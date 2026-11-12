`timescale 1ns/1ps
`default_nettype none
module tb_system;
    reg clk=0, rst_n=0, ena=1;
    reg [7:0] ui_in=4, external_level=255, external_low=0;
    wire [7:0] uo_out, uio_out, uio_oe, uio_in;
    assign uio_in = ((uio_out & uio_oe) | (external_level & ~uio_oe)) & ~external_low;
    tt_um_pulse8_proto dut(.*);
    always #20.833333 clk=~clk;
    integer checks=0, cycle=0;
    always @(posedge clk) cycle <= cycle+1;
    reg [31:0] image[0:63];
    reg [31:0] reply;
    integer i, mode;
    `include "program_sizes.vh"

    task step(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    task check(input reg condition, input string message);
        if (condition !== 1'b1) begin
            $display("FAIL cycle=%0d: %s", cycle, message);
            $fatal(1);
        end
        checks=checks+1;
    endtask
    task reset_device;
        rst_n=0; ena=1; ui_in=4; external_level=255; external_low=0;
        step(5); check(uio_oe==0,"reset releases all pads");
        rst_n=1; step(6);
    endtask
    task frame(input [7:0] command, input [31:0] data, input integer bits,
               output [31:0] answer);
        reg [39:0] send_bits, read_bits;
        integer k;
        begin
            send_bits={command,data}; read_bits=0;
            ui_in[0]=0; ui_in[2]=0; step(4);
            for(k=0;k<bits;k=k+1) begin
                ui_in[1]=(k<40) ? send_bits[39-k] : 1'b0;
                step(4); ui_in[0]=1; step(4);
                read_bits={read_bits[38:0],uo_out[0]};
                ui_in[0]=0;
            end
            step(4); ui_in[2]=1; step(6);
            answer=read_bits[31:0];
        end
    endtask
    task send(input [7:0] command,input [31:0] data);
        reg [31:0] ignored;
        frame(command,data,40,ignored);
    endtask
    task put(input integer address,input [31:0] word);
        send(8'h80+address,word);
    endtask
    task load_program(input string filename,input integer length);
        integer n;
        begin
            $readmemh(filename,image,0,length-1);
            for(n=0;n<length;n=n+1) put(n,image[n]);
        end
    endtask
    task read_byte(input [7:0] expected);
        reg [31:0] r;
        frame(5,0,40,r);
        check(r[29],"RX snapshot valid");
        check(r[23:16]==expected,"received byte matches independent expectation");
        check(!r[31] && !r[30],"no host/core fault");
    endtask

    task uart_monitor(input [7:0] value);
        integer t, bit_index;
        reg expected;
        begin
            while(!(uio_oe[0] && !uio_out[0])) step(1);
            for(t=0;t<2080;t=t+1) begin
                bit_index=t/208;
                expected=(bit_index==0) ? 0 : ((bit_index==9) ? 1 : value[bit_index-1]);
                check(uio_out[0]==expected && uio_oe[0],"UART exact 208-cycle bit waveform");
                step(1);
            end
        end
    endtask
    task uart_source(input [7:0] value,input reg good_stop);
        integer k;
        begin
            step(20); external_level[0]=0; step(208);
            for(k=0;k<8;k=k+1) begin external_level[0]=value[k]; step(208); end
            external_level[0]=good_stop; step(208);
            external_level[0]=1; step(20);
        end
    endtask

    task spi_target(input integer spi_mode,input [7:0] tx,input [7:0] rx);
        integer samples,edges,last_edge;
        reg cpol,cpha,old_sck,new_sck;
        begin
            cpol=(spi_mode>>1)&1; cpha=spi_mode&1;
            samples=0; edges=0; last_edge=0; old_sck=cpol;
            external_level[2]=rx[7];
            while(!(uio_oe[3] && !uio_out[3])) step(1);
            while(!uio_out[3]) begin
                step(1); new_sck=uio_out[0];
                if(new_sck!=old_sck) begin
                    if(edges!=0) check(cycle-last_edge==120,"SPI exact 120-cycle half period");
                    last_edge=cycle; edges=edges+1;
                    if((!cpha && new_sck!=cpol) || (cpha && new_sck==cpol)) begin
                        check(samples<8,"SPI has at most eight sample edges");
                        check(uio_out[1]==tx[7-samples],"SPI MOSI byte on correct edge");
                        samples=samples+1;
                    end
                    if((!cpha && new_sck==cpol) || (cpha && new_sck!=cpol)) begin
                        if(samples<8) external_level[2]=rx[7-samples];
                    end
                    old_sck=new_sck;
                end
            end
            check(samples==8 && edges==16,"SPI one complete full-duplex byte");
            check(uio_out[0]==cpol,"SPI returns to idle polarity");
        end
    endtask

    task i2c_target(input [7:0] expected_data,input reg stretch);
        integer rises,stretch_left,guard;
        reg old_scl,old_sda,new_scl,new_sda,done,stretched;
        reg [7:0] address_byte,data_byte;
        begin
            rises=0; stretch_left=0; guard=0; done=0; stretched=0;
            address_byte=0; data_byte=0;
            while(!(uio_in[1] && !uio_in[0])) step(1);
            old_scl=uio_in[1]; old_sda=uio_in[0];
            while(!done && guard<20000) begin
                step(1); guard=guard+1;
                check((uio_oe[1:0]&uio_out[1:0])==0,"I2C never actively drives high");
                if(stretch_left>0) begin
                    stretch_left=stretch_left-1;
                    if(stretch_left==0) external_low[1]=0;
                end
                new_scl=uio_in[1]; new_sda=uio_in[0];
                if(!old_scl && new_scl) begin
                    rises=rises+1;
                    if(rises<=8) address_byte={address_byte[6:0],new_sda};
                    if(rises>=10 && rises<=17) data_byte={data_byte[6:0],new_sda};
                    if(rises==9 || rises==18) check(!new_sda,"I2C target ACK visible");
                end
                if(old_scl && !new_scl) begin
                    if(rises==8 || rises==17) external_low[0]=1;
                    else external_low[0]=0;
                    if(stretch && rises==2 && !stretched) begin
                        external_low[1]=1; stretch_left=300; stretched=1;
                    end
                end
                if(old_scl && new_scl && !old_sda && new_sda) done=1;
                old_scl=new_scl; old_sda=new_sda;
            end
            check(done,"I2C STOP observed");
            // STOP generation includes one final rising SCL transition.
            check(rises==19,"I2C address/data/ACK clocks plus STOP");
            check(address_byte==8'ha0,"I2C address 0x50 write");
            check(data_byte==expected_data,"I2C data byte decoded");
            if(stretch) check(stretched,"I2C stretch injected");
        end
    endtask

    initial begin
        if($test$plusargs("waves")) begin $dumpfile("work/system.vcd"); $dumpvars(0,tb_system); end
        reset_device;
        send(1,0); step(4);
        check(uo_out[3] && uio_oe==0,"unloaded instruction faults safely");
        frame(0,0,40,reply); check(reply[26:24]==1,"unloaded fault code");

        reset_device;
        put(0,32'h1000ffff); put(1,32'hf0000000); send(1,0); step(4);
        check(uio_oe==255 && uio_out==255,"HALT preserves final driven levels");
        ena=0; #1; check(uio_oe==0,"deselect immediately releases outputs");
        step(4); ena=1; step(4); send(1,0);
        check(uo_out[3],"deselect invalidates program");

        for(i=39;i<=41;i=i+2) begin
            reset_device;
            frame(8'h80,32'hf0000000,i,reply);
            check(uo_out[7],"malformed frame sets host error");
            send(1,0); step(4); check(uo_out[3],"malformed write is not committed");
        end
        reset_device;
        send(8'hc0,32'hf0000000); check(uo_out[7],"reserved host opcode rejected");

        reset_device; external_level=0;
        put(0,32'h10000101); put(1,32'h80000701); put(2,32'h60000000);
        send(1,0); put(0,32'h1000ffff);
        check(uo_out[7] && uio_out==1,"writes while running rejected");
        send(2,0); check(uio_oe==0 && !uo_out[2],"STOP cancels blocking WAIT");
        send(6,0); check(!uo_out[7],"clear host error");
        send(1,0); check(uio_out==1,"rejected program write had no effect");
        rst_n=0; #1; check(uio_oe==0,"reset assertion releases outputs");

        reset_device; external_level=0;
        put(0,32'h10007f7f); put(1,32'h800a0701); send(1,0); step(20);
        check(uo_out[3] && uio_oe==0,"bounded WAIT timeout releases bus");
        frame(0,0,40,reply); check(reply[26:24]==2,"WAIT timeout fault code");
        reset_device; put(0,32'h40000800); send(1,0);
        frame(0,0,40,reply); check(reply[26:24]==3,"invalid pin operand faults");

        reset_device;
        put(0,32'h90000000); put(1,32'ha0000000);
        put(2,32'h90000000); put(3,32'ha0000000); put(4,32'hf0000000);
        send(4,8'h42); send(4,8'h99); check(uo_out[7],"TX overflow rejected");
        send(6,0); send(1,0); send(4,8'h7e);
        check(uo_out[2] && uo_out[4],"RX backpressure stalls PUSH");
        read_byte(8'h42); step(5); read_byte(8'h7e);
        check(!uo_out[2] && !uo_out[4],"mailboxes preserve order and empty correctly");

        reset_device;
        put(0,32'h20005500); put(1,32'h00c70000); put(2,32'ha0000000); put(3,32'hf0000000);
        send(1,0); frame(5,0,40,reply);
        check(!reply[29] && uo_out[4],"RX arriving after snapshot is not discarded");
        read_byte(8'h55);

        reset_device;
        load_program("work/isa.hex",ISA_WORDS); send(1,0); step(100);
        check(uio_out==8'h5f && uio_oe==255,"masked GPIO writes preserve unmasked bits");
        read_byte(3);
        $display("PASS safety, host framing, mailboxes, arithmetic and branches");

        for(i=0;i<4;i=i+1) begin
            reset_device; load_program("work/uart_tx.hex",UART_TX_WORDS);
            case(i)
                0: send(4,8'h55);
                1: send(4,8'ha5);
                2: send(4,8'h00);
                3: send(4,8'hff);
            endcase
            fork
                begin
                    case(i)
                        0: uart_monitor(8'h55);
                        1: uart_monitor(8'ha5);
                        2: uart_monitor(8'h00);
                        3: uart_monitor(8'hff);
                    endcase
                end
                send(1,0);
            join
            check(!uo_out[3],"UART TX no fault");
        end
        reset_device; load_program("work/uart_rx.hex",UART_RX_WORDS); send(1,0);
        uart_source(8'h96,1); read_byte(8'h96);
        reset_device; load_program("work/uart_rx.hex",UART_RX_WORDS); send(1,0);
        uart_source(8'h96,0); check(uo_out[3],"UART RX rejects low stop bit");
        $display("PASS UART TX exact timing and UART RX framing");

        for(mode=0;mode<4;mode=mode+1) begin
            reset_device;
            load_program($sformatf("work/spi_mode%0d.hex",mode),SPI_MODE0_WORDS);
            send(4,8'ha5);
            fork
                spi_target(mode,8'ha5,8'h3c);
                send(1,0);
            join
            step(5); read_byte(8'h3c);
        end
        $display("PASS SPI modes 0, 1, 2, 3 full duplex at exact 100 kHz equivalent");

        for(mode=0;mode<2;mode=mode+1) begin
            reset_device; load_program("work/i2c_write.hex",I2C_WRITE_WORDS);
            send(3,3); send(4,8'h5a);
            fork
                i2c_target(8'h5a,mode!=0);
                send(1,0);
            join
            step(150); read_byte(0);
        end
        reset_device; load_program("work/i2c_write.hex",I2C_WRITE_WORDS);
        send(3,3); send(4,8'h5a); send(1,0); step(5000);
        check(uo_out[3] && uio_oe==0,"I2C NACK faults and releases bus");
        reset_device; load_program("work/i2c_write.hex",I2C_WRITE_WORDS);
        external_low[1]=1; send(3,3); send(4,8'h5a); send(1,0); step(4500);
        check(uo_out[3] && uio_oe==0,"I2C stuck SCL timeout");
        $display("PASS I2C address/data, ACK, stretching, NACK and stuck-clock timeout");
        $display("ALL RTL TESTS PASSED: %0d assertions",checks);
        $finish;
    end
    initial begin #200000000; $fatal(1,"global simulation watchdog"); end
endmodule
