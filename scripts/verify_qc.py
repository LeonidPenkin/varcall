#!/usr/bin/env python3
"""Check the six training pairs and the sources actually parsed by MultiQC."""
from pathlib import Path
import argparse
import csv
import json
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--results', type=Path, default=ROOT / 'results')
args = parser.parse_args()
results = args.results.resolve()
samples = sorted(p.name.removesuffix('_R1.fastq.gz') for p in (ROOT / 'data').glob('*_R1.fastq.gz'))
errors = []
if not samples:
    errors.append('No training samples found')
expected = []

def require(path):
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f'Missing or empty: {path}')
        return False
    return True

for sid in samples:
    require(ROOT / 'data' / f'{sid}_R2.fastq.gz')
    for stage in ('raw', 'trimmed'):
        for mate in ('R1', 'R2'):
            name = f'{stage}_{sid}_{mate}_fastqc.zip'
            p = results / 'fastqc' / stage / name
            expected.append(name)
            if require(p):
                try:
                    with zipfile.ZipFile(p) as z:
                        entry = next(n for n in z.namelist() if n.endswith('/fastqc_data.txt'))
                        data = z.read(entry).decode()
                        if not re.search(r'^Filename\t' + re.escape(sid + '_' + mate) + r'\.(?:fq|fastq)(?:\.gz)?\s*$', data, re.M):
                            errors.append(f'Unexpected FastQC Filename: {name}')
                except (OSError, ValueError, StopIteration, zipfile.BadZipFile) as exc:
                    errors.append(f'Invalid FastQC zip {name}: {exc}')
    for folder, suffix in (('qcontrol','.fastp_stats.json'), ('flagstat','.flagstat'), ('bcfstats','.bcfstats'), ('samtools_stats','.stats'), ('samtools_stats','.coverage'), ('samtools_stats','.idxstats')):
        name = sid + suffix
        expected.append(name)
        require(results / folder / name)
    require(results / 'varcall' / f'{sid}.vcf')

html = results / 'report' / 'multiqc_report.html'
sources = results / 'report' / 'multiqc_data' / 'multiqc_sources.txt'
if require(html):
    content = html.read_text(encoding='utf-8', errors='replace')
    for section in ('fastqc_raw', 'fastqc_trimmed', 'varcall_sample_qc_table'):
        if section not in content:
            errors.append(f'Missing report section: {section}')
if require(sources):
    text = sources.read_text(encoding='utf-8', errors='replace')
    for name in expected:
        if not re.search(r'(?<![A-Za-z0-9_.-])' + re.escape(name) + r'(?![A-Za-z0-9_.-])', text):
            errors.append(f'Not found in MultiQC sources: {name}')
summary = results / 'report' / 'sample_qc.tsv'
custom = results / 'report' / 'sample_qc_mqc.json'
if require(summary) and require(custom):
    with summary.open() as fh:
        rows = list(csv.DictReader(fh, delimiter='\t'))
    if sorted(row['sample'] for row in rows) != samples:
        errors.append('Summary sample IDs differ from FASTQ sample IDs')
    if sorted(json.loads(custom.read_text())['data']) != samples:
        errors.append('Custom JSON sample IDs differ from FASTQ sample IDs')
    # Recalculate from the source logs, not from the summary itself.
    from sample_qc import collect
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        for sid in samples:
            for folder, suffix in (('qcontrol','.fastp_stats.json'), ('samtools_stats','.stats'), ('samtools_stats','.coverage'), ('bcfstats','.bcfstats')):
                source = results / folder / (sid+suffix)
                if source.is_file(): (d / source.name).symlink_to(source)
        try:
            expected_summary = collect(d)
            for row in rows:
                for key,value in expected_summary[row['sample']].items():
                    if abs(float(row[key])-value) > 1e-6:
                        errors.append(f'Summary mismatch: {row["sample"]} {key}')
        except (ValueError, KeyError, OSError, ZeroDivisionError) as exc:
            errors.append(f'Summary source validation failed: {exc}')
if errors:
    print('\n'.join('FAIL: ' + e for e in errors), file=sys.stderr)
    sys.exit(1)
print(f'QC_PASS: {len(samples)} samples, {len(expected)} expected QC input files found and listed in MultiQC sources.')
