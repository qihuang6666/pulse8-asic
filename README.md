# Pulse8: programmable protocol stimulus and response timing

[![RTL verification](https://github.com/qihuang6666/pulse8-asic/actions/workflows/test.yaml/badge.svg)](https://github.com/qihuang6666/pulse8-asic/actions/workflows/test.yaml)
[![GDS and precheck](https://github.com/qihuang6666/pulse8-asic/actions/workflows/gds.yaml/badge.svg)](https://github.com/qihuang6666/pulse8-asic/actions/workflows/gds.yaml)

Pulse8 is an open-source entry for the Jane Street protocol emulator ASIC competition. It turns eight digital pins into a programmable protocol instrument: generate transactions, react to received data, introduce deliberate protocol errors, and measure response intervals without a host round trip.

**Release candidate: official physical build and precheck pending.** See the workflow badges and [verification report](docs/verification.md) for executed checks. Functional simulation does not establish silicon operation or electrical protocol compliance.

## Architecture and purpose

One engine executes 64 writable 32-bit instructions. Direct input sampling and receive-data branches let firmware make timing-sensitive decisions locally. A saturating 16-bit timer captures both timestamp bytes atomically before host backpressure can affect them. Bounded waits release all outputs on a timeout. Eight output enables and open-drain settings support bidirectional buses. There are no UART, SPI, I2C or JTAG-specific hardware blocks.

The [15-word stimulus/response example](docs/event-capture.md) launches a trigger, waits for a response, classifies an input, produces a balanced-latency output, and reports elapsed time. The malformed UART example deliberately emits a bad stop bit, then restores idle. These are practical debugging workflows; the project does not claim that programmable I/O or timestamping is a new idea.

## Demonstrated programs

| Program | Demonstration | Scope |
|---|---|---|
| UART TX / RX | 8N1, 115384.6 baud at 24 MHz | One byte per invocation |
| SPI modes 0-3 | Full-duplex byte at 100 kHz | Controller, MSB first |
| I2C write | Address/data, ACK and clock stretching | Single controller, around 100 kHz |
| I2C register read | Host-selected register and repeated START | No clock stretching |
| I2C restart read | Repeated START and current-address read | Stretch-aware; empty write phase |
| JTAG | Reset, 4-bit IR selection, 8-bit DR scan | Documented target-specific chain |
| UART fault injection | Invalid stop bit and idle recovery | Receiver robustness stimulus |
| Pulse capture | Local reaction and coherent response timing | Synchronized digital inputs |

[Protocol demos](docs/protocol-demos.md) specifies pin assignments, target contracts and test coverage. One program runs at a time. Mailboxes hold one byte each. Sustained streaming, USB, Ethernet, multi-master I2C and arbitrary JTAG chains are outside the demonstrated scope.

## Reproduce verification

With Python 3.10+, Icarus Verilog and Yosys on PATH:

```sh
python tools/check.py --yosys yosys
python -m pip install yowasp-yosys==0.70.0.0.post1259
python tools/formal_check.py
python -m pip install -r test/requirements.txt
make -C test
python tools/assembler.py examples/pulse_capture.p8 -o work/pulse_capture.hex
```

The regression uses independent external monitors and the real host SPI interface at RTL and generic-netlist levels. `tools/map_cmos5l.py` repeats these tests with IHP cell models. The official workflow builds GDS, runs precheck and executes the Cocotb gate-level suite. [Formal checks](docs/formal.md) use an abstract decoded-host boundary and a finite horizon.

Explicit tool paths can be passed using `--iverilog`, `--vvp`, and `--yosys`. `--yosys-wasm` uses YoWASP. In the Windows development workspace, `tools/check-local.ps1 -Synthesis -Map -Formal` locates portable tools. `--waves` writes a VCD under `work/`. Generated files are excluded from Git.

## Load and use

1. Select the design and supply a stable clock. Hold reset low for two clock edges, then release synchronously.
2. STOP, configure the open-drain mask, load the program and preload TX if needed.
3. START, read status/RX and drain results. STOP releases the pins.
4. Reload after reset or deselection; storage is volatile.

The host is SPI mode 0 with five bytes per CS frame. Each SCLK half-period, CS setup and CS-high gap must be at least four system clocks. At 24 MHz this gives a host SCLK ceiling of 3 MHz in the digital model. For a CS-framed `transfer(bytes)->bytes` adapter:

```python
from pathlib import Path
from tools.assembler import assemble
from tools.host import Pulse8
chip = Pulse8(transfer)
chip.load(assemble(Path('examples/spi_mode0.p8').read_text()))
chip.send(0xa5)
chip.start()
received = chip.receive()
```

The driver fills unused addresses with HALT. Assembler `--packets` output contains STOP and program writes only; use after reset or explicitly manage the unused tail. It does not configure or start execution. Open-drain buses require external pull-ups. Board-specific transport and hardware operation have not been tested.

## Documents and provenance

- [Architecture and ISA](docs/architecture.md)
- [Measured design tradeoffs](docs/design-tradeoffs.md)
- [Pinout and host commands](docs/info.md)
- [Reactive timing demonstration](docs/event-capture.md)
- [Protocol contracts and monitors](docs/protocol-demos.md)
- [Verification evidence and limits](docs/verification.md)
- [End-to-end mailbox stress](docs/mailbox-stress.md)
- [AI assistance disclosure](docs/ai-usage.md)
- [Submission checklist](docs/plan.md)

Official Tiny Tapeout IHP main-branch template, 8x4 CMOS5L tiles, 24 MHz target, top module `tt_um_pulse8_proto`, entrant identifier `qihuang6666`. New source and retained template files are Apache-2.0 licensed. Initial template revision: `4b1204ab387b5ab94db1d57067051d8d89a2f83c`.

[Competition rules](https://blog.janestreet.com/protocol-emulator-asic-competition/) and [official template](https://github.com/TinyTapeout/ttihp-verilog-template).


