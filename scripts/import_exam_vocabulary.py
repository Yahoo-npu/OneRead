#!/usr/bin/env python3
"""Build the bundled membership-only index from pinned public word lists.
Usage: python3 scripts/import_exam_vocabulary.py /path/to/downloaded/sources
Files named kyle-<original filename>, ecdict.csv, ecdict-LICENSE; never executes upstream code.
"""
import csv
import io
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
files = {'CET-4': 'kyle-3 四级-乱序.txt', 'CET-6': 'kyle-4 六级-乱序.txt', '考研': 'kyle-5 考研-乱序.txt', 'IELTS': 'ecdict.csv', 'TOEFL': 'kyle-6 托福-乱序.txt'}
words, hashes = {}, {}
for exam, filename in files.items():
    raw = (source / filename).read_bytes()
    hashes[filename] = hashlib.sha256(raw).hexdigest()
    lines = raw.decode('utf-8-sig').splitlines()
    entries = [row['word'] for row in csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))) if 'ielts' in row['tag'].split()] if exam == 'IELTS' else [line.split('\t')[0] for line in lines if '\t' in line]
    normalized = {' '.join(w.strip().lower().replace('’', "'").replace('–', '-').split()) for w in entries}
    words[exam] = sorted(w for w in normalized if re.fullmatch(r"[a-z]+(?:[ '\-][a-z]+)*", w))
    assert len(words[exam]) > 500, (exam, 'unexpectedly small source')
    print(exam, len(words[exam]))
version = '2026-10-21.2'
(root / 'Sources/OneRead/ExamVocabulary.json').write_text(json.dumps({'version': version, 'words': words}, ensure_ascii=False, separators=(',', ':')) + '\n')
notices = root / 'Sources/OneRead/ExamWordListNotices'
for name in ['kyle', 'ecdict']:
    (notices / (name + '-LICENSE.txt')).write_bytes((source / (name + '-LICENSE')).read_bytes())
metadata = {'version': version, 'repositories': {'KyleBing/english-vocabulary': 'c4c6c80879ff17d7025c28fb853a4991c8e6be6a', 'skywind3000/ECDICT': 'bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b'}, 'sha256': hashes, 'counts': {key: len(value) for key, value in words.items()}}
(notices / 'manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
