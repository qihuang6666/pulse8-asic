# Bounded core safety checks

The local Yosys SAT run passed all **33 assertions through 12 clock steps**.
It starts with a reset edge and leaves instruction memory arbitrary. All decoded
host requests, payloads, enable/reset transitions and external GPIO inputs after
that first edge are symbolic. One symbolic constant address selects a program
word, so the memory-protection assertion applies to any of the 64 locations.

The production core is used directly. The SPI decoder is replaced only in this
formal build by `formal/host_abstract.v`, which supplies arbitrary commands at
the decoder/core boundary. Its command and malformed pulses are mutually
exclusive, matching the decoder. There are no assumptions that force a benign
program or keep the host idle. The proof is a digital, two-state model with one
global clock; it does not model metastability or electrical effects.

## Properties

- Reset/deselection clears control state, mailboxes and program validity.
- Host writes cannot change program words or validity bits while running.
- Accepted writes while stopped preserve the full 32-bit payload and set validity.
- Validity bits are monotonic until reset/deselection.
- An unread RX byte remains intact until consumption, START or STOP.
- TX data changes only on an accepted enqueue or reset/deselection.
- Core faults remain set until START/reset/deselection.
- STOP releases pins, clears mailboxes and stops the engine.
- Delay cycles preserve PC and output state while decrementing the delay.
- Fetching an unloaded instruction faults and releases output enables.
- Empty PULL/full PUSH operations stall without advancing PC.
- Fault/reset/deselection disables output enables; open-drain outputs never drive high.

The 33 assertion statements are in `formal/core_properties.vh`. They are included
only when `PULSE8_FORMAL_CORE` is defined. The normal RTL and synthesis builds
include no formal registers or assertions.

## Reachability checks

Separate solver queries found witness traces within the same 12-step bound for:

1. A host program write attempted while the engine is running.
2. A PUSH instruction blocked by a full RX mailbox.
3. Consumption of a valid RX byte.
4. A WAIT timeout fault.

These witnesses show that selected important scenarios are reachable under the
formal model. They do not establish that every assertion's enabling condition
was covered, nor do they prove arbitrary long-running behavior. Timeout recovery,
protocol liveness and unbounded induction remain future work.

## Run locally

```sh
python -m pip install yowasp-yosys==0.70.0.0.post1259
python tools/formal_check.py
```

In the current Windows workspace, `tools/check-local.ps1 -Formal` sets up the
portable tools and runs the ordinary regression before the bounded checks.
The result is written to `work/formal-results.json`. Solver logs and witness
VCDs remain in `work/`; the archived result is `docs/formal-results.json`.

## Additional host simulation

`tests/tb_host_random.v` checks the real SPI decoder independently. With seed
`0x1248a5c3`, it runs 240 frames (80 valid and 160 short/long frames), including
zero-length frames. Half periods vary from 4 to 10 system clocks, with varied
phase relative to the core clock. It checks 1,040 assertions and samples MISO
at the physical master clock edge, before the decoder can observe that edge.

The response is changed after the command byte to check snapshot stability.
The test also checks exactly one commit/error per frame, received command/data,
the RX snapshot flag and MISO's idle value. This tests digital phase relationships
within the documented limit, not analog setup/hold margins or metastability.

