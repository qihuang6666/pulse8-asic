"""Run portable assembler/host tests, Icarus RTL tests and optional synthesis.

python tools/check.py --iverilog PATH --vvp PATH [--yosys PATH] [--waves]
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.assembler import assemble

ROOT=Path(__file__).resolve().parents[1]
BENCHES = [('tb_system', 'rtl-tests'), ('tb_extensions', 'extension-tests'),
           ('tb_protocol_extensions', 'protocol-extension-tests')]
def run(command, log):
    result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (ROOT/'work'/log).write_text(result.stdout)
    print('\n'.join(result.stdout.splitlines()[-35:]) if log in ('synthesis.log','mapping.log') else result.stdout,end='\n')
    if result.returncode: raise SystemExit(result.returncode)

def simulate(args, sources, prefix='', defines=()):
    """Run the same independent port-level monitors at each implementation level."""
    ivl_dir=Path(args.iverilog).resolve().parent.parent/'lib/ivl'
    ivl_args=['-B',str(ivl_dir)] if ivl_dir.is_dir() else []
    vvp_args=['-M','-','-M',str(ivl_dir)] if ivl_dir.is_dir() else []
    for bench, label in BENCHES:
        binary=f'work/{prefix}{bench}.vvp'
        run([args.iverilog,*ivl_args,'-g2012','-Wall','-Iwork',*defines,
             '-s',bench,'-o',binary,*sources,f'tests/{bench}.v'],f'{prefix}{bench}-compile.log')
        run([args.vvp,*vvp_args,binary]+(['+waves'] if getattr(args,'waves',False) else []),
            f'{prefix}{label}.log')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iverilog',default='iverilog')
    p.add_argument('--vvp',default='vvp')
    p.add_argument('--yosys')
    p.add_argument('--yosys-wasm',action='store_true',help='use installed yowasp_yosys Python module')
    p.add_argument('--synth-only',action='store_true',help='reuse prior generated vectors; run synthesis and netlist simulation only')
    p.add_argument('--waves',action='store_true')
    args=p.parse_args()
    (ROOT/'work').mkdir(exist_ok=True)
    sizes={}
    for source in sorted((ROOT/'examples').glob('*.p8')):
        words=assemble(source.read_text()); sizes[source.stem]=len(words)
        (ROOT/'work'/f'{source.stem}.hex').write_text(''.join(f'{w:08x}\n' for w in words))
    isa='''SET 254
ADD 3
XOR 1
JZ init
SET 255
init: SETX 3
loop: ADD 1
DJNZ loop
PINS 15, 255
MASK 80, 240
JMP done
SET 255
done: PUSH 0
HALT
'''
    words=assemble(isa); sizes['isa']=len(words)
    (ROOT/'work/isa.hex').write_text(''.join(f'{w:08x}\n' for w in words))
    (ROOT/'work/program_sizes.vh').write_text(''.join(f'localparam {n.upper()}_WORDS={v};\n' for n,v in sizes.items()))
    ivl_dir=Path(args.iverilog).resolve().parent.parent/'lib/ivl'
    ivl_args=['-B',str(ivl_dir)] if ivl_dir.is_dir() else []
    vvp_args=['-M','-','-M',str(ivl_dir)] if ivl_dir.is_dir() else []
    if not args.synth_only:
        run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'],'software-tests.log')
        simulate(args,['src/project.v','src/host_spi.v'])
        run([args.iverilog,*ivl_args,'-g2012','-Wall','-s','tb_host_random','-o','work/host_random.vvp',
             'src/host_spi.v','tests/tb_host_random.v'],'host-phase-compile.log')
        run([args.vvp,*vvp_args,'work/host_random.vvp'],'host-phase-tests.log')
        run([args.iverilog,*ivl_args,'-g2012','-Wall','-s','tb_mailbox_random','-o','work/mailbox_random.vvp',
             'src/project.v','src/host_spi.v','tests/tb_mailbox_random.v'],'mailbox-stress-compile.log')
        run([args.vvp,*vvp_args,'work/mailbox_random.vvp'],'mailbox-stress-tests.log')
    if args.yosys or args.yosys_wasm:
        script='read_verilog src/project.v src/host_spi.v; synth -top tt_um_pulse8_proto; check -assert; stat; write_verilog -noattr work/generic_netlist.v'
        command=[sys.executable,'-c','import sys; from yowasp_yosys import run_yosys; sys.exit(run_yosys(sys.argv[1:]))'] if args.yosys_wasm else [args.yosys]
        run([*command,'-Q','-T','-p',script],'synthesis.log')
        simulate(args,['work/generic_netlist.v'],'generic-')
    (ROOT/'work/results.json').write_text(json.dumps({'software':'prior run' if args.synth_only else 'pass','rtl':'prior run' if args.synth_only else 'pass','host_phase_framing':'prior run' if args.synth_only else 'pass','generic_synthesis':'pass' if (args.yosys or args.yosys_wasm) else 'not run','program_words':sizes},indent=2))

if __name__=='__main__': main()
