// SPDX-License-Identifier: Apache-2.0
`default_nettype none
`timescale 1ns/1ps

module tt_um_pulse8_proto (
    input wire [7:0] ui_in, output wire [7:0] uo_out,
    input wire [7:0] uio_in, output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, input wire clk, input wire rst_n
);
    reg [31:0] program_mem [0:63]; // Deliberately not reset: guarded by loaded.
    reg [63:0] loaded;
    reg [5:0] pc;
    reg [7:0] acc, isr, x, pins, direction, open_drain;
    reg [11:0] delay_left, wait_count;
    reg [15:0] elapsed;
    wire [15:0] elapsed_next = elapsed == 16'hffff ? elapsed : elapsed + 1'b1;
    reg running, fault, host_error;
    reg [2:0] fault_code;
    reg [7:0] tx_data, rx_data;
    reg tx_valid, rx_valid;
    (* async_reg = "true" *) reg [7:0] input_meta, input_sync;
    wire [31:0] instruction = program_mem[pc];
    wire [3:0] op = instruction[31:28];
    wire [11:0] delay_value = instruction[27:16];
    wire [7:0] a = instruction[15:8], b = instruction[7:0];
    wire [7:0] status = {host_error, fault, rx_valid, !tx_valid, running, fault_code};
    wire [31:0] response = {status, rx_data, 2'b00, pc, acc};
    wire command_valid, malformed, snapshot_rx_valid, miso;
    wire [7:0] command;
    wire [31:0] payload;
    wire start_cmd = command_valid && command == 8'h01 && !running;
    wire stop_cmd = command_valid && command == 8'h02;

    pulse8_host_spi host (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .sclk(ui_in[0]), .mosi(ui_in[1]), .cs_n(ui_in[2]),
        .response(response), .miso(miso), .valid(command_valid),
        .malformed(malformed), .command(command), .payload(payload),
        .snapshot_rx_valid(snapshot_rx_valid)
    );
    // Status is also available without a serial transaction.
    assign uo_out = {host_error, 1'b0, !tx_valid, rx_valid, fault, running, 1'b0, miso};
    assign uio_out = pins;
    assign uio_oe = (rst_n && ena && !fault) ? direction & ~(open_drain & pins) : 8'b0;
    wire _unused = &{1'b0, ui_in[7:3], payload[31:8]};

    always @(posedge clk) begin
        if (!rst_n || !ena) begin
            loaded <= 0; pc <= 0; acc <= 0; isr <= 0; x <= 0;
            pins <= 0; direction <= 0; open_drain <= 0;
            delay_left <= 0; wait_count <= 0; elapsed <= 0;
            running <= 0; fault <= 0; fault_code <= 0; host_error <= 0;
            tx_data <= 0; rx_data <= 0; tx_valid <= 0; rx_valid <= 0;
            input_meta <= 0; input_sync <= 0;
        end else begin
            input_meta <= uio_in;
            input_sync <= input_meta;
            if (malformed) host_error <= 1;
            if (command_valid) begin
                if (command[7:6] == 2'b10) begin
                    if (!running) begin
                        program_mem[command[5:0]] <= payload;
                        loaded[command[5:0]] <= 1;
                    end else host_error <= 1;
                end else begin
                    case (command)
                        8'h00: begin end // Read snapshot; no side effects.
                        8'h01: if (running) host_error <= 1;
                        8'h02: begin end // STOP has priority over execution below.
                        8'h03: if (!running) open_drain <= payload[7:0];
                               else host_error <= 1;
                        8'h04: if (!tx_valid) begin tx_data <= payload[7:0]; tx_valid <= 1; end
                               else host_error <= 1;
                        // Pop only the byte actually captured in this frame.
                        8'h05: if (snapshot_rx_valid) rx_valid <= 0;
                        8'h06: host_error <= 0;
                        default: host_error <= 1;
                    endcase
                end
            end

            if (stop_cmd) begin
                running <= 0; direction <= 0; delay_left <= 0; wait_count <= 0;
                tx_valid <= 0; rx_valid <= 0;
            end else if (start_cmd) begin
                running <= 1; fault <= 0; fault_code <= 0;
                pc <= 0; acc <= 0; isr <= 0; x <= 0; pins <= 0; direction <= 0;
                delay_left <= 0; wait_count <= 0; rx_valid <= 0; elapsed <= 0;
                // Preserve a preloaded TX byte and the open-drain configuration.
            end else if (running) begin
                // Count all running edges, including delays and mailbox/WAIT stalls.
                // Saturation makes an overlong measurement explicit instead of wrapping.
                elapsed <= elapsed_next;
                if (delay_left != 0) delay_left <= delay_left - 1'b1;
                else if (!loaded[pc]) begin
                    fault <= 1; fault_code <= 1; running <= 0; direction <= 0;
                end else if (((op == 4 || op == 5 || op == 8) && a > 7) ||
                             ((op == 6 || op == 7 || op == 13) && a > 63) ||
                             (op == 0 && a == 4 && b > 63)) begin
                    fault <= 1; fault_code <= 3; running <= 0; direction <= 0;
                end else begin
                    // Completed instructions advance by default. Blocking ops override.
                    pc <= pc + 1'b1;
                    delay_left <= delay_value;
                    wait_count <= 0;
                    case (op)
                        4'h0: case (a)
                            // Extension selectors occupy formerly unused NOP operands.
                            // Canonical NOP (a=b=0) and all old assembler output are unchanged.
                            8'h01: acc <= isr;
                            8'h02: acc <= input_sync & b;
                            8'h03: acc <= acc & b;
                            8'h04: if (acc != 0) pc <= b[5:0];
                            8'h05: elapsed <= 0;
                            // Capture the value at this edge coherently across both bytes.
                            8'h06: begin acc <= elapsed_next[7:0]; isr <= elapsed_next[15:8]; end
                            default: begin end
                        endcase
                        4'h1: begin pins <= a; direction <= b; end
                        4'h2: acc <= a;
                        4'h3: x <= a;
                        4'h4: begin
                            pins[a[2:0]] <= b[0] ? acc[7] : acc[0];
                            acc <= b[0] ? {acc[6:0], 1'b0} : {1'b0, acc[7:1]};
                        end
                        4'h5: isr <= b[0] ? {isr[6:0], input_sync[a[2:0]]} :
                                                   {input_sync[a[2:0]], isr[7:1]};
                        4'h6: pc <= a[5:0];
                        4'h7: if (x > 1) begin x <= x - 1'b1; pc <= a[5:0]; end
                              else x <= 0;
                        4'h8: begin
                            delay_left <= 0;
                            if (input_sync[a[2:0]] != b[0]) begin
                                pc <= pc;
                                if (delay_value != 0 && wait_count == delay_value - 1'b1) begin
                                    fault <= 1; fault_code <= 2; running <= 0; direction <= 0;
                                end else if (delay_value != 0) wait_count <= wait_count + 1'b1;
                            end
                        end
                        4'h9: if (tx_valid) begin acc <= tx_data; tx_valid <= 0; end
                              else begin pc <= pc; delay_left <= 0; end
                        4'ha: if (!rx_valid) begin rx_data <= a[0] ? isr : acc; rx_valid <= 1; end
                              else begin pc <= pc; delay_left <= 0; end
                        4'hb: acc <= acc ^ a;
                        4'hc: acc <= acc + a;
                        4'hd: if (acc == 0) pc <= a[5:0];
                        4'he: pins <= (pins & ~b) | (a & b);
                        4'hf: begin running <= 0; pc <= pc; end // Preserve final output levels.
                    endcase
                end
            end
        end
    end
`ifdef PULSE8_FORMAL_CORE
`include "core_properties.vh"
`endif
endmodule
