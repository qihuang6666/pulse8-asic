# Physical implementation and release evidence

**Official GDS, Tiny Tapeout precheck and gate-level tests passed for the same candidate.** Ten maximum-fanout violations remain after antenna insertion and are
accounted for below. The project does not claim that every electrical constraint
is met or that these residuals have a foundry-approved waiver.

The physical evidence is from commit
[`5a0acb27e641263d98e931b72a4e8f3eeb46664f`](https://github.com/qihuang6666/pulse8-asic/commit/5a0acb27e641263d98e931b72a4e8f3eeb46664f),
[official run 43157743973](https://github.com/qihuang6666/pulse8-asic/actions/runs/43157743973).
[Verification run 43157743977](https://github.com/qihuang6666/pulse8-asic/actions/runs/43157743977)
passes on the same source. The release adds documentation, evidence and a standalone
hardened-netlist test runner; the RTL, physical configuration, info.yaml, existing
testbenches and official workflow inputs match the tested revision.

## Physical checks and size

| Check | Result |
|---|---:|
| Magic full DRC / illegal overlap | 0 / 0 |
| LVS | Circuits match uniquely; all mismatch counters 0 |
| Detailed-route DRC / antenna violations | 0 / 0 |
| Setup / hold violation counts, all checked corners | 0 / 0 |
| Maximum capacitance / slew violations, all checked corners | 0 / 0 |
| Maximum-fanout violations | 10; explicitly retained below |
| Critical disconnected pins / power-grid errors | 0 / 0 |
| Filtered / partially unannotated drivers | 0 / 0 |

The 8x4 tile measures 1724.16 by 710.64 um (1,225,257.0624 um^2).
The final design contains 14,386 standard cells
excluding fill, 2,381 flip-flops, 286,947
um^2 of standard-cell area and 717,879 um of routed wire.
These physical counts include clock-tree and repair cells and differ from
preliminary synthesis statistics.

The downloaded precheck `results.xml` records 10 applicable checks, all passing: KLayout pin label overlapping drawing, KLayout SG13CMOS5L DRC, KLayout zero area, KLayout Checks, Pin check, Boundary check, Layer check, Cell name check, Analog pin check, Verilog syntax check. Its report databases contain zero violation items. The artifact digest and XML/job-log hashes are retained in [physical-results.json](physical-results.json).

## Timing at the 24 MHz target

The clock constraint remains 41.666667 ns, with 8.333333 ns input/output delays,
0.25 ns uncertainty, 5% timing derating and a 0.006 pF output load in the official
generic SDC. These constraints describe the evaluated environment, not a measured
board or pad-speed specification. Parasitic extraction uses the configured
nominal RC corner with these three PVT corners:

| Corner | Worst setup slack (ns) | Worst hold slack (ns) |
|---|---:|---:|
| nom_fast_1p32V_m40C | 23.955246 | 0.086252 |
| nom_slow_1p08V_125C | 22.794759 | 0.624282 |
| nom_typ_1p20V_25C | 23.544628 | 0.297622 |

Setup/hold WNS and TNS are zero in all three corners. The clock is propagated;
there are no false-path, multicycle or max-delay exclusions in the final SDC.
The constraint checker reports no unconstrained endpoints or missing clocks.

The raw `setup_r2r__ws` value is `Infinity`, a reporting sentinel rather than a
timing margin: LibreLane selects an endpoint's worst path before filtering for
register starts, so dominating reset-input paths can leave that filtered set
empty. Independent `report_clock_min_period` analysis traverses timing endpoints
and reports finite internal minimum periods of 3.98/9.28/5.92 ns for fast/slow/typical
corners. These corroborate register setup coverage; they are not advertised chip
speeds. A separate label typo in the flow's clock summary writes the propagated
state into the virtual-clock label; the final SDC and nonzero clock-tree latencies
establish propagation. See [LibreLane's selection and clock-label code](https://github.com/librelane/librelane/blob/3.1.0.dev4/librelane/scripts/openroad/sta/corner.tcl#L327)
and [OpenSTA's independent endpoint traversal](https://github.com/The-OpenROAD-Project/OpenSTA/blob/857316ff001b2a8dbbdc5996944d08a6d38c87ab/search/Sta.cc#L3230).

## Disclosed maximum-fanout residuals

The final SDC and library retain a limit of 8. OpenSTA counts the library's
default fanout load of 1 for each connected input, including an antenna diode.
Consequently these are real scalar-limit violations, even though all functional
fanouts are at most eight. The diodes are required for antenna protection and
remain in both the layout and electrical models. Each has nonzero modeled input
capacitance (nominally 1.0804 fF); the extracted capacitance and slew checks above
include their loads. No constraint was increased to hide the reports.

| Driver | Functional loads | Antenna-diode loads | Reported fanout |
|---|---:|---:|---:|
| `_08803_/X` | 8 | 6 | 14 |
| `_11500_/X` | 5 | 6 | 11 |
| `_11519_/X` | 5 | 6 | 11 |
| `_09321_/X` | 8 | 2 | 10 |
| `_11415_/X` | 5 | 5 | 10 |
| `_11479_/X` | 5 | 5 | 10 |
| `_09148_/X` | 8 | 1 | 9 |
| `_09198_/X` | 8 | 1 | 9 |
| `_09280_/X` | 8 | 1 | 9 |
| `_11390_/X` | 5 | 4 | 9 |

The full sink accounting is in [physical-results.json](physical-results.json).
All clock fanout violations from the earlier trials were resolved. The official
flow does not fail on these ten remaining count violations; treating them as a
disclosed competition-candidate residual is an engineering assessment, not a
foundry waiver. Revisit the implementation if Tiny Tapeout requires their removal,
if a functional fanout exceeds eight, or if capacitance, slew or timing fails.
[OpenSTA's fanout calculation](https://github.com/The-OpenROAD-Project/OpenSTA/blob/857316ff001b2a8dbbdc5996944d08a6d38c87ab/search/CheckFanoutLimits.cc#L210)
provides the counting semantics.

## Controlled implementation comparison

All three trials use identical RTL and the same clock target, die size and
official physical-check suite. Density60 and density40 differ only in placement
density. The selected repair trial additionally sets clock sink clusters to 8,
tightens MAX_FANOUT_CONSTRAINT from 10 to 8, enables post-global-route
design/timing repair and uses a 25% capacitance repair margin. This is a small
measured search, not global PPA optimization.

| Measure | Density60 | Density40 | Selected repair |
|---|---:|---:|---:|
| Standard cells excluding fill | 14,315 | 14,297 | 14,386 |
| Standard-cell area (um^2) | 279,053 | 278,514 | 286,947 |
| Routed wire (um) | 689,398 | 793,599 | 717,879 |
| Maximum capacitance violations | 0 | 1 | 0 |
| Maximum fanout violations | 174 | 181 | 10 |

The repair trial resolves the clock-load problem and has no extracted
capacitance violations. It costs additional standard-cell area; its wire length
is shorter than density40 and longer than density60. It is not uniformly best
on every metric. Earlier runs are [density60](https://github.com/qihuang6666/pulse8-asic/actions/runs/43149794753)
and [density40](https://github.com/qihuang6666/pulse8-asic/actions/runs/43152515888).

## Functional checks on the exact hardened netlist

The official gate-level suite passes all five Cocotb tests. The supplemental
port-only regression passes 18,706 system, 2,446 extension and 251,399 protocol
assertions (272,551 total) on this exact hardened netlist with exact official
PDK model blobs. [hardened-results.json](hardened-results.json) records the ZIP,
netlist, model, runner, bench and log hashes. These are functional zero-delay
`FUNCTIONAL/SIM` tests with no SDF; static timing is the separate evidence above.

With Python and Icarus on PATH, download `tt_submission` from the recorded run
and check out IHP-Open-PDK revision `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`
with unmodified LF model files, then run:

```sh
python tools/test_hardened.py --submission /path/to/tt_submission.zip \
  --pdk-root /path/to/IHP-Open-PDK --repo qihuang6666/pulse8-asic \
  --run-id 43157743973 --commit 5a0acb27e641263d98e931b72a4e8f3eeb46664f \
  --sha256 619f7ee289230331c2ea0cd2fd7a643b31a35763924264eda55de34468287420 --jobs 3
```

## Provenance and warning review

Flow: LibreLane 3.1.0.dev4; OpenROAD source pin
`dcf36133a369abc8f3c5e5738cd4d82e4903c0e0`; official IHP-Open-PDK pin
`89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`; Tiny Tapeout support tools
`9d13ff3e3e6202090740110438c6a10c1d62ca0f`. The workflow records its complete
environment. All downloaded archive bytes were checked against GitHub's digest.

| Artifact | ID | SHA256 |
|---|---|---|
| GDS_logs | 13919570810 | `29ee73b5a42b0b8be82eeb07d7624e31388229e9d5becc066394cf9476d15bb1` |
| tt_submission | 13918634713 | `619f7ee289230331c2ea0cd2fd7a643b31a35763924264eda55de34468287420` |
| precheck_reports | 13921686006 | `0c5e427d797e5688105f5a2377e357befcda1fd73ec110a8ab063e36ec42799f` |
| verification-results | 13916926676 | `3090c7dc1b7e04385fd1e25da464cb1728aaa6f75dfc89173dc233e9f302d9d3` |

The 106 lint warnings are timescale warnings in generated PDK blackboxes, with
zero RTL lint errors, latches or timing constructs. Raw unannotated drivers are
exactly five unused top inputs plus 337 unloaded clock-balancing outputs; none
remain after the flow's filtering, and no driver is partially annotated. The
five disconnected top inputs are the documented unused `ui_in[7:3]`; critical
disconnect and power-connectivity counts are zero. LVS matches uniquely.

No fabricated silicon, board experiment, analog CDC/MTBF characterization,
measured power, sustained streaming or global optimality is established by
these results. The [competition FAQ](https://blog.janestreet.com/protocol-emulator-asic-competition/#faq)
defines the entry requirements; repository publication alone does not send the
final entry form.
