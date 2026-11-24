process bcfstats {
    conda 'bioconda::bcftools'
    container 'staphb/bcftools:1.25'
    publishDir 'results/bcfstats'
    tag "$sid"

    input:
    tuple val(sid), path(vcf)
    output:
    tuple val(sid), path("${sid}.bcfstats")
    script:
    """
    bcftools stats $vcf > ${sid}.bcfstats
    """

}