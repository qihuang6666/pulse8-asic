"""Encoding checks independent of the RTL extension decoder."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.assembler import assemble, AssemblyError


class ExtensionAssemblerTests(unittest.TestCase):
    def test_extension_encoding(self):
        self.assertEqual(assemble('MOVISR\nSAMPLE 165\nAND 15 [7]\nJNZ 63\nTRESET\nTSTAMP'),
                         [0x00000100, 0x000002a5, 0x0007030f,
                          0x0000043f, 0x00000500, 0x00000600])

    def test_extension_label_and_delay(self):
        self.assertEqual(assemble('again: SAMPLE 1 [4095]\nJNZ again\nTSTAMP [255]'),
                         [0x0fff0201, 0x00000400, 0x00ff0600])

    def test_extension_rejects_invalid_operands(self):
        for source in ['JNZ 64', 'JNZ -1', 'JNZ missing', 'JNZ',
                       'SAMPLE 256', 'SAMPLE -1', 'SAMPLE', 'AND 256',
                       'AND -1', 'AND 0, 1', 'MOVISR 1', 'TRESET 1',
                       'TSTAMP 1', 'TSTAMP [4096]']:
            with self.subTest(source=source), self.assertRaises(AssemblyError):
                assemble(source)

    def test_canonical_nop_unchanged(self):
        self.assertEqual(assemble('NOP\nNOP [4095]'), [0, 0x0fff0000])


if __name__ == '__main__':
    unittest.main()
