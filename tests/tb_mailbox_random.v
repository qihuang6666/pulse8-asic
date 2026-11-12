`timescale 1ns/1ps
`default_nettype none
// End-to-end SPI + core test. Independent FIFO scoreboard; no DUT hierarchy.
module tb_mailbox_random;
    reg clk=0,rst_n=0,ena=1;
    reg [7:0] ui_in=4,uio_in=0;
    wire [7:0] uo_out,uio_out,uio_oe;
    tt_um_pulse8_proto dut(.*);
    always #5 clk=~clk;
    integer seed,unused,checks=0,frames=0,malformed_frames=0;
    integer sent=0,received=0,head=0,tail=0,iteration=0,choice;
    integer empty_pops=0,late_pops=0,pull_handoffs=0,full_observations=0;
    integer half_ns,phase_ns,low_extra_ns,idle_ns,bits;
    reg [7:0] expected_fifo[0:1023];
    reg [7:0] next_byte;
    reg [31:0] reply;
    reg can_enqueue=0,expect_host_error=0;

    task check(input reg condition,input string message);
        begin
            if(condition!==1'b1) begin
                $display("FAIL mailbox stress iteration=%0d sent=%0d received=%0d: %s",
                         iteration,sent,received,message);
                $fatal(1);
            end
            checks=checks+1;
        end
    endtask

    task frame(input [7:0] command,input [31:0] payload,input integer clocks,
               output [31:0] answer);
        reg [39:0] outgoing,incoming;
        integer bit_index,wait_low;
        begin
            half_ns=$urandom_range(40,100); // 4..10 system clocks minimum
            phase_ns=$urandom_range(1,29);
            outgoing={command,payload};incoming=0;
            #(phase_ns);ui_in[0]=0;ui_in[2]=0;#43;
            for(bit_index=0;bit_index<clocks;bit_index=bit_index+1) begin
                ui_in[1]=(bit_index<40)?outgoing[39-bit_index]:1'b0;
                // Independent variable low gaps exercise paused serial transfers.
                wait_low=half_ns+$urandom_range(0,120);
                #(wait_low);incoming={incoming[38:0],uo_out[0]};ui_in[0]=1;
                #(half_ns);ui_in[0]=0;
            end
            #43;ui_in[2]=1;#83;
            answer=incoming[31:0];frames=frames+1;
        end
    endtask

    task inspect_snapshot(input [31:0] answer);
        begin
            check(!answer[30],"core never faults during legal mailbox program");
            check(answer[31]==expect_host_error,"host-error flag matches framing history");
            check(uio_oe==0,"mailbox workload never enables GPIO drivers");
            if(answer[29]) begin
                check(tail>head,"RX cannot contain an unaccepted or duplicated byte");
                check(answer[23:16]==expected_fifo[head],"RX snapshot matches independent FIFO head");
            end
            can_enqueue=answer[28];
        end
    endtask

    task snapshot;
        begin frame(0,0,40,reply);inspect_snapshot(reply);end
    endtask

    task enqueue(input [7:0] value);
        begin
            // A previously observed empty TX cannot fill without this host.
            // Thus acceptance is known without inspecting internal DUT signals.
            check(can_enqueue,"only enqueue after an observed TX-ready snapshot");
            frame(4,{24'b0,value},40,reply);inspect_snapshot(reply);
            check(reply[28],"TX stayed empty between readiness observation and enqueue");
            if(reply[15:8]==0) pull_handoffs=pull_handoffs+1;
            expected_fifo[tail]=value^8'ha5;tail=tail+1;sent=sent+1;
            can_enqueue=0; // The snapshot precedes this frame's enqueue commit.
            check(tail-head<=3,"at most RX, core accumulator and TX hold pending bytes");
        end
    endtask

    task pop;
        begin
            frame(5,0,40,reply);inspect_snapshot(reply);
            if(reply[29]) begin
                head=head+1;received=received+1;
            end else begin
                empty_pops=empty_pops+1;
                // RX appeared after the returned empty snapshot. This POP must
                // preserve it; a later snapshot/pop is checked against the queue.
                if(uo_out[4]) late_pops=late_pops+1;
            end
        end
    endtask

    task malformed_enqueue;
        reg [31:0] ignored;
        begin
            if($urandom_range(0,1)) bits=$urandom_range(0,39);
            else bits=$urandom_range(41,72);
            frame(4,32'h000000d7,bits,ignored);
            malformed_frames=malformed_frames+1;
            expect_host_error=1;
            check(uo_out[7],"malformed enqueue raises host error");
            check(!uo_out[3],"malformed enqueue does not fault the core");
            // No expected byte is appended: any accidental commit is detected
            // by the FIFO comparison, byte count, or final empty-drain checks.
            frame(6,0,40,reply);inspect_snapshot(reply);
            expect_host_error=0;
            snapshot;
        end
    endtask

    initial begin
        seed=32'h6e4b2a19;unused=$urandom(seed);
        #103;rst_n=1;#101;
        // PULL; XOR 0xa5; NOP[511]; PUSH A; JMP0. The deliberate compute
        // delay lets RX arrive during POP frames with an empty RX snapshot.
        frame(8'h80,32'h90000000,40,reply);
        frame(8'h81,32'hb000a500,40,reply);
        frame(8'h82,32'h01ff0000,40,reply);
        frame(8'h83,32'ha0000000,40,reply);
        frame(8'h84,32'h60000000,40,reply);
        frame(1,0,40,reply);
        snapshot;

        // Force a genuinely full three-byte pipeline, then leave it under
        // prolonged backpressure with snapshots but no RX POP transactions.
        while(sent<3) begin
            if(can_enqueue) enqueue(8'h10+sent);
            else snapshot;
        end
        repeat(8) begin
            idle_ns=$urandom_range(500,10000);#(idle_ns);
            snapshot;
            check(reply[29] && !reply[28],"full pipeline holds RX and TX across backpressure");
            check(tail-head==3,"backpressure preserves all three pending bytes");
            full_observations=full_observations+1;
        end

        // Long seeded traffic mixes legal commands, empty POPs, pauses,
        // malformed enqueue attempts and changing frame phases/speeds.
        while(sent<512 && iteration<4000) begin
            iteration=iteration+1;
            choice=$urandom_range(0,99);
            if(iteration%31==0) malformed_enqueue;
            else if(choice<58 && can_enqueue) begin
                next_byte=$urandom;
                enqueue(next_byte);
            end else if(choice<88) pop;
            else snapshot;
            idle_ns=$urandom_range(0,300);#(idle_ns);
        end
        check(sent==512,"all 512 source bytes accepted before progress watchdog");
        while(head<tail && iteration<4100) begin
            iteration=iteration+1;pop;
        end
        check(received==512 && head==tail,"every accepted byte returned exactly once and in order");

        // No malformed frame may have inserted a trailing extra byte. Wait
        // beyond the program's compute delay before checking multiple times.
        #10000;
        repeat(8) begin
            pop;
            check(!reply[29],"drained stream contains no extra or duplicated byte");
        end
        check(!uo_out[4] && uo_out[5] && uo_out[2],"drained engine waits on empty PULL");
        check(malformed_frames>=10,"malformed frames exercised repeatedly");
        check(empty_pops>0 && late_pops>0,"empty and late-arrival POP cases were reached");
        check(pull_handoffs>0 && full_observations==8,"PULL handoff and full-backpressure cases reached");
        $display("MAILBOX STRESS PASSED: %0d bytes, %0d frames, %0d assertions, %0d malformed, %0d empty POP, %0d late-arrival POP, %0d PULL handoffs; seed=0x6e4b2a19",
                 received,frames,checks,malformed_frames,empty_pops,late_pops,pull_handoffs);
        $finish;
    end
    initial begin #100000000;$fatal(1,"mailbox stress global watchdog");end
endmodule
