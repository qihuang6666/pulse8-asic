"""Run three existing port-only benches on an official hardened submission netlist.

This is zero-delay FUNCTIONAL/SIM simulation. No SDF, extracted delay, power,
or electrical timing is simulated. It supplements the official Tiny Tapeout
flow and does not replace its precheck, physical verification, or timing reports.

Required provenance inputs come from the trusted GitHub Actions run/artifact:
  --commit FULL_SHA --repo OWNER/REPO --run-id NUMBER --sha256 ARTIFACT_DIGEST
Obtain the SHA256 from GitHub's artifact digest or successful download log,
not merely by hashing an untrusted ZIP. The runner checks these expectations
against the ZIP bytes and tt_submission/commit_id.json. It cannot authenticate
caller-supplied expectations independently and makes no network requests.

--pdk-root accepts the official IHP-Open-PDK checkout root, or its
ihp-sg13cmos5l directory. The exact supported PDK revision is pinned below.
The three model files must match the Git blob identities at that revision;
a full Git checkout is not required. Files fetched from the corresponding
GitHub blob URLs are also accepted, provided their exact bytes match. Git
checkouts must disable autocrlf for these files. A different PDK version fails
until its source model identities have been independently reviewed and added.

Example (from the repository root):
  python tools/test_hardened.py --submission tt_submission.zip \
    --repo OWNER/REPO --run-id NUMBER --commit FULL_SHA --sha256 DIGEST \
    --pdk-root /path/to/IHP-Open-PDK

Outputs go under work/hardened/<commit-prefix>-<archive-hash-prefix>/.
All three testbenches and the assembler come from this working checkout and
their hashes are recorded; archived RTL must match this checkout (LF/CRLF
differences ignored). The archive is never extracted wholesale: only one
validated, fixed-name netlist is materialized, with metadata read in memory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.assembler import assemble

PDK_VERSION = '89d42ee6d2fd9b50b86a1aada6fee6673c3e6008'
PDK_REPO = 'https://github.com/IHP-GmbH/IHP-Open-PDK'
# GitHub contents API blob identities at the exact PDK_VERSION above.
MODELS = {
    'libs.ref/sg13cmos5l_io/verilog/sg13cmos5l_io.v':
        'ab0b13f734999aa2748c8432fdf182b5d6c785a4',
    'libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v':
        'ca53cb9a45c16d0ed276d396300760d372048b33',
    'libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v':
        '0d8e5f4d1a8950c80cddbe1f5ecadc08d1a6aa52',
}
BENCHES = {
    'tb_system': r'ALL RTL TESTS PASSED: (\d+) assertions',
    'tb_extensions': r'PASS: (\d+) extension assertions;',
    'tb_protocol_extensions': r'ALL PROTOCOL EXTENSION TESTS PASSED: (\d+) assertions',
}
# Same arithmetic/branch program as tools/check.py; generated locally so stale
# or missing work/ vectors cannot silently affect the hardened-netlist test.
ISA = '''SET 254
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


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_members(archive):
    """Reject ambiguous names, traversal, links and unreasonable archive sizes."""
    seen = set()
    total = 0
    for member in archive.infolist():
        name = member.filename
        path = PurePosixPath(name)
        require(name and '\\' not in name and ':' not in name and '\0' not in name,
                f'Unsafe ZIP member name: {name!r}')
        require(not path.is_absolute() and '..' not in path.parts and '.' not in path.parts,
                f'Unsafe ZIP member path: {name!r}')
        canonical = path.as_posix().rstrip('/')
        require(canonical == name.rstrip('/') and canonical.casefold() not in seen,
                f'Duplicate or noncanonical ZIP member: {name!r}')
        seen.add(canonical.casefold())
        mode = member.external_attr >> 16
        require(not stat.S_ISLNK(mode), f'Symlink ZIP member rejected: {name}')
        require(member.file_size <= 128 * 1024 * 1024, f'ZIP member too large: {name}')
        total += member.file_size
        require(total <= 512 * 1024 * 1024, 'Uncompressed ZIP exceeds 512 MiB limit')


def read_member(archive, name, limit):
    member = archive.getinfo(name)
    require(not member.is_dir() and member.file_size <= limit,
            f'Missing, directory, or oversized required ZIP member: {name}')
    return archive.read(member)


def generate_vectors(work):
    vectors = {}
    source_hashes = {}
    for source in sorted((ROOT / 'examples').glob('*.p8')):
        data = source.read_bytes()
        vectors[source.stem] = assemble(data.decode('utf-8'))
        source_hashes[source.relative_to(ROOT).as_posix()] = sha256(data)
    vectors['isa'] = assemble(ISA)
    for name, words in vectors.items():
        (work / f'{name}.hex').write_text(''.join(f'{word:08x}\n' for word in words), encoding='ascii')
    (work / 'program_sizes.vh').write_text(''.join(
        f'localparam {name.upper()}_WORDS={len(words)};\n' for name, words in vectors.items()),
        encoding='ascii')
    return source_hashes, {path.name: sha256(path.read_bytes()) for path in work.glob('*.hex')}


def execute(command, directory, label, timeout):
    command = [str(part) for part in command]
    (directory / f'{label}-command.json').write_text(json.dumps(command, indent=2) + '\n', encoding='utf-8')
    log = directory / f'{label}.log'
    with log.open('w', encoding='utf-8') as output:
        result = subprocess.run(command, cwd=directory, stdout=output, stderr=subprocess.STDOUT,
                                text=True, timeout=timeout, shell=False)
    content = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode:
        raise RuntimeError(f'{label} failed with exit {result.returncode}; see {log}')
    return content


def run_bench(bench, marker, directory, work, iverilog, vvp, ivl_args, vvp_args,
              model_paths, timeout):
    """Each worker has separate source, binary and log paths; vectors are read-only."""
    source = ROOT / 'tests' / f'{bench}.v'
    bench_bytes = source.read_bytes()
    saved_source = work / f'{bench}.v'
    saved_source.write_bytes(bench_bytes)
    binary = work / f'{bench}.vvp'
    execute([iverilog, *ivl_args, '-g2012', '-Wall', '-DFUNCTIONAL', '-DSIM',
             '-I' + str(work), '-s', bench, '-o', binary, *model_paths,
             work / 'official_netlist.v', saved_source], directory, f'{bench}-compile', timeout)
    output = execute([vvp, *vvp_args, binary], directory, bench, timeout)
    matches = re.findall(marker, output)
    require(len(matches) == 1 and int(matches[0]) > 0,
            f'{bench} exited without its expected success marker; inspect the log')
    require(not re.search(r'(?im)^\s*(FAIL|FATAL|ERROR)\b', output), f'{bench} reported a simulation error')
    return {'status': 'pass', 'assertions': int(matches[0]),
            'testbench_sha256': sha256(bench_bytes),
            'log_sha256': sha256((directory / f'{bench}.log').read_bytes())}, output


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--submission', type=Path, required=True)
    parser.add_argument('--pdk-root', type=Path, required=True)
    parser.add_argument('--repo', required=True, help='Expected GitHub owner/repository')
    parser.add_argument('--run-id', type=int, required=True)
    parser.add_argument('--commit', required=True, help='Expected full 40-character source commit')
    parser.add_argument('--sha256', required=True, help='Trusted official artifact SHA256 digest')
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    parser.add_argument('--timeout', type=int, default=900, help='Per compile/simulation limit in seconds')
    parser.add_argument('--jobs', type=int, choices=(1, 2, 3), default=1,
                        help='Concurrent independent benches (default: 1; maximum: 3)')
    args = parser.parse_args()
    result_path = None
    evidence = {'status': 'validating', 'simulation': 'zero-delay FUNCTIONAL/SIM; no SDF or extracted delays',
                'started_utc': datetime.now(timezone.utc).isoformat()}
    try:
        require(re.fullmatch(r'[0-9a-fA-F]{40}', args.commit), '--commit must be a full hexadecimal SHA')
        require(re.fullmatch(r'[0-9a-fA-F]{64}', args.sha256), '--sha256 must have 64 hexadecimal digits')
        require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo), '--repo must be OWNER/REPO')
        require(args.run_id > 0 and args.timeout > 0, '--run-id and --timeout must be positive')
        archive_bytes = args.submission.read_bytes()
        archive_hash = sha256(archive_bytes)
        require(archive_hash == args.sha256.lower(), 'Submission archive digest does not match trusted expected SHA256')
        directory = ROOT / 'work' / 'hardened' / f'{args.commit[:12].lower()}-{archive_hash[:12]}'
        directory.mkdir(parents=True, exist_ok=True)
        result_path = directory / 'results.json'
        # Invalidate an older pass before revalidating the same artifact/models.
        result_path.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
        with ZipFile(args.submission) as archive:
            validate_members(archive)
            commit = json.loads(read_member(archive, 'tt_submission/commit_id.json', 1024 * 1024))
            pdk = json.loads(read_member(archive, 'tt_submission/pdk.json', 1024 * 1024))
            require(isinstance(commit, dict) and isinstance(pdk, dict), 'Archive metadata must contain JSON objects')
            expected_repo = f'https://github.com/{args.repo}'
            expected_workflow = f'{expected_repo}/actions/runs/{args.run_id}'
            require(commit.get('commit') == args.commit.lower(), 'Archived source commit differs from --commit')
            require(commit.get('repo') == expected_repo, 'Archived repository differs from --repo')
            require(commit.get('workflow_url') == expected_workflow, 'Archived workflow differs from --run-id')
            require(pdk.get('PDK') == 'ihp-sg13cmos5l' and pdk.get('PDK_SOURCE') == 'IHP-Open-PDK',
                    'Unsupported PDK name/source in official submission')
            require(pdk.get('PDK_VERSION') == PDK_VERSION,
                    f'Unreviewed PDK version; require exact supported pin {PDK_VERSION}')
            rtl_hashes = {}
            for name in ('src/project.v', 'src/host_spi.v'):
                archived = read_member(archive, name, 1024 * 1024).replace(b'\r\n', b'\n')
                local = (ROOT / name).read_bytes().replace(b'\r\n', b'\n')
                require(archived == local, f'Current RTL differs from official archive: {name}')
                rtl_hashes[name] = sha256(archived)
            netlist = read_member(archive, 'tt_submission/tt_um_pulse8_proto.v', 64 * 1024 * 1024)

        pdk_root = args.pdk_root.resolve()
        if (pdk_root / 'ihp-sg13cmos5l').is_dir():
            pdk_root /= 'ihp-sg13cmos5l'
        model_bytes, model_evidence = {}, {}
        for name, expected_blob in MODELS.items():
            data = (pdk_root / name).read_bytes()
            require(git_blob(data) == expected_blob,
                    f'PDK model differs from exact pinned Git blob: {name}; check revision and LF line endings')
            model_bytes[Path(name).name] = data
            model_evidence[name] = {'git_blob': expected_blob, 'sha256': sha256(data),
                'source': f'{PDK_REPO}/blob/{PDK_VERSION}/ihp-sg13cmos5l/{name}'}

        work = directory / 'work'
        work.mkdir(parents=True, exist_ok=True)
        (work / 'official_netlist.v').write_bytes(netlist)
        model_paths = []
        for name, data in model_bytes.items():
            target = work / name
            target.write_bytes(data)
            model_paths.append(target)
        example_hashes, vector_hashes = generate_vectors(work)
        runner_bytes = Path(__file__).read_bytes()
        (directory / 'runner-source.py').write_bytes(runner_bytes)
        evidence.update(status='running', archive_sha256=archive_hash,
                        provenance=commit, pdk=pdk, models=model_evidence,
                        netlist_sha256=sha256(netlist), rtl_lf_sha256=rtl_hashes,
                        examples_sha256=example_hashes, vectors_sha256=vector_hashes,
                        assembler_sha256=sha256((ROOT / 'tools/assembler.py').read_bytes()),
                        runner_sha256=sha256(runner_bytes), jobs=args.jobs,
                        benches={bench: {'status': 'pending'} for bench in BENCHES})
        result_path.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
        iverilog = shutil.which(args.iverilog) or args.iverilog
        vvp = shutil.which(args.vvp) or args.vvp
        ivl_dir = Path(iverilog).resolve().parent.parent / 'lib/ivl'
        ivl_args = ['-B', str(ivl_dir)] if ivl_dir.is_dir() else []
        vvp_args = ['-M', '-', '-M', str(ivl_dir)] if ivl_dir.is_dir() else []
        execute([iverilog, *ivl_args, '-V'], directory, 'iverilog-version', args.timeout)
        execute([vvp, *vvp_args, '-V'], directory, 'vvp-version', args.timeout)
        print(f'Validated official commit {args.commit} and PDK {PDK_VERSION}', flush=True)
        # Only the main thread records results, in BENCHES key order. A failure
        # is recorded/printed immediately; already-running benches retain their
        # logs and finish within their individual timeout rather than being lost.
        errors = {}
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {}
            for bench, marker in BENCHES.items():
                print(f'Scheduled {bench} on official hardened netlist (zero-delay)...', flush=True)
                future = pool.submit(run_bench, bench, marker, directory, work,
                                     iverilog, vvp, ivl_args, vvp_args, model_paths, args.timeout)
                futures[future] = bench
            for future in as_completed(futures):
                bench = futures[future]
                try:
                    entry, output = future.result()
                    evidence['benches'][bench] = entry
                    print('\n'.join(output.splitlines()[-3:]), flush=True)
                except Exception as exc:
                    errors[bench] = str(exc)
                    evidence['benches'][bench] = {'status': 'fail', 'error': str(exc)}
                    evidence['status'] = 'fail'
                    print(f'HARDENED BENCH FAILED: {bench}: {exc}', file=sys.stderr, flush=True)
                result_path.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
        if errors:
            raise RuntimeError('; '.join(f'{bench}: {errors[bench]}' for bench in BENCHES if bench in errors))
        evidence['status'] = 'pass'
        evidence['completed_utc'] = datetime.now(timezone.utc).isoformat()
        result_path.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
        print(f'HARDENED FUNCTIONAL TESTS PASSED. Evidence: {result_path}', flush=True)
    except (OSError, ValueError, KeyError, RuntimeError, BadZipFile, subprocess.TimeoutExpired) as exc:
        evidence.update(status='fail', error=str(exc))
        if result_path:
            result_path.write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
        print(f'HARDENED TEST FAILED: {exc}', file=sys.stderr, flush=True)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
