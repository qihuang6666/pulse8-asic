# Protocol demonstrations and their verified scope

Pulse8 programs control pin values, enables and delays directly. The same RTL
runs conventional transactions and deliberately malformed stimulus; no UART,
SPI, I2C or JTAG-specific hardware decoder is added. These examples demonstrate
programmability, not universal compliance or a measured advantage over other
programmable I/O engines.

The additional demonstrations in `tests/tb_protocol_extensions.v` are loaded
through real 40-bit host SPI transactions. Independent targets observe external
pins and return data through those pins. Tests never inspect DUT registers or
write its program memory directly. Host replies are sampled at the master's
actual SCLK edge, before the DUT's synchronized observation of that edge.

| Program | Words / 64 | Demonstrated transaction | Explicit limitations |
|---|---:|---|---|
| `i2c_register_read.p8` | 49 | Address 0x50 write, host-provided 8-bit register pointer, repeated START, address 0x50 read, one byte, controller NACK, STOP | Single controller; target must not stretch SCL; no arbitration |
| `i2c_restart_read.p8` | 57 | Empty write to 0x50, repeated START, read current byte, controller NACK, STOP; waits for every released SCL phase | Target must accept the empty write/current-address convention; no register pointer or arbitration |
| `jtag_dr8.p8` | 60 | TAP reset, 4-bit IR instruction 2, then 8-bit full-duplex DR scan, return to Run-Test/Idle | Target-specific IR width, instruction and DR width; no universal IDCODE or boundary-scan discovery |
| `uart_bad_stop.p8` | 9 | Host byte as 8N1-style UART frame with a deliberately low stop bit, followed by idle recovery | Intentionally malformed stimulus; not a conforming UART transmitter |

## I2C checks

Both I2C examples require GPIO0=SDA, GPIO1=SCL, host open-drain mask `3`, and
external pull-ups. The register pointer must be preloaded in the TX mailbox
before START. Transmitted bytes are MSB-first; the final received byte is
returned through the RX mailbox. Every transmitted byte's ACK is checked.

The target monitor decodes the write address, register pointer when present,
read address, repeated START, final controller NACK and STOP independently. It
checks that neither line is ever actively driven high and that each measured
SCL high/low interval is at least 120 system clocks, or 5 microseconds at the
nominal 24 MHz clock. Transmit loops include additional low cycles and therefore
do not imply a uniform 100 kHz bus rate. Read loops are approximately 100 kHz.

The stretch-capable example waits for SCL high in data, ACK, controller NACK,
repeated START and STOP phases. Its nonzero WAIT timeout is 4095 system clocks,
about 170.6 microseconds at 24 MHz. Tests inject a 480-clock low extension in
three places: write address, read data and the controller NACK clock. This
exercises the last-byte transition as well as the main loop.

The register-read example deliberately trades stretching support for program
capacity. Do not use it with a stretching target. The suite injects target NACK
at the first address, register-pointer byte and read address; in each case the
core faults and all output enables become zero. The original system suite also
checks a stuck SCL timeout. These digital simulations do not model pull-up RC,
voltage levels, setup/hold margins at pads, bus contention or metastability.
The [NXP I2C specification](https://www.nxp.com/docs/en/user-guide/UM10204.pdf)
defines the underlying bus conventions; this is not a compliance certification.

## JTAG checks

GPIO0=TCK, GPIO1=TMS, GPIO2=TDI and GPIO3=TDO. The example first holds TMS high
for five clocks, navigates to Shift-IR, selects instruction 2 using a four-bit
LSB-first scan, then captures and shifts an eight-bit DR. It exits through
Update-DR and returns to Run-Test/Idle. Reset alone would not generally select
an eight-bit register, which is why the example explicitly selects an IR.

The independent target implements all sixteen TAP transitions, a four-bit IR
and an eight-bit selected DR. It drives TDO on falling TCK edges and samples TDI
on rising edges. The test starts in every possible TAP state, checks reset
recovery, validates IR selection, compares every outgoing data bit and the final
updated DR, and confirms the captured target byte through host SPI. It checks
120-clock high times and at least 120-clock low times. Shift loops run at about
100 kHz at 24 MHz; navigation and mailbox operations have longer gaps. The
[Microchip TAP documentation](https://onlinedocs.microchip.com/oxy/GUID-74F8229E-4C43-4FA0-BE7D-1AA303C6F8A4-en-US-6/GUID-4A877CE6-1E9A-4679-BE1B-11E7C5C25C31.html)
describes the sixteen-state controller and five-clock reset convention.

## Programmed protocol faults

`uart_bad_stop.p8` shows how the engine can test a receiver's error detection
and recovery. It changes only the firmware's stop-bit level; core execution
remains healthy. The independent receiver checks all 2288 waveform clocks,
including the invalid stop-bit center and the explicit subsequent idle period,
for both `0xa5` and `0x00`. A separate hardware receiver's recovery behavior has
not been tested. The stimulus could be adapted to shortened bits or breaks by
editing the program's values and delays, but those variants are not claimed as
verified demonstrations.

## Reproducible evidence

The extension suite passes **251,399 assertions across 29 scenarios**: four
register reads, four current-address reads (including three stretch positions),
three NACK faults, sixteen JTAG scans and two deliberate UART framing faults.
Many assertions repeat the same safety condition on successive clocks; the
scenario count and checked behavior describe coverage more accurately than the
raw assertion total. These tests remain finite digital functional simulations.
See `verification.md` for the current RTL/netlist run status and physical-flow
status. Passing this suite alone does not establish routed timing, electrical
compatibility or silicon operation.
