#!/usr/bin/env bash
# Reuse local SIFs, or obtain missing images from public registries.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
ROOT=$PWD
mkdir -p .runtime/{containers,cache,tmp,logs}
export APPTAINER_CACHEDIR="$ROOT/.runtime/cache"
export APPTAINER_TMPDIR="$ROOT/.runtime/tmp"
export NXF_APPTAINER_CACHEDIR="$ROOT/.runtime/cache"
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"
if [[ -f .runtime/containers/SHA256SUMS_QC ]]; then
    sha256sum -c .runtime/containers/SHA256SUMS_QC
fi
pull() {
    local target=".runtime/containers/$1.sif" uri=$2
    if [[ ! -s "$target" ]]; then
        apptainer pull "$target" "$uri"
    fi
}
pull bwa_samtools docker://glebusasha/bwa_samtools:latest
pull fastp docker://nanozoo/fastp:0.23.1--9f2e255
pull bcftools docker://staphb/bcftools:1.25
pull multiqc docker://staphb/multiqc:1.35
pull fastqc https://depot.galaxyproject.org/singularity/fastqc-0.12.1--hdfd78af_0
pull samtools_1.20 docker://quay.io/biocontainers/samtools:1.20--h50ea8bc_0
check() {
    local name=$1 expected=$2 output
    shift 2
    output=$(apptainer exec ".runtime/containers/$name.sif" "$@" 2>&1) || { printf '%s\n' "$output" >&2; return 1; }
    grep -Fqx "$expected" <<< "$output" || { printf 'VERSION FAIL: %s\n%s\n' "$expected" "$output" >&2; return 1; }
    printf 'VERSION OK: %s\n' "$expected"
}
bwa_output=$(apptainer exec .runtime/containers/bwa_samtools.sif bwa 2>&1 || true)
grep -Fqx 'Version: 0.7.17-r1188' <<< "$bwa_output"
check bwa_samtools 'samtools 1.13' samtools --version
check fastp 'fastp 0.23.1' fastp --version
check bcftools 'bcftools 1.25' bcftools --version
check multiqc 'multiqc, version 1.35' multiqc --version
check fastqc 'FastQC v0.12.1' fastqc --version
check samtools_1.20 'samtools 1.20' samtools --version
apptainer exec .runtime/containers/multiqc.sif python3 --version
cat > .runtime/qc.config <<CONFIG
apptainer {
    enabled = true
    autoMounts = true
    cacheDir = '$ROOT/.runtime/cache'
}
process {
    withName: 'qcontrol' { container = 'file://$ROOT/.runtime/containers/fastp.sif' }
    withName: 'refindex|faindex|align|bamindex|flagstat' { container = 'file://$ROOT/.runtime/containers/bwa_samtools.sif' }
    withName: 'varcall|bcfstats' { container = 'file://$ROOT/.runtime/containers/bcftools.sif' }
    withName: 'report' { container = 'file://$ROOT/.runtime/containers/multiqc.sif' }
    withName: 'FASTQC_RAW|FASTQC_TRIMMED' { container = 'file://$ROOT/.runtime/containers/fastqc.sif' }
    withName: 'samtools_stats' { container = 'file://$ROOT/.runtime/containers/samtools_1.20.sif' }
}
CONFIG
sha256sum .runtime/containers/*.sif > .runtime/containers/SHA256SUMS_QC
# Publish only hashes and basenames, never local paths or binary images.
(cd .runtime/containers && sha256sum bwa_samtools.sif fastp.sif bcftools.sif multiqc.sif fastqc.sif samtools_1.20.sif) > containers.sha256
printf '\nLOCAL_QC_READY: %s/.runtime/qc.config\n' "$ROOT"
