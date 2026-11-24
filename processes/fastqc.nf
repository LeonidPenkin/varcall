process fastqc {
    container 'https://depot.galaxyproject.org/singularity/fastqc-0.12.1--hdfd78af_0'
    conda 'bioconda::fastqc=0.12.1'
    tag "$sid:$stage"
    cpus 2
    memory '1 GB'
    publishDir "results/fastqc/${stage}", mode: 'copy', overwrite: true

    input:
    tuple val(sid), path(reads, stageAs: 'reads/*')
    val stage

    output:
    path "${stage}_*_fastqc.zip", arity: '2', emit: zip
    path "${stage}_*_fastqc.html", arity: '2', emit: html

    script:
    """
    fastqc --threads ${task.cpus} --noextract --outdir . "${reads[0]}" "${reads[1]}"
    for f in *_fastqc.zip *_fastqc.html; do
        mv -- "\$f" "${stage}_\$f"
    done
    """
}
