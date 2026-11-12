"""Pulse8 assembler. Standard-library only; rejects out-of-range operands."""
from __future__ import annotations
import argparse
import ast
import re
from pathlib import Path

# opcode, inclusive maximum for each operand
OPS = {
    'NOP': (0, ()), 'PINS': (1, (255, 255)), 'SET': (2, (255,)),
    'SETX': (3, (255,)), 'OUT': (4, (7, 1)), 'IN': (5, (7, 1)),
    'JMP': (6, (63,)), 'DJNZ': (7, (63,)), 'WAIT': (8, (7, 1)),
    'PULL': (9, ()), 'PUSH': (10, (1,)), 'XOR': (11, (255,)),
    'ADD': (12, (255,)), 'JZ': (13, (63,)), 'MASK': (14, (255, 255)),
    'HALT': (15, ()),
    'MOVISR': (0, ()), 'SAMPLE': (0, (255,)), 'AND': (0, (255,)),
    'JNZ': (0, (63,)), 'TRESET': (0, ()), 'TSTAMP': (0, ()),
}
# Operand a selects an opcode-0 extension; its optional operand goes in b.
EXTENSIONS = {'MOVISR': 1, 'SAMPLE': 2, 'AND': 3, 'JNZ': 4,
              'TRESET': 5, 'TSTAMP': 6}

class AssemblyError(ValueError):
    pass

def expression(text: str, symbols: dict[str, int]) -> int:
    def visit(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id in symbols:
            return symbols[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            v = visit(node.operand)
            return v if isinstance(node.op, ast.UAdd) else -v
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
            lhs, rhs = visit(node.left), visit(node.right)
            return lhs + rhs if isinstance(node.op, ast.Add) else lhs - rhs
        raise AssemblyError(f'unsupported expression or unknown symbol: {text}')
    try:
        return visit(ast.parse(text, mode='eval').body)
    except SyntaxError as exc:
        raise AssemblyError(f'invalid expression: {text}') from exc

def assemble(source: str) -> list[int]:
    symbols, statements = {}, []
    for line_number, raw in enumerate(source.splitlines(), 1):
        line = re.split(r'[;#]', raw, maxsplit=1)[0].strip()
        if not line:
            continue
        match = re.match(r'^([A-Za-z_]\w*):', line)
        if match:
            name = match[1]
            if name in symbols:
                raise AssemblyError(f'line {line_number}: duplicate label {name}')
            symbols[name] = len(statements)
            line = line[match.end():].strip()
        if line:
            statements.append((line_number, line))
    if not 1 <= len(statements) <= 64:
        raise AssemblyError('program must contain 1..64 instructions')
    words = []
    for line_number, line in statements:
        try:
            delay = 0
            match = re.search(r'\[([^\[\]]+)\]\s*$', line)
            if match:
                delay = expression(match[1], symbols)
                line = line[:match.start()].strip()
            if not 0 <= delay <= 4095:
                raise AssemblyError('delay/timeout must be 0..4095')
            parts = line.split(None, 1)
            name = parts[0].upper()
            if name not in OPS:
                raise AssemblyError(f'unknown instruction {name}')
            opcode, limits = OPS[name]
            args = [s.strip() for s in parts[1].split(',')] if len(parts) == 2 else []
            if len(args) != len(limits):
                raise AssemblyError(f'{name} expects {len(limits)} operands')
            values = [expression(arg, symbols) for arg in args]
            for value, maximum in zip(values, limits):
                if not 0 <= value <= maximum:
                    raise AssemblyError(f'operand {value} is outside 0..{maximum}')
            if name in EXTENSIONS:
                values = [EXTENSIONS[name], values[0] if values else 0]
            else:
                values += [0] * (2 - len(values))
            words.append((opcode << 28) | (delay << 16) | (values[0] << 8) | values[1])
        except AssemblyError as exc:
            raise AssemblyError(f'line {line_number}: {exc}') from exc
    return words

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('-o', '--output', type=Path, required=True)
    parser.add_argument('--packets', action='store_true', help='emit binary STOP + program-write SPI frames')
    args = parser.parse_args()
    try:
        words = assemble(args.source.read_text())
    except AssemblyError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.packets:
        data = b'\x02\x00\x00\x00\x00' + b''.join(bytes([0x80+i]) + word.to_bytes(4, 'big') for i,word in enumerate(words))
        args.output.write_bytes(data)
    else:
        args.output.write_text(''.join(f'{word:08x}\n' for word in words))
    print(f'{args.source.name}: {len(words)}/64 words -> {args.output}')

if __name__ == '__main__':
    main()
