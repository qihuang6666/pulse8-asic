// SPDX-License-Identifier: Apache-2.0
`default_nettype none
`timescale 1ns/1ps

// Oversampled SPI mode 0, MSB first. Exactly 40 clocks per CS assertion.
// All pins cross into clk through two flip-flops; no derived clock domain.
module pulse8_host_spi (
    input wire clk, input wire rst_n, input wire ena,
    input wire sclk, input wire cs_n, input wire mosi,
    input wire [31:0] response,
    output wire miso,
    output reg valid, output reg malformed,
    output reg [7:0] command, output reg [31:0] payload,
    output reg snapshot_rx_valid
);
    (* async_reg = "true" *) reg [1:0] sck_sync, cs_sync, mosi_sync;
    reg sck_last, cs_last;
    reg [5:0] count;
    reg overflow;
    reg [39:0] request_shift;
    reg [31:0] reply_shift;
    wire rising = sck_sync[1] && !sck_last;
    wire falling = !sck_sync[1] && sck_last;
    assign miso = (!cs_sync[1] && count >= 8) ? reply_shift[31] : 1'b0;

    always @(posedge clk) begin
        if (!rst_n || !ena) begin
            sck_sync <= 0; cs_sync <= 2'b11; mosi_sync <= 0;
            sck_last <= 0; cs_last <= 1;
            count <= 0; overflow <= 0; request_shift <= 0;
            reply_shift <= 0; valid <= 0; malformed <= 0;
            command <= 0; payload <= 0; snapshot_rx_valid <= 0;
        end else begin
            sck_sync <= {sck_sync[0], sclk};
            cs_sync <= {cs_sync[0], cs_n};
            mosi_sync <= {mosi_sync[0], mosi};
            sck_last <= sck_sync[1]; cs_last <= cs_sync[1];
            valid <= 0; malformed <= 0;
            if (!cs_sync[1] && cs_last) begin
                count <= 0; overflow <= 0; request_shift <= 0;
                reply_shift <= 0; snapshot_rx_valid <= 0;
            end else if (cs_sync[1] && !cs_last) begin
                if (count == 40 && !overflow) begin
                    command <= request_shift[39:32];
                    payload <= request_shift[31:0];
                    valid <= 1;
                end else malformed <= 1;
            end else if (!cs_sync[1]) begin
                if (rising) begin
                    if (count < 40) begin
                        request_shift <= {request_shift[38:0], mosi_sync[1]};
                        count <= count + 1'b1;
                        if (count == 7) begin
                            reply_shift <= response;
                            snapshot_rx_valid <= response[29];
                        end
                    end else overflow <= 1;
                end
                // Keep bit 31 stable through the ninth rising edge.
                if (falling && count > 8) reply_shift <= {reply_shift[30:0], 1'b0};
            end
        end
    end
endmodule
