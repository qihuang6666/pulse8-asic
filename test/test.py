"""Port-only regression for both RTL and the official physical-flow netlist.

All program writes use the actual host SPI pins. Expected UART/SPI waveforms and
timestamp arithmetic are independent of the RTL; no internal signals are read.
The official GL Makefile uses FUNCTIONAL models, so this is not an SDF test.
"""
from pathlib import Path
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.assembler import assemble

CLOCK_NS = 42  # Conservative simulation period for the 24 MHz timing target.
HOST_HALF_NS = 5 * CLOCK_NS


class Bench:
    def __init__(self, dut):
        self.dut = dut
        self.external = 0xff

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, CLOCK_NS, unit="ns").start(start_high=False))
        await self.reset()

    async def tick(self, count=1):
        for _ in range(count):
            await RisingEdge(self.dut.clk)
            await Timer(1, unit="ns")

    def inputs(self, value):
        self.external = value & 255
        self.dut.uio_in.value = self.external

    def pin(self, number, value):
        self.inputs((self.external & ~(1 << number)) | (int(value) << number))

    async def reset(self):
        self.dut.ena.value = 1
        self.dut.rst_n.value = 0
        self.dut.ui_in.value = 4
        self.inputs(255)
        await self.tick(8)
        assert int(self.dut.uio_oe.value) == 0, "reset must release GPIO"
        self.dut.rst_n.value = 1
        await self.tick(8)

    async def transfer(self, command, data=0, length=40):
        request = (command << 32) | data
        response = 0
        self.dut.ui_in.value = 0
        await Timer(HOST_HALF_NS, unit="ns")
        for index in range(length):
            bit = ((request >> (39-index)) & 1) if index < 40 else 0
            self.dut.ui_in.value = bit << 1
            await Timer(HOST_HALF_NS, unit="ns")
            self.dut.ui_in.value = (bit << 1) | 1
            # Sample at the master's edge, before the oversampled slave detects it.
            await Timer(1, unit="ns")
            response = (response << 1) | (int(self.dut.uo_out.value) & 1)
            await Timer(HOST_HALF_NS-1, unit="ns")
            self.dut.ui_in.value = bit << 1
        await Timer(HOST_HALF_NS, unit="ns")
        self.dut.ui_in.value = 4
        await Timer(2*HOST_HALF_NS, unit="ns")
        return response & 0xffffffff

    async def load(self, source):
        words = assemble(source) if isinstance(source, str) else source
        for address, word in enumerate(words):
            await self.transfer(0x80 | address, word)

    async def example(self, name):
        await self.load((ROOT / "examples" / (name + ".p8")).read_text())

    async def receive(self, expected):
        for _ in range(100):
            if int(self.dut.uo_out.value) & 0x10:
                break
            await self.tick()
        else:
            raise AssertionError("RX byte did not become available")
        response = await self.transfer(5)
        assert response & (1 << 29), "read snapshot must contain a valid RX byte"
        assert (response >> 16) & 255 == expected, (hex(response), hex(expected))
        assert not response & 0xc0000000, "unexpected host/core fault"
        return response

    async def fault(self, code):
        response = await self.transfer(0)
        assert response & (1 << 30), "expected core fault"
        assert (response >> 24) & 7 == code, hex(response)
        assert int(self.dut.uio_oe.value) == 0, "fault must release GPIO"


@cocotb.test()
async def loader_framing_reset_and_open_drain(dut):
    b = Bench(dut)
    await b.start()
    for length in (0, 7, 39, 41, 48):
        await b.reset()
        await b.transfer(0x80, 0xf0000000, length=length)
        assert int(dut.uo_out.value) & 0x80, "malformed frame must set host error"
        await b.transfer(6)
        await b.transfer(1)
        await b.fault(1)  # Rejected writes cannot mark program RAM as loaded.

    await b.reset()
    await b.load("PINS 165, 255\nSET 90\nPUSH 0\nHALT")
    await b.transfer(3, 0x0f)
    await b.transfer(1)
    assert int(dut.uio_out.value) == 0xa5
    assert int(dut.uio_oe.value) == 0xfa, "open-drain high bits must be released"
    await b.receive(0x5a)
    # Reset/deselection must release a deliberately driven bus immediately.
    dut.ena.value = 0
    await Timer(1, unit="ns")
    assert int(dut.uio_oe.value) == 0
    await b.tick(8)
    dut.ena.value = 1
    await b.tick(8)
    await b.transfer(1)
    await b.fault(1)

    await b.reset()
    await b.load("PINS 255, 255\nWAIT 0, 0\nHALT")
    await b.transfer(1)
    assert int(dut.uio_oe.value) == 255
    # Start an incomplete programming frame, then reset in the middle of it.
    dut.ui_in.value = 0
    await b.tick(8)
    dut.ui_in.value = 3
    await b.tick(8)
    dut.rst_n.value = 0
    await Timer(1, unit="ns")
    assert int(dut.uio_oe.value) == 0
    await b.reset()
    await b.transfer(1)
    await b.fault(1)


@cocotb.test()
async def receive_dependent_extensions_and_branch_validation(dut):
    b = Bench(dut)
    await b.start()
    b.inputs(0xa6)
    serial_sample = "\n".join(f"IN {pin}, 1" for pin in range(7, -1, -1))
    await b.load(serial_sample + """
MOVISR
PUSH 0
SAMPLE 242
AND 60
JNZ nonzero
SET 238
nonzero: PUSH 0
SAMPLE 0
JNZ wrong
SET 90
PUSH 0
HALT
wrong: SET 224
PUSH 0
HALT
""")
    await b.transfer(1)
    await b.receive(0xa6)
    await b.receive(0x20)  # (0xa6 & 0xf2) & 0x3c, taken JNZ.
    await b.receive(0x5a)  # Zero SAMPLE makes JNZ fall through.
    assert not int(dut.uo_out.value) & 4, "program should halt after third result"

    # Raw malformed JNZ must fault even if A is zero (branch would not be taken).
    await b.reset()
    await b.load([0x00000440, 0xf0000000])
    await b.transfer(1)
    await b.fault(3)


@cocotb.test()
async def timestamp_edge_count_coherence_and_saturation(dut):
    b = Bench(dut)
    await b.start()
    await b.load("TRESET\nNOP [254]\nTSTAMP\nPUSH 0\nPUSH 1\nHALT")
    await b.transfer(1)
    await b.tick(600)
    # 255 NOP edges + capture edge = 256. The high byte must retain the
    # captured value despite several hundred more elapsed cycles/backpressure.
    await b.receive(0)
    await b.receive(1)

    await b.reset()
    await b.load("TRESET\nTSTAMP\nPUSH 0\nHALT")
    await b.transfer(1)
    await b.receive(1)

    await b.reset()
    await b.load("""
TRESET
SETX 17
loop: NOP [4095]
DJNZ loop
TSTAMP
PUSH 0
PUSH 1
HALT
""")
    await b.transfer(1)
    await Timer(70000*CLOCK_NS, unit="ns")
    await b.receive(255)
    await b.receive(255)  # Overlong intervals saturate rather than wrap.


async def uart_monitor(b, value):
    for _ in range(600):
        if int(b.dut.uio_oe.value) & 1 and not int(b.dut.uio_out.value) & 1:
            break
        await b.tick()
    else:
        raise AssertionError("UART start bit was not observed")
    for cycle in range(10*208):
        bit_index = cycle // 208
        expected = 0 if bit_index == 0 else (1 if bit_index == 9 else (value >> (bit_index-1)) & 1)
        assert int(b.dut.uio_oe.value) & 1, "UART TX must remain driven"
        assert int(b.dut.uio_out.value) & 1 == expected, (cycle, expected)
        await b.tick()


@cocotb.test()
async def uart_transmit_and_receive_waveforms(dut):
    b = Bench(dut)
    await b.start()
    await b.example("uart_tx")
    for value in (0xa5, 0x00):
        await b.transfer(4, value)
        monitor = cocotb.start_soon(uart_monitor(b, value))
        await b.transfer(1)
        await with_timeout(monitor, 200, "us")
        assert not int(dut.uo_out.value) & 8
        await b.tick(8)

    for good_stop in (True, False):
        await b.reset()
        await b.example("uart_rx")
        await b.transfer(1)
        await b.tick(20)
        b.pin(0, 0)
        await b.tick(208)
        for bit in range(8):
            b.pin(0, (0x96 >> bit) & 1)
            await b.tick(208)
        b.pin(0, good_stop)
        await b.tick(208)
        b.pin(0, 1)
        if good_stop:
            await b.receive(0x96)
        else:
            await b.fault(2)


async def spi_target(b, mode, transmitted, received):
    cpol, cpha = (mode >> 1) & 1, mode & 1
    samples = edges = 0
    old_sck = cpol
    last_edge = None
    b.pin(2, (received >> 7) & 1)
    for _ in range(600):
        if int(b.dut.uio_oe.value) & 8 and not int(b.dut.uio_out.value) & 8:
            break
        await b.tick()
    else:
        raise AssertionError("SPI CS assertion was not observed")
    for cycle in range(5000):
        await b.tick()
        pins = int(b.dut.uio_out.value)
        assert int(b.dut.uio_oe.value) == 11, "SPI drive directions must be SCK/MOSI/CS only"
        sck = pins & 1
        if sck != old_sck:
            if last_edge is not None:
                assert cycle-last_edge == 120, "SPI half-period must be 120 clocks"
            last_edge = cycle
            edges += 1
            sample_edge = (sck != cpol) if not cpha else (sck == cpol)
            if sample_edge:
                assert samples < 8
                assert (pins >> 1) & 1 == (transmitted >> (7-samples)) & 1
                samples += 1
            else:
                if samples < 8:
                    b.pin(2, (received >> (7-samples)) & 1)
            old_sck = sck
        if pins & 8:
            assert edges == 16 and samples == 8, (edges, samples)
            assert sck == cpol
            return
    raise AssertionError("SPI transaction did not deassert CS")


@cocotb.test()
async def spi_four_modes_full_duplex(dut):
    b = Bench(dut)
    await b.start()
    for mode in range(4):
        await b.reset()
        await b.example(f"spi_mode{mode}")
        await b.transfer(4, 0xa5)
        target = cocotb.start_soon(spi_target(b, mode, 0xa5, 0x3c))
        await b.transfer(1)
        await with_timeout(target, 250, "us")
        await b.receive(0x3c)
