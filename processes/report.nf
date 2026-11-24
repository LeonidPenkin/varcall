process report {
    conda 'bioconda::multiqc=1.35'
    container 'staphb/multiqc:1.35'
    publishDir 'results/report', mode: 'copy', overwrite: true

    input:
    path files, stageAs: 'qc/*'
    path config
    path summary_script

    output:
    path 'multiqc_report.html'
    path 'multiqc_data'
    path 'sample_qc.tsv'
    path 'sample_qc_mqc.json'

    script:
    """
    python3 "${summary_script}" qc --tsv sample_qc.tsv --json qc/sample_qc_mqc.json
    multiqc qc --config "${config}" --force \
        --filename multiqc_report.html \
        -m custom_content -m fastqc -m fastp -m samtools -m bcftools
    if [ ! -d multiqc_data ] && [ -d multiqc_report_data ]; then
        mv multiqc_report_data multiqc_data
    fi
    cp qc/sample_qc_mqc.json sample_qc_mqc.json
    test -s multiqc_report.html
    test -d multiqc_data
    """
}
