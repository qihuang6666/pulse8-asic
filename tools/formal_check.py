"""Bounded core safety checks using Yosys SAT with an abstract host-command boundary.

Requires yowasp-yosys. This is a finite-depth check, not an unbounded proof.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--depth',type=int,default=12)
    args=parser.parse_args()
    if args.depth<8: parser.error('depth must be at least 8 for the reachability checks')
    (ROOT/'work').mkdir(exist_ok=True)
    setup=('read_verilog -formal -sv -D PULSE8_FORMAL_CORE -Iformal '
           'src/project.v formal/host_abstract.v; '
           'prep -top tt_um_pulse8_proto -flatten; memory_map; async2sync; opt_clean; ')
    base=f'-seq {args.depth} -set-at 1 rst_n 0 -set-at 1 ena 1 -timeout 45'
    proof=f'sat {base} -prove-asserts -verify -dump_vcd work/formal_failure.vcd; '
    covers=['write_blocked','push_blocked','rx_pop','wait_timeout']
    script=setup+proof
    for cover in covers:
        script+=(f'sat {base} -set-at {args.depth} f_cover_{cover} 1 '
                 f'-show f_cover_{cover} -dump_vcd work/cover_{cover}.vcd; ')
    command=[sys.executable,'-c','import sys; from yowasp_yosys import run_yosys; sys.exit(run_yosys(sys.argv[1:]))',
             '-Q','-T','-l','work/formal-yosys.log','-p',script]
    result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (ROOT/'work/formal-console.log').write_text(result.stdout)
    log=(ROOT/'work/formal-yosys.log').read_text() if (ROOT/'work/formal-yosys.log').exists() else result.stdout
    proven='SAT proof finished - no model found: SUCCESS!' in log
    reached=log.count('SAT solving finished - model found:')
    if result.returncode or not proven or reached!=len(covers):
        print('\n'.join(log.splitlines()[-80:]))
        raise SystemExit(result.returncode or 1)
    evidence={'core_safety':'bounded pass','depth':args.depth,'reachable_scenarios':covers,
              'scope':'arbitrary decoded host requests; reset at first edge; arbitrary initial instruction memory; digital two-state model',
              'unbounded_proof':False}
    (ROOT/'work/formal-results.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(f'BOUNDED CORE CHECKS PASSED: {args.depth} cycles, {len(covers)} reachable scenarios')
    print('Scope: abstract decoded-host boundary; no analog CDC or unbounded liveness claim.')

if __name__=='__main__': main()
