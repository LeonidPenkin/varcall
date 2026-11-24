#!/usr/bin/env python3
import csv
from collections import Counter
from pathlib import Path
import sys
path, status = sys.argv[1:]
with open(path) as fh:
    rows = list(csv.DictReader(fh, delimiter='\t'))
counts = Counter(r['status'] for r in rows)
if len(rows) != 57 or counts != Counter({status: 57}):
    sys.exit(f'TRACE FAIL: {path}: {dict(counts)}; expected 57 {status}')
print(f'TRACE_PASS: {Path(path).name}: 57 {status}')
