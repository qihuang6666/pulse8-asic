# Reactive response measurement

`examples/pulse_capture.p8` is a 15-word test-instrument example. It launches a
stimulus, waits for a device's response, classifies that response from another
input, and returns a coherent 16-bit time measurement. All stimulus generation,
classification, and timestamp capture finish before the host drains any result.
This makes response handling independent of host SPI transaction latency.

| GPIO | Role |
|---|---|
| 0 | Device response input, initially low |
| 1 | Active-high stimulus trigger output |
| 2 | Response qualifier input; keep stable around the response |
| 3 | Classification output: 1 when qualifier was high, otherwise 0 |
| 4-7 | Unused inputs |

Load the program with open-drain mask 0, start it, and read two RX bytes: low
timestamp byte followed by high byte. Combine them as `low | (high << 8)`.
The host may delay either read without changing the captured value. HALT holds
the classification and a low trigger. STOP releases both output drivers. Each
START repeats the measurement with a reset timer and cleared classification.

The response must first be low, then become high within the WAIT timeout. Both
WAIT instructions fault safely after 4095 nonmatching samples. A stuck-high
initial response prevents trigger launch; a missing response releases output
drivers on timeout. A timed-out run does not return a valid timestamp pair, so
the host must check fault status instead of waiting indefinitely for RX data.
This demonstrates response testing with a level handshake, not an asynchronous
edge recorder: brief pulses that miss the synchronizer can be lost.

## Exact cycle interpretation

TRESET establishes cycle R. The trigger rises at R+1. Let W be the clock edge
on which WAIT recognizes the synchronized response. SAMPLE reads the qualifier
at W+1, JNZ selects the path at W+2, and the classification output is set at W+3.
The paths are balanced with one delayed MASK versus MASK plus JMP. TSTAMP
captures at W+5, and the trigger falls at W+6. The returned value is therefore:

```
timestamp = (W + 5) - R
trigger pulse width = (W + 6) - (R + 1) = timestamp clocks
recognized response latency from trigger = timestamp - 6 clocks
```

The last line measures when the engine recognized the input, including the
two-flop input synchronizer. An external pad change generally takes another
two to three system-clock edges to be recognized; it is not justified to claim
subcycle pad timing or subtract a universally exact synchronization offset.
At the intended 24 MHz clock one cycle is approximately 41.667 ns. Actual clock,
pad delays and metastability behavior require physical validation.

In the deterministic digital testbench, the external response rises just after
the Dth edge following trigger launch. WAIT recognizes it at trigger+D+3, the
timestamp is D+9, and the measured output trigger width is also D+9. Both
qualifier paths are checked for D = 0, 1, 7, 31, 255 and 3000 clocks, together
with stuck-low and stuck-high fault cases. The test drives and observes only
the top-level interface and loads the actual assembly program through SPI.

The underlying timer saturates at 65535 (about 2.731 ms at 24 MHz). A 0xffff
result means at least 65535 clocks, never a wrapped short interval. This
particular program's 4095-cycle WAIT deadline prevents successful runs from
reaching saturation; the ISA regression separately verifies counter saturation.

The design does not claim novelty over programmable-I/O systems. This example
demonstrates a concrete use for the added receive-dependent control flow and
timestamp instructions in protocol bring-up and response characterization.
