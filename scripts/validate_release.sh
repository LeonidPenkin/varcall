#!/usr/bin/env bash
# Fresh launch and cache-only repeat in an independent launch directory.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
ROOT=$PWD
[[ -s .runtime/qc.config ]] || { echo 'Run prepare_local_qc.sh first' >&2; exit 1; }
sha256sum -c .runtime/containers/SHA256SUMS_QC
python3 -m unittest discover -s tests -p 'test_*.py'
mkdir -p .runtime/validation
TEST=$(mktemp -d "$ROOT/.runtime/validation/release-$(date +%Y%m%d-%H%M%S)-XXXXXX")
export APPTAINER_CACHEDIR="$ROOT/.runtime/cache" APPTAINER_TMPDIR="$ROOT/.runtime/tmp" NXF_APPTAINER_CACHEDIR="$ROOT/.runtime/cache"
# Existing outputs, Nextflow work and shared Sarek cache are not removed or overwritten.
cd "$TEST"
mkdir fresh resume
run() {
    local phase=$1; shift
    nextflow -c "$ROOT/.runtime/qc.config" run "$ROOT/main.nf" -profile apptainer \
      -work-dir "$TEST/work" --reads "$ROOT/data/*_R{1,2}.fastq.gz" --reference "$ROOT/data/MT.fna" \
      -with-trace "$TEST/$phase/trace.txt" -with-report "$TEST/$phase/report.html" \
      -with-timeline "$TEST/$phase/timeline.html" -with-dag "$TEST/$phase/dag.html" "$@" \
      2>&1 | tee "$TEST/$phase/console.log"
    cp .nextflow.log "$TEST/$phase/nextflow.log"
    for f in trace.txt report.html timeline.html dag.html; do test -s "$TEST/$phase/$f"; done
    python3 "$ROOT/scripts/verify_qc.py" --results "$TEST/results"
}
run fresh
python3 "$ROOT/scripts/check_trace.py" fresh/trace.txt COMPLETED
# VCF headers may contain time or absolute paths on separate runs. Here compare exact bytes for resume only.
sha256sum results/varcall/*.vcf results/report/sample_qc.tsv > fresh/checksums.txt
run resume -resume
python3 "$ROOT/scripts/check_trace.py" resume/trace.txt CACHED
sha256sum -c fresh/checksums.txt
printf 'RELEASE_VALIDATION_PASS: %s\n' "$TEST"
