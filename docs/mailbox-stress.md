# End-to-end host/core mailbox stress

`tests/tb_mailbox_random.v` exercises the real host SPI decoder together with
the production core. It loads a five-instruction program through ordinary host
transactions: `PULL; XOR 0xa5; NOP [511]; PUSH 0; JMP 0`. A separately maintained
FIFO records each accepted source byte XOR `0xa5` and compares every valid RX
snapshot to its head. No internal DUT signal or memory is accessed.

The compute delay allows RX to become valid after a POP command has captured
an empty snapshot but before that command commits. Such a POP must preserve
the newly arrived byte. Subsequent snapshots and POPs verify its value and
position in the sequence. The test records this condition through the external
RX-valid output and received snapshot, rather than inferring it from the core's
program counter or implementation registers.

Before enqueueing, the master obtains a TX-ready snapshot. Only the host can
fill TX, so this observation guarantees that the following enqueue is accepted.
The scoreboard adds exactly one expected byte at that frame's completion. RX
bytes are removed from the scoreboard only when an actual POP frame returns a
valid RX snapshot. Status-only frames never consume bytes.

The initial sequence fills all three places that can hold pending data: RX,
the core accumulator stalled at PUSH, and TX. Eight further snapshots with
random idle gaps verify preservation under backpressure. Later randomized
commands mix enqueues, POPs, snapshots and malformed enqueue attempts. A bad
frame must raise the host-error flag without adding a byte; the test clears the
flag and continues. Finally, the full stream is drained and checked repeatedly
for extra or duplicated bytes.

The master samples MISO at the actual external rising edge. Frame half-periods
vary from 40 to 100 ns with a 10 ns system clock, frame phase varies, and each
low phase receives an additional random 0 to 120 ns pause. These meet the
documented minimum four-clock half-period. Malformed frames contain 0–39 or
41–72 clocks. This verifies digital timing relationships and interrupted serial
progress within the supported timing contract; it does not model metastability
or physical timing margins.

## Recorded RTL result

The deterministic Icarus run with seed `0x6e4b2a19` passed:

| Evidence | Count |
|---|---:|
| Accepted source bytes returned exactly once, in order | 512 |
| Actual SPI frames, including setup and negative cases | 1,564 |
| Assertions | 8,340 |
| Malformed enqueue frames | 46 |
| POPs returning an empty snapshot | 222 |
| Empty-snapshot POPs with RX valid at frame completion | 130 |
| Enqueues while the engine was waiting at empty PULL | 485 |
| Explicit full-pipeline backpressure observations | 8 |

The counts describe one seeded run, not exhaustive coverage or an unbounded
proof. Different simulator random-number implementations may produce different
traffic counts; the fixed 512-byte completion requirement and scoreboard checks
remain the same. Reset/deselect and STOP flush behavior are covered separately;
this test concentrates on uninterrupted end-to-end mailbox traffic. See
`verification.md` for which netlist and CI stages run this suite.

## Standalone run

From the project directory, with Icarus Verilog on PATH:

```sh
iverilog -g2012 -Wall -s tb_mailbox_random -o work/mailbox_random.vvp src/project.v src/host_spi.v tests/tb_mailbox_random.v
vvp work/mailbox_random.vvp
```

Create `work/` first if it does not exist. The development run's captured log
is `work/mailbox-stress-tests.log`. The regular project runner may provide the
same check as part of the full regression.
