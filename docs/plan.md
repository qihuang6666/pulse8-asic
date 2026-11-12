# Submission checklist

Deadline: January 18, 2027. Public repository: https://github.com/qihuang6666/pulse8-asic.

- Included: synthesizable RTL, 8x4 CMOS5L configuration, reset-safe I/O, assembler, host driver, protocol examples, architecture/ISA, verification methods and AI disclosure.
- Demonstrated extensions: receive-dependent execution, masked sampling, coherent elapsed-time capture, reactive stimulus/response timing, I2C read/repeated START, JTAG IR/DR scan and intentional UART framing error.
- Executed: official GDS, full Tiny Tapeout precheck and five-test gate-level suite on commit `5a0acb27e641263d98e931b72a4e8f3eeb46664f`; same-commit verification CI and 272,551 supplemental assertions on the exact hardened netlist.
- Disclosed residual: ten maximum-fanout violations caused by antenna-diode loads. All affected functional fanouts are at most eight; extracted capacitance, slew, setup and hold checks pass. See [physical review](physical-review.md) for complete accounting. This is not complete electrical-constraint closure or a foundry waiver.
- Entrant identifier: `qihuang6666`. Top module: `tt_um_pulse8_proto`.
- The final competition form was not available on the organizers' page at this release. When published, submit the public repository link through that form before the deadline. Repository publication does not submit the entry; no entry form has been sent.

The release preserves the tested design inputs and adds documentation, evidence
and a standalone hardened-netlist test runner. Exact commit/run IDs, archive
hashes and source fingerprints are included for review.

Optional further work includes resolving the residual scalar fanout counts,
deeper/unbounded proof, hardware demonstrations, larger buffering, additional
protocol roles and streaming. These are not extra requirements imposed by the
competition rules. No global optimum or competition outcome is claimed, and no
background schedule is configured.
