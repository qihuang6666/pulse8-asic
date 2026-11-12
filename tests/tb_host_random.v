`timescale 1ns/1ps
`default_nettype none
// Independent SPI master: samples at the physical rising edge, not after CDC latency.
module tb_host_random;
    reg clk=0, rst_n=0, ena=1, sclk=0, cs_n=1, mosi=0;
    reg [31:0] response=0;
    wire miso, valid, malformed, snapshot_rx_valid;
    wire [7:0] command;
    wire [31:0] payload;
    pulse8_host_spi dut(.*);
    always #5 clk=~clk;
    integer valid_count=0, bad_count=0, assertions=0;
    reg [7:0] last_command;
    reg [31:0] last_payload;
    reg last_snapshot;
    always @(posedge clk) begin
        #1;
        if(valid) begin
            valid_count=valid_count+1;
            last_command=command; last_payload=payload;
            last_snapshot=snapshot_rx_valid;
        end
        if(malformed) bad_count=bad_count+1;
        if(valid && malformed) $fatal(1,"valid and malformed overlap");
    end
    task check(input reg condition,input string message);
        if(condition !== 1'b1) $fatal(1,"host fuzz: %s",message);
        assertions=assertions+1;
    endtask
    integer seed,throwaway,frame_number,bit_number,bits,half_ns,start_phase;
    integer before_valid,before_bad;
    reg [39:0] tx,rx;
    reg [31:0] initial_response;
    initial begin
        seed=32'h1248a5c3; throwaway=$urandom(seed);
        #103; rst_n=1; #101;
        for(frame_number=0;frame_number<240;frame_number=frame_number+1) begin
            // Include long, short, zero-clock and valid frames; 80 valid cases.
            case(frame_number%3)
                0: bits=40;
                1: bits=$urandom_range(0,39);
                2: bits=$urandom_range(41,75);
            endcase
            half_ns=$urandom_range(40,100); // >= four system clocks
            start_phase=$urandom_range(1,19);
            tx={$urandom,$urandom}; rx=0;
            initial_response=$urandom;
            response=initial_response;
            before_valid=valid_count; before_bad=bad_count;
            #(start_phase); cs_n=0; #43;
            for(bit_number=0;bit_number<bits;bit_number=bit_number+1) begin
                mosi=(bit_number<40) ? tx[39-bit_number] : $urandom_range(0,1);
                #(half_ns);
                // Check data before the DUT can observe this new rising edge.
                rx={rx[38:0],miso}; sclk=1;
                #(half_ns); sclk=0;
                if(bit_number==7) response=~initial_response;
            end
            #43; cs_n=1; #83;
            if(bits==40) begin
                check(valid_count==before_valid+1,"one commit for a 40-bit frame");
                check(bad_count==before_bad,"no malformed pulse on valid frame");
                check(last_command==tx[39:32],"command byte preserved");
                check(last_payload==tx[31:0],"payload preserved");
                check(rx[31:0]==initial_response,"snapshot remains stable across response changes");
                check(last_snapshot==initial_response[29],"RX snapshot flag belongs to returned data");
            end else begin
                check(valid_count==before_valid,"malformed frame cannot commit");
                check(bad_count==before_bad+1,"one error per malformed frame");
            end
            check(miso==0,"MISO idle value");
        end
        $display("HOST PHASE/FRAMING TESTS PASSED: 240 frames, %0d assertions, seed=0x1248a5c3",assertions);
        $finish;
    end
    initial begin #10000000; $fatal(1,"host fuzz watchdog"); end
endmodule
