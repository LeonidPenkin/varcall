process samtools_stats {
    container 'quay.io/biocontainers/samtools:1.20--h50ea8bc_0'
    conda 'bioconda::samtools=1.20'
    tag "$sid"
    cpus 2
    memory '1 GB'
    publishDir 'results/samtools_stats', mode: 'copy', overwrite: true

    input:
    tuple val(sid), path(bamFile), path(bamIndex)

    output:
    path "${sid}.stats", emit: stats
    path "${sid}.coverage", emit: coverage
    path "${sid}.idxstats", emit: idxstats

    script:
    """
    samtools quickcheck -v "${bamFile}"
    samtools stats -@ ${task.cpus - 1} "${bamFile}" > "${sid}.stats"
    samtools coverage "${bamFile}" > "${sid}.coverage"
    samtools idxstats "${bamFile}" > "${sid}.idxstats"
    """
}
