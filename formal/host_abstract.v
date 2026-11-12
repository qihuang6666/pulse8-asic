// Core proof boundary: arbitrary decoded host requests each clock.
// This replaces only the SPI decoder in the formal build, not in production.
`default_nettype none
module pulse8_host_spi (
    input wire clk, rst_n, ena, sclk, cs_n, mosi,
    input wire [31:0] response,
    output wire miso, valid, malformed,
    output wire [7:0] command,
    output wire [31:0] payload,
    output wire snapshot_rx_valid
);
    (* anyseq *) reg choose_valid, choose_malformed, choose_snapshot;
    (* anyseq *) reg [7:0] choose_command;
    (* anyseq *) reg [31:0] choose_payload;
    assign valid=choose_valid;
    assign malformed=choose_malformed && !choose_valid;
    assign command=choose_command;
    assign payload=choose_payload;
    assign snapshot_rx_valid=choose_snapshot;
    assign miso=0;
endmodule
