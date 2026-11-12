# Verification evidence

## Recorded verification

The expanded source passes 14 software tests and 272,551 assertions at each of RTL, generic-netlist and CMOS5L mapped functional levels. Host framing adds 1,040 assertions across 240 frames. An end-to-end real-SPI mailbox stress test passes 8,340 assertions over 512 ordered bytes and 1,564 frames, including malformed traffic, full-pipeline backpressure and late-arrival POP races. See mailbox-stress.md; this additional test is run at RTL. All 33 core assertion statements pass through 12 formal steps with four witnesses. Fresh mapping reports 9,306 actual cells, 2,381 flip-flops and 192,631.1436 square micrometers of cell area. See verification-results.txt, mapped-statistics.json, formal-results.json and source-sha256.json for reproducible evidence. The official GDS, full Tiny Tapeout precheck and gate-level jobs pass for the recorded candidate. [Physical review](physical-review.md) records the remaining ten antenna-diode-related fanout violations and the separate passing capacitance, slew, timing, DRC and LVS results.

Current RTL suites cover the original host/UART/SPI/I2C cases, all 256 receive and sample values for the new data path, timer carry/saturation/backpressure, a reactive capture program, I2C read/repeated START, JTAG IR/DR transactions starting in all 16 TAP states, and deliberate UART framing errors. These are port-only tests loaded through real SPI; pin monitors decode protocol behavior independently of firmware.

The same three system testbenches run at RTL, generic synthesized and CMOS5L mapped functional levels. The host decoder has a separate seeded 240-frame phase/framing test. The official Cocotb suite additionally checks malformed frames, reset/deselection, new instructions, timestamps, UART and all SPI modes. Test counts are dynamic assertions, not counts of independent scenarios.

## Public CI evidence

[Verification run 43157743977](https://github.com/qihuang6666/pulse8-asic/actions/runs/43157743977)
passed on commit `5a0acb27e641263d98e931b72a4e8f3eeb46664f` on November 12,
2026 (UTC). It executed the 14 software cases, all three system suites at RTL
and generic-netlist levels, the host phase/framing test, the 512-byte mailbox
stress test, all five Cocotb tests and the 12-step formal check with four
witnesses. The CI mailbox counts match the recorded local result.

The run's `verification-results` archive has artifact ID `13916926676` and
SHA256 `3090c7dc1b7e04385fd1e25da464cb1728aaa6f75dfc89173dc233e9f302d9d3`.
Its downloaded bytes were checked against GitHub's reported digest. This CI
run does not include CMOS5L mapping or physical sign-off; the former is the
separate local evidence above, and the latter is the GDS workflow.

## Exact hardened-netlist regression

The same three port-only benches also pass on the official hardened netlist from
commit `5a0acb27`: 18,706 + 2,446 + 251,399 = 272,551 assertions. The standalone
`tools/test_hardened.py` checks the trusted ZIP digest, commit/repository/run
metadata, unchanged RTL, and exact official PDK model blobs before simulation.
Its concurrent mode (`--jobs 3`) passed on this artifact. The official five-test
Cocotb gate-level suite also passes. See [hardened-results.json](hardened-results.json)
and the [reproduction command](physical-review.md#functional-checks-on-the-exact-hardened-netlist).
These tests are zero-delay functional simulations with no SDF; assertion counts
include repeated checks and are not independent scenario counts.

## Physical and formal scope

[Official run 43157743973](https://github.com/qihuang6666/pulse8-asic/actions/runs/43157743973) passes GDS, precheck and gate-level Cocotb on the same candidate. The final release adds documentation/evidence and the standalone runner; it preserves the tested RTL, configuration, existing benches and workflows. Ten real scalar fanout-limit violations remain from additional antenna-diode loads and are explicitly reviewed in physical-review.md. No blanket electrical-rule compliance or foundry waiver is claimed. The mapped and official gate simulations are functional, with no SDF delays; static timing is a separate physical-flow result. Do not equate a passing simulation with maximum pad speed or fabricated-silicon operation.

The core formal harness contains 33 assertion statements. It uses arbitrary decoded host requests, a reset at the first clock edge, arbitrary initial instruction storage, a 12-step default bound and digital two-state semantics. Four reachability witnesses check that selected scenarios are possible. This is neither an unbounded proof nor an end-to-end SPI/metastability proof. See formal.md.

## Historical baseline

Before the reactive upgrade, the prototype passed 10 Python cases, 18,706 checks at each of three simulation levels, 1,040 host checks and 23 assertions through 12 formal steps. Preliminary mapping used 8,907 standard cells, 2,365 flip-flops and 190,211.112 square micrometers of cell area. Those numbers are retained only as a development comparison. They exclude routing, CTS, fillers and repair.

Initial tool provenance: Icarus 13.0, Verilator 5.050, Yosys 0.70 via YoWASP; Tiny Tapeout template 4b1204ab387b5ab94db1d57067051d8d89a2f83c; IHP PDK 597570eec556a473d1eedb22c055545d4522f442, typical 1.20V/25C library. GitHub Actions records the exact official tool and PDK revisions used for hardening.

## Remaining practical limits

No FPGA/board experiment, silicon operation, analog CDC/MTBF characterization, pad rise/fall measurement, continuous streaming validation or universal protocol compliance is claimed. Protocol examples have explicit roles and restrictions in protocol-demos.md. The single-byte mailboxes and 64-word store are deliberate capacity limits, not evidence of global optimization.

## Reproduction

Run python tools/check.py --yosys yosys, python tools/formal_check.py, and make -C test after installing test/requirements.txt. For preliminary IHP mapping, use python tools/map_cmos5l.py --pdk-root /path/to/ihp-sg13cmos5l. The Windows helper tools/check-local.ps1 locates development tools and accepts -Synthesis -Map -Formal. All generated logs and vectors live in work/.


