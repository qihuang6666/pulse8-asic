"""Preliminary CMOS5L mapping and zero-delay cell simulation, not physical sign-off.

Supply a local checkout of https://github.com/IHP-GmbH/ihp-sg13cmos5l.
Requires the generated vectors from tools/check.py and Python yowasp-yosys.
"""
import argparse
import json
from pathlib import Path
import shutil
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.check import ROOT,run,simulate

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pdk-root',type=Path,required=True)
    parser.add_argument('--iverilog',default='iverilog')
    parser.add_argument('--vvp',default='vvp')
    args=parser.parse_args()
    libroot=args.pdk_root/'libs.ref/sg13cmos5l_stdcell'
    destination=ROOT/'work/pdk'
    destination.mkdir(parents=True,exist_ok=True)
    library='sg13cmos5l_stdcell_typ_1p20V_25C.lib'
    for part,name in [('lib',library),('verilog','sg13cmos5l_stdcell.v'),('verilog','sg13cmos5l_udp.v')]:
        shutil.copyfile(libroot/part/name,destination/name)
    lib=f'work/pdk/{library}'
    script=(f'read_verilog src/project.v src/host_spi.v; '
            f'synth -top tt_um_pulse8_proto -flatten -noabc; '
            f'dfflibmap -liberty {lib}; abc -liberty {lib}; clean; '
            f'read_liberty -lib {lib}; hierarchy -check -top tt_um_pulse8_proto; check -assert; '
            f'tee -o work/mapped_stats.json stat -json -liberty {lib}; '
            f'write_verilog -noattr work/cmos5l_netlist.v')
    run([sys.executable,'-c','import sys; from yowasp_yosys import run_yosys; sys.exit(run_yosys(sys.argv[1:]))',
         '-Q','-T','-l','work/mapping-yosys.log','-p',script],'mapping.log')
    simulate(args,['work/pdk/sg13cmos5l_udp.v','work/pdk/sg13cmos5l_stdcell.v',
                   'work/cmos5l_netlist.v'],'mapped-',('-DFUNCTIONAL','-DSIM'))
    stats=json.loads((ROOT/'work/mapped_stats.json').read_text())
    print(json.dumps(stats,indent=2))

if __name__=='__main__': main()
