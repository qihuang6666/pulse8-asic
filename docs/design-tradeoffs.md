# Design choices and measured tradeoffs

Pulse8 trades a small increase in mapped logic for local decisions on received
data and coherent event timing. The comparison below measures the original
core against the version with MOVISR, SAMPLE, AND, JNZ, TRESET and TSTAMP. Both
versions retain the 64-by-32-bit program store, eight GPIOs and the one-byte
mailbox in each direction. This is an incremental before/after comparison, not
an exhaustive architecture search or a claim of PPA optimality.

## Preliminary mapping comparison

The measurements use Yosys 0.70 and the IHP CMOS5L typical 1.20 V, 25 C
standard-cell library, `sg13cmos5l_stdcell_typ_1p20V_25C.lib`. The current
mapping is produced by `tools/map_cmos5l.py`; its local machine-readable output
is `work/mapped_stats.json`. The original measurements were retained in the
project's prototype verification evidence.

| Measure | Original core | Reactive/timing core | Change |
|---|---:|---:|---:|
| Actual standard cells | 8,907 | 9,306 | +399 (+4.48%) |
| Flip-flops | 2,365 | 2,381 | +16 (+0.68%) |
| Library cell area, um^2 | 190,211.1120 | 192,631.1436 | +2,420.0316 (+1.27%) |
| Program storage | 64 x 32 bits | 64 x 32 bits | Unchanged |
| TX/RX mailbox capacity | One byte each | One byte each | Unchanged |

Yosys reports 9,307 objects for the current core. One is the nonphysical
`$scopeinfo` object, so the physical standard-cell count is 9,306. The 16 added
flip-flops hold the elapsed counter. The other extensions reuse the existing
accumulator, input shift register and program counter, adding combinational
decode and data paths. Cell count and library area need not change by the same
percentage because different cell types occupy different areas.

Library area is the sum of mapped cell areas. It excludes routing, clock-tree
insertion, physical repair, fillers and other layout overhead. It does not show
that an 8x4 tile layout fits, meets timing, or passes fabrication checks. These
measurements establish no power result, maximum clock frequency, routed area,
or physical sign-off result. Official Tiny Tapeout flow evidence is recorded
separately in the [verification report](verification.md).

## Why add local response decisions and timing?

The original core could shift inputs into ISR and return them to the host, but
could not directly use ISR as the arithmetic/branch accumulator. MOVISR removes
that round trip. With the usual one-cycle, zero-delay instructions, MOVISR,
XOR and JZ can compare a received byte with an immediate value and select a
branch in three execution cycles. SAMPLE and AND support masked multi-pin
conditions, while JNZ provides the complementary branch condition. These are
execution-cycle statements, not a physical timing claim.

The saturating counter advances during WAIT, instruction delays and mailbox
stalls. TSTAMP captures both timestamp bytes together, so a slow host cannot
change the value between low-byte and high-byte reads. Its cost is the measured
16 additional flip-flops plus the counter and selection logic. Captures overwrite
A and ISR, and the counter cannot distinguish intervals above 65,535 clocks.
At the intended 24 MHz clock, that range is approximately 2.731 ms.

The 15-word [response measurement example](event-capture.md) gives these changes
a concrete use: launch a stimulus, observe a response, select a classification
output and capture time before the host consumes either result byte. Both
classification paths take equal time. Its external test checks the emitted
trigger width against an independent clock count and checks that classification
finishes before any result read. The documented input-synchronizer and firmware
offsets remain part of interpreting the measurement.

This is a demonstrated capability of Pulse8, not evidence that it outperforms
existing programmable-I/O systems. No broad superiority, novelty, or competition
outcome is claimed.

## Storage and buffering choices

The longest current example, JTAG, uses 60 words; the stretching-aware I2C
repeated-START example uses 57. A 32-word store would not hold those programs as
written. Keeping 64 words leaves four words after the JTAG program while
preserving a six-bit PC and the existing host loader. This is a concrete reason
for the current capacity, not proof that 64 is globally optimal: a different
encoding or subroutine architecture could change the tradeoff.

Program data alone occupies 2,048 stored bits. The current design uses
flip-flops and a separate validity map, with no SRAM macro. An SRAM alternative
could change area and timing, but it has not been implemented and compared in
the same physical flow. No quantified SRAM saving is asserted.

One-byte mailboxes keep the control logic small but limit sustained transfers.
PULL stalls when TX is empty; PUSH stalls when RX is full. Consequently,
continuous high-rate streams depend on host service time, and protocol firmware
must place blocking transfers at safe boundaries. Finishing a capture before
PUSH protects that particular measurement; it does not make the design a
continuous event recorder or remove the need for buffering in longer workloads.
Larger FIFOs, autonomous repeated captures and concurrent engines remain
unimplemented alternatives with additional storage and control costs.

## Evidence and coverage limits

The following counts come from completed local test logs for the updated core.
The generic and CMOS5L simulations use synthesized netlists; the latter uses
functional cell models without extracted delays or SDF.

| Check | Observed result | Local evidence |
|---|---|---|
| Assembler and host Python tests | 14 tests passed | `work/software-tests.log` |
| Host SPI phase/framing | 240 frames, 1,040 assertions passed | `work/host-phase-tests.log` |
| Core safety, arithmetic, UART, SPI and original I2C scenarios | 18,706 assertions passed at RTL, generic netlist and mapped netlist | `work/rtl-tests.log`, `work/generic-rtl-tests.log`, `work/mapped-rtl-tests.log` |
| New instructions and event capture | 2,446 assertions passed at RTL, generic and mapped netlist levels | `work/generic-extension-tests.log`, `work/mapped-extension-tests.log` |
| Additional I2C, JTAG and malformed-UART scenarios | 251,399 assertions passed at RTL, generic and mapped netlist levels | `work/generic-protocol-extension-tests.log`, `work/mapped-protocol-extension-tests.log` |

Instruction tests include all 256 input byte values for ISR-to-A transfer,
masked arithmetic and branch decisions, 256 SAMPLE values, timer saturation,
coherent capture under backpressure, and 14 response-capture scenarios. The
protocol tests include repeated START/read/NACK/STOP, clock stretching in the
designated I2C example, injected NACKs, all 16 JTAG TAP initial states, and an
intentionally invalid UART stop bit followed by idle recovery.

Assertion totals include repeated cycle checks and are not counts of independent
scenarios. These tests demonstrate the listed behavior; they do not prove all
programs, arbitrary sustained workloads, physical timing, power, analog input
behavior or metastability containment. The separate bounded formal harness and
its current results are described in [formal verification](formal.md); no
unbounded proof is inferred from simulation.

