#!/usr/bin/env python3
"""Run fork regressions from the same Solidity fixture in Foundry and Lean."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import tempfile

import harness_runtime


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--solc', default=os.environ.get('SOLC', 'solc'))
    parser.add_argument('--forge', default=os.environ.get('FORGE', 'forge'))
    parser.add_argument('--lake', default=os.environ.get('LAKE', 'lake'))
    parser.add_argument('--output-dir', type=Path, help='retain the generated Lean regression input')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    version = subprocess.check_output([args.solc, '--version'], text=True)
    if 'Version: 0.8.35+' not in version:
        parser.error('fork regressions require solc 0.8.35')
    subprocess.run([args.forge, 'test', '--no-dynamic-test-linking', '--root', str(root / 'tests/ci'),
                    '--use', args.solc, '-vv'], cwd=root, check=True, timeout=900)
    generated = subprocess.check_output([
        'python3', str(root / 'scripts/solc_ast_to_lean_source.py'),
        str(root / 'tests/ci/src/ForkFeatures.sol'), '--contract', 'ForkFeatures',
        '--namespace', 'ForkFixtures', '--body-only', '--solc', args.solc,
    ], text=True, cwd=root, timeout=120)
    header = 'import SolidCore.Solidity.Reflective\nsection\nopen SolidCore.Solidity\n'
    checks = (root / 'tests/ci/ForkFeatures.lean').read_text()
    with tempfile.TemporaryDirectory(prefix='solidity-lean-fork.') as work:
        output = args.output_dir or Path(work)
        output.mkdir(parents=True, exist_ok=True)
        source = output.resolve() / 'ForkFeatures.lean'
        source.write_text(header + generated + '\nend\n' + checks)
        subprocess.run(harness_runtime.lean_command(root, args.lake, source), cwd=root,
                       check=True, timeout=900)
    print('fork_features=pass')


if __name__ == '__main__':
    main()
