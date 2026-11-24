import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from sample_qc import collect, write_outputs, ratio

class TestSummary(unittest.TestCase):
    def test_sample(self):
        with tempfile.TemporaryDirectory() as tmp:
            d=Path(tmp)
            (d/'sample1.fastp_stats.json').write_text(json.dumps({'summary':{'before_filtering':{'total_reads':100,'q30_rate':0.9},'after_filtering':{'total_reads':98,'q30_rate':0.95}}}))
            (d/'sample1.stats').write_text('SN\traw total sequences:\t98\nSN\treads mapped:\t49\n')
            (d/'sample1.bcfstats').write_text('SN\t0\tnumber of records:\t5\nSN\t0\tnumber of SNPs:\t4\nSN\t0\tnumber of indels:\t1\n')
            (d/'sample1.coverage').write_text('#rname\tstartpos\tendpos\tnumreads\tcovbases\tcoverage\tmeandepth\tmeanbaseq\tmeanmapq\nMT\t1\t100\t49\t80\t80\t20\t39\t60\n')
            data=collect(d); row=data['sample1']
            self.assertEqual(row['mapped_pct'],50); self.assertEqual(row['coverage_pct'],80)
            self.assertEqual(row['q30_after_pct'],95); self.assertEqual(row['retained_pct'],98)
            self.assertEqual(row['vcf_records'],5); self.assertEqual(row['mean_depth'],20)
            write_outputs(data,d/'summary.tsv',d/'summary_mqc.json')
            self.assertEqual(json.loads((d/'summary_mqc.json').read_text())['data'],data)
            with (d/'summary.tsv').open() as fh:
                self.assertEqual(len(list(csv.DictReader(fh,delimiter='\t'))),1)
            (d/'sample1.coverage').unlink()
            with self.assertRaises(FileNotFoundError): collect(d)
    def test_invalid(self):
        for n,d in [(1,0),(2,1),(-1,1),(float('nan'),1)]:
            with self.assertRaises(ValueError): ratio(n,d)
if __name__=='__main__': unittest.main()
