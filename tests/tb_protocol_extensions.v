`timescale 1ns/1ps
`default_nettype none
// External protocol agents see only pins and the documented host interface.
// There are no hierarchical DUT accesses or direct instruction-memory writes.
module tb_protocol_extensions;
    reg clk=0, rst_n=0, ena=1;
    reg [7:0] ui_in=4, external_level=255, external_low=0;
    wire [7:0] uo_out, uio_out, uio_oe, uio_in;
    assign uio_in=((uio_out & uio_oe) | (external_level & ~uio_oe)) & ~external_low;
    tt_um_pulse8_proto dut(.*);
    always #20.833333 clk=~clk;
    integer checks=0, cycle=0, scenario;
    reg [31:0] image[0:63], reply;
    reg [7:0] vector_byte;
    `include "program_sizes.vh"
    always @(posedge clk) cycle<=cycle+1;

    task step(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask

    task uart_fault_receiver(input [7:0] expected);
        integer t,bit_index;
        reg level;
        begin
            while(!(uio_oe[0] && !uio_out[0])) step(1);
            for(t=0;t<2288;t=t+1) begin
                bit_index=t/208;
                if(bit_index==0 || bit_index==9) level=0;
                else if(bit_index==10) level=1;
                else level=expected[bit_index-1];
                check(uio_oe[0] && uio_in[0]==level,"fault stimulus exact UART waveform and idle recovery");
                if(t==1976) check(!uio_in[0],"independent receiver detects low stop bit at its center");
                step(1);
            end
            check(!uo_out[3] && uio_in[0],"intentional protocol error leaves core healthy and line idle");
        end
    endtask
    task check(input reg condition,input string message);
        if(condition !== 1'b1) begin
            $display("FAIL protocol extensions cycle=%0d: %s",cycle,message);
            $fatal(1);
        end
        checks=checks+1;
    endtask
    task reset_device;
        rst_n=0; ena=1; ui_in=4; external_level=255; external_low=0;
        step(5); rst_n=1; step(6);
    endtask
    task frame(input [7:0] command,input [31:0] data,output [31:0] answer);
        reg [39:0] outgoing,incoming;
        integer k;
        begin
            outgoing={command,data}; incoming=0;
            ui_in[0]=0; ui_in[2]=0; step(4);
            for(k=0;k<40;k=k+1) begin
                ui_in[1]=outgoing[39-k]; step(4);
                // Sample at the real master's edge, before slave synchronizers.
                incoming={incoming[38:0],uo_out[0]};
                ui_in[0]=1; step(4); ui_in[0]=0;
            end
            step(4); ui_in[2]=1; step(6); answer=incoming[31:0];
        end
    endtask
    task send(input [7:0] command,input [31:0] data);
        reg [31:0] ignored;
        frame(command,data,ignored);
    endtask
    task load_program(input string filename,input integer words);
        integer n;
        begin
            $readmemh(filename,image,0,words-1);
            for(n=0;n<words;n=n+1) send(8'h80+n,image[n]);
        end
    endtask
    task read_byte(input [7:0] expected);
        frame(5,0,reply);
        check(reply[29],"RX snapshot valid");
        check(reply[23:16]==expected,"host RX matches independently supplied target byte");
        check(!reply[31] && !reply[30],"host and core report no fault");
    endtask

    // Receives bus bytes and responds like an I2C target. nack_at=0 means ACK
    // all bytes, otherwise NACK the 1-based transmitted byte. stretch_at is
    // 0 (none), 1 (write-address), 2 (read-data), 3 (controller NACK clock).
    task i2c_target(input reg register_phase,input [7:0] register_pointer,
                    input [7:0] target_data,input integer nack_at,
                    input integer stretch_at);
        integer starts,rises,guard,byte_index,stretch_left,fall_cycle,rise_cycle;
        reg old_scl,old_sda,scl,sda,done,stretched,expect_ack;
        reg [7:0] received;
        begin
            starts=0; rises=0; guard=0; byte_index=0; stretch_left=0;
            done=0; stretched=0; received=0; fall_cycle=0; rise_cycle=0;
            old_scl=1; old_sda=1;
            while(!done && guard<30000 && !uo_out[3]) begin
                step(1); guard=guard+1;
                check((uio_oe[1:0] & uio_out[1:0])==0,"I2C never drives SDA/SCL high");
                if(stretch_left>0) begin
                    stretch_left=stretch_left-1;
                    if(stretch_left==0) external_low[1]=0;
                end
                scl=uio_in[1]; sda=uio_in[0];
                if(old_scl && scl && old_sda && !sda) begin
                    starts=starts+1; rises=0; received=0;
                    check(starts<=2,"exactly initial and repeated START permitted");
                end
                if(starts>0 && !old_scl && scl) begin
                    check(cycle-fall_cycle>=120,"I2C minimum low duration is five microseconds");
                    rise_cycle=cycle; rises=rises+1;
                    if(rises<=8 || (starts==1 && register_phase && rises>=10 && rises<=17))
                        received={received[6:0],sda};
                    if(rises==9 || (starts==1 && register_phase && rises==18)) begin
                        byte_index=byte_index+1;
                        expect_ack=byte_index!=nack_at;
                        check(sda==!expect_ack,"target ACK/NACK appears on ninth clock");
                        if(rises==9) check(received==(starts==1 ? 8'ha0 : 8'ha1),"decoded I2C address and direction");
                        else check(received==register_pointer,"decoded host-provided register pointer");
                        received=0;
                    end
                    if(starts==2 && rises>=10 && rises<=17)
                        check(sda==target_data[17-rises],"target data byte observed on bus");
                    if(starts==2 && rises==18) check(sda,"controller NACKs final read byte");
                end
                if(starts>0 && old_scl && !scl) begin
                    if(rise_cycle!=0) check(cycle-rise_cycle>=120,"I2C minimum high duration is five microseconds");
                    fall_cycle=cycle;
                    if(rises==8 || (starts==1 && register_phase && rises==17))
                        external_low[0]=(byte_index+1!=nack_at);
                    else if(starts==2 && rises>=9 && rises<=16)
                        external_low[0]=!target_data[16-rises];
                    else external_low[0]=0;
                    if(!stretched && ((stretch_at==1 && starts==1 && rises==3) ||
                        (stretch_at==2 && starts==2 && rises==12) ||
                        (stretch_at==3 && starts==2 && rises==17))) begin
                        external_low[1]=1; stretch_left=480; stretched=1;
                    end
                end
                if(starts>0 && old_scl && scl && !old_sda && sda) done=1;
                old_scl=scl; old_sda=sda;
            end
            if(nack_at==0) begin
                check(done && starts==2,"one repeated START and one final STOP");
                check(rises==19,"eight read bits, NACK and STOP clock after address ACK");
                check(byte_index==(register_phase ? 3 : 2),"all transmitted byte ACKs decoded");
                if(stretch_at!=0) check(stretched,"requested target clock stretch occurred");
            end else begin
                check(uo_out[3] && uio_oe==0,"injected NACK causes fault and releases pads");
                check(byte_index==nack_at,"NACK stops before the next transmitted byte");
            end
            external_low=0;
        end
    endtask

    // Complete IEEE 1149.1 TAP state transition graph. Data behavior models
    // a 4-bit IR (instruction2 selects an8-bit DR); it is not an IDCODE model.
    function integer next_tap(input integer state,input reg tms);
        case(state)
            0: next_tap=tms?0:1;   // Test-Logic-Reset
            1: next_tap=tms?2:1;   // Run-Test/Idle
            2: next_tap=tms?9:3;   // Select-DR
            3: next_tap=tms?5:4;   // Capture-DR
            4: next_tap=tms?5:4;   // Shift-DR
            5: next_tap=tms?8:6;   // Exit1-DR
            6: next_tap=tms?7:6;   // Pause-DR
            7: next_tap=tms?8:4;   // Exit2-DR
            8: next_tap=tms?2:1;   // Update-DR
            9: next_tap=tms?0:10;  // Select-IR
            10: next_tap=tms?12:11;
            11: next_tap=tms?12:11;
            12: next_tap=tms?15:13;
            13: next_tap=tms?14:13;
            14: next_tap=tms?15:11;
            15: next_tap=tms?2:1;
            default: next_tap=0;
        endcase
    endfunction
    task jtag_target(input [7:0] transmitted,input [7:0] captured,input integer initial_state);
        integer state,rises,shift_bits,updates,guard,last_rise,last_fall,ir_bits;
        reg old_tck,tck,selected;
        reg [7:0] scan;
        reg [3:0] ir_scan;
        begin
            state=initial_state; rises=0; shift_bits=0; updates=0; guard=0;
            last_rise=0; last_fall=0; old_tck=0; scan=0;
            ir_scan=0; ir_bits=0; selected=0;
            while(!uo_out[2]) step(1);
            while(uo_out[2] && guard<15000) begin
                step(1); guard=guard+1; tck=uio_in[0];
                check(uio_oe==7,"JTAG only TCK/TMS/TDI are driven");
                if(!old_tck && tck) begin
                    if(last_fall!=0) check(cycle-last_fall>=120,"JTAG clock low time at least 120 cycles");
                    last_rise=cycle; rises=rises+1;
                    if(state==10 && rises>5) ir_scan=1;
                    if(state==11 && rises>5) begin
                        check(ir_bits<4,"JTAG instruction scan has four bits");
                        ir_scan={uio_in[2],ir_scan[3:1]}; ir_bits=ir_bits+1;
                    end
                    if(state==15 && rises>5) begin
                        check(ir_scan==2,"JTAG selects target-specific instruction2");
                        selected=1;
                    end
                    if(state==3 && rises>5) begin
                        check(selected,"JTAG instruction selected before DR capture");
                        scan=captured;
                    end
                    if(state==4 && rises>5) begin
                        check(shift_bits<8,"JTAG shifts no extra data bits");
                        check(uio_in[2]==transmitted[shift_bits],"JTAG TDI LSB-first payload");
                        scan={uio_in[2],scan[7:1]}; shift_bits=shift_bits+1;
                    end
                    if(state==8 && rises>5) begin
                        check(scan==transmitted,"JTAG Update-DR contains transmitted byte");
                        updates=updates+1;
                    end
                    state=next_tap(state,uio_in[1]);
                    if(rises==5) check(state==0,"five TMS-high clocks reset arbitrary TAP state");
                end
                if(old_tck && !tck) begin
                    check(cycle-last_rise==120,"JTAG TCK high duration exactly 120 cycles");
                    last_fall=cycle;
                    external_level[3]=(state==4) ? scan[0] : 1'b1;
                end
                old_tck=tck;
            end
            check(guard<15000 && !uo_out[3],"JTAG completes without fault");
            check(rises==29 && ir_bits==4 && shift_bits==8 && updates==1,"JTAG complete reset, IR select, DR scan and update");
            check(state==1 && !uio_out[0] && !uio_out[1],"JTAG ends Run-Test/Idle with TCK/TMS low");
        end
    endtask

    initial begin
        for(scenario=0;scenario<4;scenario=scenario+1) begin
            case(scenario)
                0: vector_byte=8'h00;
                1: vector_byte=8'hff;
                2: vector_byte=8'ha5;
                3: vector_byte=8'h96;
            endcase
            reset_device; load_program("work/i2c_register_read.hex",I2C_REGISTER_READ_WORDS);
            send(3,3); send(4,vector_byte);
            fork
                i2c_target(1,vector_byte,~vector_byte,0,0);
                send(1,0);
            join
            step(130); read_byte(~vector_byte);
        end
        $display("PASS I2C register pointer/repeated START/read/NACK/STOP: four payloads");
        for(scenario=0;scenario<4;scenario=scenario+1) begin
            reset_device; load_program("work/i2c_restart_read.hex",I2C_RESTART_READ_WORDS);
            send(3,3);
            fork
                i2c_target(0,0,8'h69,0,scenario);
                send(1,0);
            join
            step(130); read_byte(8'h69);
        end
        $display("PASS I2C repeated START read with target stretches in address, data and NACK");
        for(scenario=1;scenario<=3;scenario=scenario+1) begin
            reset_device; load_program("work/i2c_register_read.hex",I2C_REGISTER_READ_WORDS);
            send(3,3); send(4,8'h12);
            fork
                i2c_target(1,8'h12,8'h69,scenario,0);
                send(1,0);
            join
        end
        $display("PASS I2C injected NACK at both address phases and register-data phase");
        for(scenario=0;scenario<16;scenario=scenario+1) begin
            vector_byte=8'ha6 ^ (scenario*17);
            reset_device; load_program("work/jtag_dr8.hex",JTAG_DR8_WORDS);
            send(4,vector_byte);
            fork
                jtag_target(vector_byte,~vector_byte,scenario);
                send(1,0);
            join
            read_byte(~vector_byte);
        end
        $display("PASS JTAG full TAP monitor from all 16 initial states and 16 payloads");
        for(scenario=0;scenario<2;scenario=scenario+1) begin
            vector_byte=(scenario==0)?8'ha5:8'h00;
            reset_device; load_program("work/uart_bad_stop.hex",UART_BAD_STOP_WORDS);
            send(4,vector_byte);
            fork
                uart_fault_receiver(vector_byte);
                send(1,0);
            join
        end
        $display("PASS programmed UART framing-error stimulus with idle recovery: two payloads");
        $display("ALL PROTOCOL EXTENSION TESTS PASSED: %0d assertions",checks);
        $finish;
    end
    initial begin #200000000; $fatal(1,"protocol extension watchdog"); end
endmodule
