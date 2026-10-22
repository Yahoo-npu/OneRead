#!/usr/bin/env python3
"""Check the current Git upload set without printing possible secret values."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root, check=True, stdout=subprocess.PIPE)
paths = sorted(set(p for p in result.stdout.decode().split('\0') if p))
problems = []
patterns = [
    re.compile(r'\bghp_[A-Za-z0-9]{30,}'),
    re.compile(r'\bgithub_pat_[A-Za-z0-9_]{40,}'),
    re.compile(r'\bsk-[A-Za-z0-9_-]{32,}'),
    re.compile(r'\bAIza[0-9A-Za-z_-]{30,}'),
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    re.compile(r'''(?i)(?:api[_ -]?key|token|password|secret)\s*[:=]\s*["']([A-Za-z0-9_-]{32,})["']''')
]
required = ['README.md', 'VERSION', 'CHANGELOG.md', '.gitignore', 'Package.swift',
            'docs/USER_GUIDE.md', 'docs/GITHUB_PUBLISHING.md', 'docs/THIRD_PARTY.md',
            'Sources/OneRead/ExamWordListNotices/kyle-LICENSE.txt',
            'Sources/OneRead/ExamWordListNotices/ecdict-LICENSE.txt']
for relative in required:
    if relative not in paths:
        problems.append(f'Required file missing from Git upload set: {relative}')
for relative in paths:
    path = root / relative
    if not path.is_file():
        continue
    if path.is_symlink():
        problems.append(f'Review symlink before upload: {relative}')
        continue
    if relative.split('/')[0] in {'.build', 'dist', '.local', 'design', 'Data', 'Assets', 'FolderCovers'}:
        problems.append(f'Local-only file is staged or not ignored: {relative}')
    if path.name == 'library.json' or path.suffix in {'.p12', '.pfx', '.pem', '.key', '.keychain-db'}:
        problems.append(f'Private data or signing material: {relative}')
    if path.suffix.lower() in {'.epub', '.pdf'} and not relative.startswith('Samples/'):
        problems.append(f'Non-sample reading material: {relative}')
    if path.stat().st_size > 50 * 1024 * 1024:
        problems.append(f'Large source file: {relative}')
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeError:
        continue
    for number, line in enumerate(text.splitlines(), 1):
        if '/Users/' in line and relative != 'scripts/check-repository.py':
            problems.append(f'Personal absolute path: {relative}:{number}')
        if any(pattern.search(line) for pattern in patterns):
            problems.append(f'Potential credential (value hidden): {relative}:{number}')
if problems:
    print('\n'.join(problems), file=sys.stderr)
    sys.exit(1)
print(f'Checked {len(paths)} repository files: no local data, signing keys or credential patterns found.')
print('Pattern checks are not a guarantee; review git diff --cached before publishing.')
