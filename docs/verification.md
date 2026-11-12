# Verification evidence

## Release candidate

The expanded source passes 14 software tests and 272,551 assertions at each of RTL, generic-netlist and CMOS5L mapped functional levels. Host framing adds 1,040 assertions across 240 frames. An end-to-end real-SPI mailbox stress test passes 8,340 assertions over 512 ordered bytes and 1,564 frames, including malformed traffic, full-pipeline backpressure and late-arrival POP races. See mailbox-stress.md; this additional test is run at RTL. All 33 core assertion statements pass through 12 formal steps with four witnesses. Fresh mapping reports 9,306 actual cells, 2,381 flip-flops and 192,631.1436 square micrometers of cell area. See verification-results.txt, mapped-statistics.json, formal-results.json and source-sha256.json for reproducible evidence. The official physical workflow is still in progress.

Current RTL suites cover the original host/UART/SPI/I2C cases, all 256 receive and sample values for the new data path, timer carry/saturation/backpressure, a reactive capture program, I2C read/repeated START, JTAG IR/DR transactions starting in all 16 TAP states, and deliberate UART framing errors. These are port-only tests loaded through real SPI; pin monitors decode protocol behavior independently of firmware.

The same three system testbenches run at RTL, generic synthesized and CMOS5L mapped functional levels. The host decoder has a separate seeded 240-frame phase/framing test. The official Cocotb suite additionally checks malformed frames, reset/deselection, new instructions, timestamps, UART and all SPI modes. Test counts are dynamic assertions, not counts of independent scenarios.

## Physical and formal scope

Submission readiness requires the public repository's official Tiny Tapeout GDS build and precheck to pass. The workflow also runs a gate-level Cocotb suite. The mapped and official gate simulations are functional, with no SDF delays; static timing is a separate physical-flow result. Do not equate a passing simulation with maximum pad speed or fabricated-silicon operation.

The core formal harness contains 33 assertion statements. It uses arbitrary decoded host requests, a reset at the first clock edge, arbitrary initial instruction storage, a 12-step default bound and digital two-state semantics. Four reachability witnesses check that selected scenarios are possible. This is neither an unbounded proof nor an end-to-end SPI/metastability proof. See formal.md.

## Historical baseline

Before the reactive upgrade, the prototype passed 10 Python cases, 18,706 checks at each of three simulation levels, 1,040 host checks and 23 assertions through 12 formal steps. Preliminary mapping used 8,907 standard cells, 2,365 flip-flops and 190,211.112 square micrometers of cell area. Those numbers are retained only as a development comparison. They exclude routing, CTS, fillers and repair.

Initial tool provenance: Icarus 13.0, Verilator 5.050, Yosys 0.70 via YoWASP; Tiny Tapeout template 4b1204ab387b5ab94db1d57067051d8d89a2f83c; IHP PDK 597570eec556a473d1eedb22c055545d4522f442, typical 1.20V/25C library. GitHub Actions records the exact official tool and PDK revisions used for hardening.

## Remaining practical limits

No FPGA/board experiment, silicon operation, analog CDC/MTBF characterization, pad rise/fall measurement, continuous streaming validation or universal protocol compliance is claimed. Protocol examples have explicit roles and restrictions in protocol-demos.md. The single-byte mailboxes and 64-word store are deliberate capacity limits, not evidence of global optimization.

## Reproduction

Run python tools/check.py --yosys yosys, python tools/formal_check.py, and make -C test after installing test/requirements.txt. For preliminary IHP mapping, use python tools/map_cmos5l.py --pdk-root /path/to/ihp-sg13cmos5l. The Windows helper tools/check-local.ps1 locates development tools and accepts -Synthesis -Map -Formal. All generated logs and vectors live in work/.


