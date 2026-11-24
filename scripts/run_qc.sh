#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
test -s .runtime/qc.config || { echo 'Run bash scripts/prepare_local_qc.sh first' >&2; exit 1; }
mkdir -p .runtime/logs
export APPTAINER_CACHEDIR="$PWD/.runtime/cache"
export APPTAINER_TMPDIR="$PWD/.runtime/tmp"
export NXF_APPTAINER_CACHEDIR="$PWD/.runtime/cache"
RUN_DIR=$(mktemp -d "$PWD/.runtime/logs/run-$(date +%Y%m%d-%H%M%S)-XXXXXX")
echo "Run directory: $RUN_DIR"
nextflow -c .runtime/qc.config run main.nf -profile apptainer -resume \
    -with-trace "$RUN_DIR/trace.txt" \
    -with-report "$RUN_DIR/report.html" \
    -with-timeline "$RUN_DIR/timeline.html" \
    -with-dag "$RUN_DIR/dag.html"
python scripts/verify_qc.py
