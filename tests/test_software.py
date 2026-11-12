import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.assembler import assemble, AssemblyError
from tools.host import Pulse8, Status

class AssemblerTests(unittest.TestCase):
    def test_known_encoding(self):
        self.assertEqual(assemble('PINS 0xa5, 0xff [208-1]\nHALT'), [0x10cfa5ff,0xf0000000])
    def test_forward_and_backward_labels(self):
        self.assertEqual(assemble('start: JMP end\nNOP\nend: DJNZ start'),[0x60000200,0,0x70000000])
    def test_operand_boundaries(self):
        for src in ['OUT 8, 0','IN 0, 2','JMP 64','SET -1','PINS 256, 1',
                    'NOP [4096]','NOP [-1]','PUSH 2','WAIT 0','NOP 1',
                    'X: NOP\nX: HALT','JMP missing','BAD','', 'NOP\n'*65,
                    'SET __import__("os")','SET True','NOP [1*2]']:
            with self.subTest(src=src), self.assertRaises(AssemblyError): assemble(src)
    def test_capacity(self):
        self.assertEqual(len(assemble('NOP\n'*64)),64)
    def test_comments_and_expression(self):
        self.assertEqual(assemble('; comment\na: NOP # x\nJMP a+1 [4095]'),[0,0x6fff0100])
    def test_all_examples_fit(self):
        for p in (Path(__file__).resolve().parents[1]/'examples').glob('*.p8'):
            with self.subTest(path=p.name): self.assertLessEqual(len(assemble(p.read_text())),64)

class HostTests(unittest.TestCase):
    def test_status_decode(self):
        s=Status.decode(bytes([0,0xfa,0x42,63,0xa5]))
        self.assertTrue(s.host_error and s.fault and s.rx_valid and s.tx_ready and s.running)
        self.assertEqual((s.fault_code,s.received,s.pc,s.accumulator),(2,0x42,63,0xa5))
    def test_load_fills_tail_and_uses_big_endian(self):
        sent=[]
        def transfer(packet):
            sent.append(packet)
            return bytes([0,16,0,0,0])
        dev=Pulse8(transfer)
        dev.load([0x12345678],3)
        self.assertEqual(sent[:4],[bytes([2,0,0,0,0]),bytes([6,0,0,0,0]),bytes([3,0,0,0,3]),bytes([128,0x12,0x34,0x56,0x78])])
        self.assertEqual(sent[66],bytes([191,0xf0,0,0,0]))
        self.assertEqual(sent[-1],bytes(5))
    def test_tx_backpressure(self):
        dev=Pulse8(lambda _:bytes(5))
        with self.assertRaises(BufferError): dev.send(42)
    def test_bad_inputs(self):
        dev=Pulse8(lambda _:bytes([0,16,0,0,0]))
        for words in [[],[0]*65,[-1],[1<<32]]:
            with self.assertRaises(ValueError): dev.load(words)
        with self.assertRaises(ValueError): dev.load([0],256)
        with self.assertRaises(ValueError): dev.send(256)

if __name__=='__main__': unittest.main()
