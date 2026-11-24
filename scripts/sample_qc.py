#!/usr/bin/env python3
"""Build one sample-level QC row from the actual fastp/SAMtools/BCFtools outputs."""
import argparse
import csv
import json
import math
from pathlib import Path

HEADERS = {
    'raw_reads': ('Raw reads', '', 'Individual reads, not read pairs; fastp before filtering'),
    'trimmed_reads': ('Trimmed reads', '', 'Individual reads retained by fastp'),
    'retained_pct': ('Retained', '%', '100 × trimmed / raw reads'),
    'q30_before_pct': ('Q30 raw', '%', 'Percentage of bases at Q30 or above before fastp'),
    'q30_after_pct': ('Q30 trimmed', '%', 'Percentage of bases at Q30 or above after fastp'),
    'mapped_pct': ('Mapped', '%', 'SAMtools stats reads mapped / raw total sequences; excludes secondary and supplementary alignments'),
    'coverage_pct': ('Coverage', '%', 'Reference bases covered at least once, from samtools coverage'),
    'mean_depth': ('Mean depth', '×', 'Length-weighted mean depth across reference sequences'),
    'vcf_records': ('VCF records', '', 'BCFtools stats number of records; unfiltered'),
    'snps': ('SNP', '', 'BCFtools stats number of SNPs'),
    'indels': ('Indel', '', 'BCFtools stats number of indels'),
}

def ratio(n, d):
    if not math.isfinite(n) or not math.isfinite(d) or d <= 0 or not 0 <= n <= d:
        raise ValueError(f'invalid ratio: {n}/{d}')
    return round(100*n/d, 6)

def read_stats(path, bcftools=False):
    result = {}
    for line in path.read_text().splitlines():
        fields = line.split('\t')
        if fields[0] != 'SN':
            continue
        if bcftools:
            if len(fields) < 4 or fields[1] != '0':
                continue
            key, value = fields[2:4]
        else:
            if len(fields) < 3:
                continue
            key, value = fields[1:3]
        result[key.rstrip(':').strip()] = value
    return result

def coverage(path):
    total = covered = 0
    depth_sum = 0.0
    with path.open() as fh:
        reader = csv.DictReader(fh, delimiter='\t')
        for row in reader:
            length = int(row['endpos']) - int(row['startpos']) + 1
            bases = int(row['covbases'])
            depth = float(row['meandepth'])
            if length <= 0 or not 0 <= bases <= length or not math.isfinite(depth) or depth < 0:
                raise ValueError(f'Invalid coverage row: {path}')
            total += length; covered += bases; depth_sum += depth*length
    return ratio(covered, total), round(depth_sum/total, 6)

def collect(qc):
    qc = Path(qc)
    suffix = '.fastp_stats.json'
    names = sorted(x.name[:-len(suffix)] for x in qc.glob('*'+suffix))
    if not names:
        raise ValueError('No fastp reports')
    data = {}
    for sid in names:
        before_after = json.loads((qc/(sid+suffix)).read_text())['summary']
        before, after = before_after['before_filtering'], before_after['after_filtering']
        raw, trimmed = int(before['total_reads']), int(after['total_reads'])
        stats = read_stats(qc/(sid+'.stats'))
        variants = read_stats(qc/(sid+'.bcfstats'), True)
        cov, depth = coverage(qc/(sid+'.coverage'))
        data[sid] = dict(raw_reads=raw, trimmed_reads=trimmed,
            retained_pct=ratio(trimmed,raw), q30_before_pct=ratio(float(before['q30_rate']),1),
            q30_after_pct=ratio(float(after['q30_rate']),1),
            mapped_pct=ratio(int(stats['reads mapped']),int(stats['raw total sequences'])),
            coverage_pct=cov, mean_depth=depth,
            vcf_records=int(variants['number of records']), snps=int(variants['number of SNPs']),
            indels=int(variants['number of indels']))
    return data

def write_outputs(data, tsv, json_file):
    with Path(tsv).open('w', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=['sample',*HEADERS], delimiter='\t', lineterminator='\n')
        writer.writeheader()
        for sid, row in data.items():
            writer.writerow(dict(sample=sid, **row))
    headers = {}
    for key,(title,suffix,description) in HEADERS.items():
        h = dict(title=title,description=description, min=0, hidden=False, format='{:,.0f}' if not suffix else '{:,.2f}')
        if suffix: h['suffix'] = suffix
        if suffix == '%': h['max'] = 100
        headers[key] = h
    payload = dict(id='varcall_sample_qc', section_name='Sample QC Summary',
        description='One row per paired-end sample. Mapping is relative to the selected reference only; no clinical QC thresholds are applied.',
        plot_type='table', pconfig=dict(id='varcall_sample_qc_table',title='Sample QC Summary',col1_header='Sample'),
        headers=headers, data=data)
    Path(json_file).write_text(json.dumps(payload,indent=2,ensure_ascii=False,allow_nan=False)+'\n')

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('qc',type=Path)
    p.add_argument('--tsv',required=True,type=Path); p.add_argument('--json',required=True,type=Path)
    args=p.parse_args(); write_outputs(collect(args.qc),args.tsv,args.json)
if __name__=='__main__': main()
