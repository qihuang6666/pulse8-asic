"""Transport-neutral host driver; transfer must assert CS for exactly five bytes.

Use SPI mode 0, MSB first, <= clk/8; leave CS high for >= four clk cycles.
An adapter must return the five received bytes. No hardware-specific API assumed.
"""
from dataclasses import dataclass
import time

@dataclass(frozen=True)
class Status:
    host_error: bool
    fault: bool
    rx_valid: bool
    tx_ready: bool
    running: bool
    fault_code: int
    received: int
    pc: int
    accumulator: int

    @classmethod
    def decode(cls, packet):
        if len(packet) != 5:
            raise ValueError('SPI transport must return five bytes')
        s = packet[1]
        return cls(bool(s & 128), bool(s & 64), bool(s & 32), bool(s & 16),
                   bool(s & 8), s & 7, packet[2], packet[3], packet[4])

class Pulse8:
    def __init__(self, transfer):
        self.transfer = transfer

    def command(self, command, payload=0):
        if not 0 <= command <= 255 or not 0 <= payload <= 0xffffffff:
            raise ValueError('command/payload out of range')
        return Status.decode(self.transfer(bytes([command]) + payload.to_bytes(4, 'big')))

    def status(self):
        return self.command(0)

    def stop(self):
        self.command(2)

    def load(self, words, open_drain=0):
        words = list(words)
        if not 1 <= len(words) <= 64 or any(not 0 <= w <= 0xffffffff for w in words):
            raise ValueError('program must contain 1..64 unsigned 32-bit words')
        if not 0 <= open_drain <= 255:
            raise ValueError('open_drain must be an 8-bit mask')
        self.stop()
        self.command(6)
        self.command(3, open_drain)
        for addr, word in enumerate(words):
            self.command(0x80 | addr, word)
        # Invalidate the unused tail semantically with HALTs, preventing fallthrough
        # into a previous longer program after a reload without reset.
        for addr in range(len(words), 64):
            self.command(0x80 | addr, 0xf0000000)
        if self.status().host_error:
            raise RuntimeError('program load rejected by device')

    def send(self, value):
        if not 0 <= value <= 255:
            raise ValueError('TX value must be 0..255')
        if not self.status().tx_ready:
            raise BufferError('TX mailbox is full')
        self.command(4, value)

    def start(self):
        self.command(1)

    def receive(self, timeout=1.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            status = self.command(5)
            if status.host_error or status.fault:
                raise RuntimeError(f'device error: {status}')
            if status.rx_valid:
                return status.received
        raise TimeoutError('RX mailbox remained empty')
