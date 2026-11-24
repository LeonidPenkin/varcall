#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

params.reads     = 'data/*_R{1,2}.fastq.gz'
params.reference = 'data/MT.fna'

include { qcontrol } from './processes/qcontrol'
include { refindex } from './processes/refindex'
include { align }    from './processes/align'
include { faindex }  from './processes/faindex'
include { bamindex } from './processes/bamindex'
include { flagstat } from './processes/flagstat'
include { varcall }  from './processes/varcall'
include { bcfstats } from './processes/bcfstats'
include { report }   from './processes/report'
include { fastqc as FASTQC_RAW; fastqc as FASTQC_TRIMMED } from './processes/fastqc'
include { samtools_stats } from './processes/samtools_stats'

workflow {
    reads_ch = Channel.fromFilePairs(params.reads, checkIfExists: true)
    ref_ch = Channel.value(file(params.reference, checkIfExists: true))

    FASTQC_RAW(reads_ch, 'raw')
    qcontrol(reads_ch)
    trimmed_ch = qcontrol.out[0].map { sid, r1, r2 -> tuple(sid, [r1, r2]) }
    FASTQC_TRIMMED(trimmed_ch, 'trimmed')
    refindex(ref_ch)
    faindex(ref_ch)

    align(ref_ch, qcontrol.out[0], refindex.out)
    bamindex(align.out)
    flagstat(align.out)

    bam_bai_ch = align.out.join(bamindex.out, failOnMismatch: true, failOnDuplicate: true)
    samtools_stats(bam_bai_ch)
    varcall(ref_ch, bam_bai_ch, faindex.out)
    bcfstats(varcall.out)

    qc_files_ch = qcontrol.out.json
        .mix(flagstat.out.map { sid, stats -> stats })
        .mix(bcfstats.out.map { sid, stats -> stats })
        .mix(FASTQC_RAW.out.zip.flatten())
        .mix(FASTQC_TRIMMED.out.zip.flatten())
        .mix(samtools_stats.out.stats)
        .mix(samtools_stats.out.coverage)
        .mix(samtools_stats.out.idxstats)
        .collect()

    report(qc_files_ch,
        Channel.value(file("${projectDir}/multiqc_config.yaml", checkIfExists: true)),
        Channel.value(file("${projectDir}/scripts/sample_qc.py", checkIfExists: true)))
}
