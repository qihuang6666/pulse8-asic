# How it works

Pulse8 is a reprogrammable digital protocol engine. A host loads up to 64
32-bit instructions through SPI; the engine controls the eight bidirectional
pins using explicit delays, input sampling, branching and mailbox transfers.
See [architecture.md](architecture.md) for the ISA and timing rules.

# How to test

Run `python tools/check.py` from the project root with Python and Icarus Verilog.
The testbench loads every program through the external host pins and checks
UART, SPI and I2C waveforms independently of internal RTL signals.

## Host pins

| Tiny Tapeout pin | Function |
|---|---|
| ui[0] | Host SPI SCLK |
| ui[1] | Host SPI MOSI |
| ui[2] | Host SPI CS_n, idle high |
| uo[0] | Host SPI MISO (dedicated output, drives zero outside frames) |
| uo[2] | Engine running |
| uo[3] | Core fault |
| uo[4] | RX valid |
| uo[5] | TX ready |
| uo[7] | Sticky host error |
| uio[7:0] | Programmable GPIO |

ui[7:3] are unused. uo[1] and uo[6] are tied low. The host SPI pins are separate
from the programmable pins, so a program can run while the host reads status.

## Host framing

Use mode 0, MSB first. Every CS assertion contains exactly 40 rising SCLK edges:
an 8-bit command followed by a 32-bit big-endian payload. The transaction commits
on CS rising, after synchronization. Short or long frames are rejected atomically.
Use SCLK <= clk/8, high and low times >= four system clocks, and CS setup/high
times >= four system clocks. Faster or badly phased framing has no guarantee.

During the first byte, ignore MISO. The following four received bytes contain a
snapshot captured when the command byte arrives:

| Response bits | Meaning |
|---|---|
| 31 | Sticky host error |
| 30 | Core fault |
| 29 | RX valid |
| 28 | TX ready |
| 27 | Engine running |
| 26:24 | Core fault code: 0 none, 1 unloaded instruction, 2 WAIT timeout, 3 invalid pin/address |
| 23:16 | RX data (valid only if bit 29 is set) |
| 15:8 | PC, zero-extended |
| 7:0 | Accumulator A |

The snapshot describes state before the current command commits. Issue another
status frame to observe its result. RX data arriving after a read-and-pop snapshot
is not consumed by that frame. Polling may miss a short running pulse; use faults
and the expected completion result rather than requiring running to be observed.

| Command | Payload | Effect |
|---|---|---|
| 0x00 | Ignored | Snapshot only |
| 0x01 | Ignored | START at address 0; rejected if running |
| 0x02 | Ignored | STOP, release pins, clear TX/RX mailboxes |
| 0x03 | Low byte | Set open-drain mask; rejected if running |
| 0x04 | Low byte | Enqueue TX byte; rejected if TX is full |
| 0x05 | Ignored | Consume RX only if the snapshot contained a valid byte |
| 0x06 | Ignored | Clear sticky host error |
| 0x80..0xBF | 32-bit instruction | Write address command[5:0]; rejected if running |

Other command values set host_error. Rejected commands do not overwrite program
memory or mailbox data. Mailboxes are one byte deep; the host must honor readiness.
One host must own the interface; multiple concurrent host clients are unsupported.

# External hardware

Provide the clock, reset and host SPI through the Tiny Tapeout demo board or a
documented host adapter. Only digital pads are exposed. The demo board I/O is
3.3 V according to the competition announcement; verify board wiring before use.
The proposed 24 MHz clock remains subject to post-route timing closure.

UART: GPIO0 is TX or RX, depending on the selected example. Use a logic-level
UART partner, with external level conversion when needed.

SPI: GPIO0=SCK, GPIO1=MOSI, GPIO2=MISO, GPIO3=CS_n. Select the program matching
the partner's mode. Preload TX before START, then read RX after the transfer.

I2C: GPIO0=SDA and GPIO1=SCL, both with pull-ups to the compatible I/O supply.
Configure open-drain mask 0x03. Choose pull-ups for the actual bus capacitance
and required rise time. The example addresses 0x50 and writes one byte.

No board experiment has been run yet. The Python host driver requires an
adapter to the selected microcontroller/SPI API. Reset or deselection loses the
program; the host must reload it after each selection/power cycle.
