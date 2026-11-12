// Verification-only properties. Included with -D PULSE8_FORMAL_CORE.
// Proof starts with a reset edge; instruction memory remains arbitrary.
    reg f_past_valid=0;
    (* anyconst *) reg [5:0] f_address;
    wire f_active=rst_n && ena;
    wire f_load=command_valid && command[7:6]==2'b10 && !running;
    wire f_pop=command_valid && command==5 && snapshot_rx_valid;
    wire f_enqueue=command_valid && command==4 && !tx_valid;
    wire f_execute=running && delay_left==0 && loaded[pc] && !stop_cmd;
    (* keep *) reg f_cover_write_blocked=0;
    (* keep *) reg f_cover_push_blocked=0;
    (* keep *) reg f_cover_rx_pop=0;
    (* keep *) reg f_cover_wait_timeout=0;

    always @(posedge clk) begin
        f_past_valid<=1;
        if(!f_active) begin
            f_cover_write_blocked<=0; f_cover_push_blocked<=0;
            f_cover_rx_pop<=0; f_cover_wait_timeout<=0;
        end else begin
            if(running && command_valid && command[7:6]==2'b10) f_cover_write_blocked<=1;
            if(f_execute && op==10 && rx_valid) f_cover_push_blocked<=1;
            if(f_pop && rx_valid) f_cover_rx_pop<=1;
            if(fault && fault_code==2) f_cover_wait_timeout<=1;
        end
        if(f_past_valid) begin
            // Reset/deselection establishes safe control state without resetting RAM.
            if(!$past(f_active)) begin
                assert(!running && !fault && direction==0);
                assert(loaded==0 && !rx_valid && !tx_valid);
                assert(elapsed==0);
            end else begin
                // A program may never modify its own backing store through the host.
                if($past(running)) begin
                    assert(program_mem[f_address]==$past(program_mem[f_address]));
                    assert(loaded==$past(loaded));
                end
                if($past(f_load && command[5:0]==f_address)) begin
                    assert(program_mem[f_address]==$past(payload));
                    assert(loaded[f_address]);
                end
                assert((loaded | $past(loaded))==loaded);

                // Unread/unsent bytes cannot be silently replaced by another operation.
                if($past(rx_valid && !f_pop && !start_cmd && !stop_cmd)) begin
                    assert(rx_valid);
                    assert(rx_data==$past(rx_data));
                end
                if(!$past(f_enqueue)) assert(tx_data==$past(tx_data));
                if($past(f_enqueue)) assert(tx_data==$past(payload[7:0]));

                if($past(fault && !start_cmd)) assert(fault);
                if($past(stop_cmd)) begin
                    assert(!running && direction==0);
                    assert(!rx_valid && !tx_valid);
                end
                // Delay cycles do not accidentally execute the next instruction.
                if($past(running && delay_left!=0 && !stop_cmd)) begin
                    assert(pc==$past(pc));
                    assert(pins==$past(pins) && direction==$past(direction));
                    assert(delay_left==$past(delay_left)-1'b1);
                end
                if($past(running && delay_left==0 && !loaded[pc] && !stop_cmd)) begin
                    assert(fault && fault_code==1 && !running && direction==0);
                end
                if($past(f_execute && op==9 && !tx_valid))
                    assert(pc==$past(pc) && delay_left==0);
                if($past(f_execute && op==10 && rx_valid))
                    assert(pc==$past(pc) && delay_left==0);
                if($past(start_cmd && !stop_cmd)) assert(elapsed==0);
                if($past(running && !stop_cmd)) begin
                    if($past(f_execute && op==0 && a==5)) assert(elapsed==0);
                    else assert(elapsed==$past(elapsed_next));
                end
                if($past(f_execute && op==0 && a==1)) assert(acc==$past(isr));
                if($past(f_execute && op==0 && a==2)) assert(acc==$past(input_sync & b));
                if($past(f_execute && op==0 && a==3)) assert(acc==$past(acc & b));
                if($past(f_execute && op==0 && a==4 && b<=63)) begin
                    if($past(acc!=0)) assert(pc==$past(b[5:0]));
                    else assert(pc==($past(pc)+6'd1));
                end
                if($past(f_execute && op==0 && a==6)) assert({isr,acc}==$past(elapsed_next));
            end
        end
        if(f_past_valid && fault) assert(!running && direction==0);
        if(!rst_n || !ena || fault) assert(uio_oe==0);
        assert((uio_oe & open_drain & pins)==0);
    end
