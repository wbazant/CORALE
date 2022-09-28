nextflow.enable.dsl=2

process downloadSingleWget {
  label 'download'
  input:
  tuple val(sample), val(fastqUrl)

  output:
  tuple val(sample), file("${sample}.fastq.gz")

  script:
  """
  ${params.wgetCommand} $fastqUrl -O ${sample}.fastq.gz
  """
}

process downloadPairedWget {
  label 'download'
  input:
  tuple val(sample), val(fastqUrlR1), val(fastqUrlR2)

  output:
  tuple val(sample), file("${sample}_R1.fastq.gz"), file("${sample}_R2.fastq.gz")

  script:
  """
  ${params.wgetCommand} $fastqUrlR1 -O ${sample}_R1.fastq.gz
  ${params.wgetCommand} $fastqUrlR2 -O ${sample}_R2.fastq.gz
  """
}

process downloadPairedWgetUnpackBz2 {
  label 'download'
  input:
  tuple val(sample), val(url)

  output:
  tuple val(sample), file("${sample}_R1.fastq"), file("${sample}_R2.fastq")

  script:
  """
  ${params.wgetCommand} $url -O ${sample}.tar.bz2
  tar -xvjf ${sample}.tar.bz2 --transform 's!^[^/]\\+\\(\$\\|/\\)!tar_out\\1!'
  fastq_R1=\$(find tar_out -name '*1.fastq')
  fastq_R2=\$(find tar_out -name '*2.fastq')
  mv -v "\$fastq_R1" "${sample}_R1.fastq"
  mv -v "\$fastq_R2" "${sample}_R2.fastq"
  """
}


process downloadSingleSra {

  label 'download'

  input:
  tuple val(sample), val(runAccession)

  output:
  tuple val(sample), file("${sample}.fastq")

  script:
  """
  getFastqFromSraSingle $runAccession ${sample}.fastq
  """
}

process downloadPairedSra {

  label 'download'

  input:
  tuple val(sample), val(runAccession)

  output:
  tuple val(sample), file("${sample}_R1.fastq"), file("${sample}_R2.fastq")

  script:
  """
  getFastqFromSraPaired $runAccession ${sample}_R1.fastq ${sample}_R2.fastq
  """
}

process bowtie2Single {
  label 'align'
  input:
  tuple val(sample), path(readsFastq)

  output:
  tuple val(sample), path("numReads.txt"), path("alignmentsSingle.sam")

  script:
  """
  grep -c '^@' ${readsFastq} > numReads.txt

  ${params.bowtie2Command} \
    -x ${params.refdb} \
    -U ${readsFastq} \
    -S alignmentsSingle.sam 
  """

}
process bowtie2Paired {
  label 'align'
  input:
  tuple val(sample), path(readsFastqR1), path(readsFastqR2)

  output:
  tuple val(sample), path("numReads.txt"), path("alignmentsPaired.sam")

  script:
  """
  grep -c '^@' ${readsFastqR1} > numReads.txt

  ${params.bowtie2Command} \
    -x ${params.refdb} \
    -1 ${readsFastqR1} \
    -2 ${readsFastqR2} \
    -S alignmentsPaired.sam
  """
}
process alignmentStats {
  publishDir "${params.resultDir}/alignmentStats"
  label 'stats'

  input:
  tuple val(sample), path(numReadsPath), path(alignmentsSam)

  output:
  tuple val(sample), path("${sample}.alignmentStats.txt")

  script:
  """
  ${params.alignmentStatsCommand} ${alignmentsSam} > ${sample}.alignmentStats.txt
  """
}

process summarizeAlignments{
  publishDir "${params.resultDir}/summarizedAlignments"
  label 'postAlign'

  input:
  tuple val(sample), path(numReadsPath), path(alignmentsSam)

  output:
  path("${sample}.taxa.tsv")

  script:
  """
  ${params.summarizeAlignmentsCommand} \
    --input ${alignmentsSam} \
    --refdb-marker-to-taxon-path ${params.markerToTaxonPath} \
    --refdb-format eukprot \
    --output-type taxon_all \
    --num-reads \$(cat ${numReadsPath}) \
    --output ${sample}.taxa.tsv 
  """
}

process makeTsv {
  publishDir params.resultDir, mode: 'move', overwrite: true  
  label 'postAlign'

  input:
  file("*.taxa.tsv")

  output:
  file("${params.summaryColumn}.${params.summaryFormat}.tsv")

  script:
  """
  makeTsv.pl . .taxa.tsv ${params.summaryColumn} ${params.summaryFormat} > ${params.summaryColumn}.${params.summaryFormat}.tsv
  """
}

def postAlign(sample_numReadsPath_alignmentsSam) {
  if(params.alignmentStatsCommand != 'none'){
    alignmentStats(sample_numReadsPath_alignmentsSam)
  }
  return summarizeAlignments(sample_numReadsPath_alignmentsSam)
}

def singleWget(input) {
  sample_reads = downloadSingleWget(input)
  sample_numReads_alignments = bowtie2Single(sample_reads)
  return postAlign(sample_numReads_alignments)
}

def pairedWget(input) {
  sample_reads = downloadPairedWget(input)
  sample_numReads_alignments = bowtie2Paired(sample_reads)
  return postAlign(sample_numReads_alignments)
}

def pairedWgetUnpackBz2(input) {
  sample_reads = downloadPairedWgetUnpackBz2(input)
  sample_numReads_alignments = bowtie2Paired(sample_reads)
  return postAlign(sample_numReads_alignments)
}

def singleSra(input) {
  sample_reads = downloadSingleSra(input)
  sample_numReads_alignments = bowtie2Single(sample_reads)
  return postAlign(sample_numReads_alignments)
}

def pairedSra(input) {
  sample_reads = downloadPairedSra(input)
  sample_numReads_alignments = bowtie2Paired(sample_reads)
  return postAlign(sample_numReads_alignments)
}

def singleLocal(input) {
  sample_numReads_alignments = bowtie2Single(input)
  return postAlign(sample_numReads_alignments)
}

def pairedLocal(input) {
  sample_numReads_alignments = bowtie2Paired(input)
  return postAlign(sample_numReads_alignments)
}

workflow {
  input = Channel.fromPath(params.inputPath).splitCsv(sep: "\t")
  if (params.downloadMethod == 'sra') {
    input = input.map{it.size() == 1 ? [it[0], it[0]] : it}
  }

  if(params.downloadMethod == 'wget' && params.libraryLayout == 'single'){
    xs = singleWget(input)
  } else if(params.downloadMethod == 'wget' && params.libraryLayout == 'paired'){
    if(params.unpackMethod == 'bz2'){
      xs = pairedWgetUnpackBz2(input)
    } else {
      xs = pairedWget(input)
    }
  } else if(params.downloadMethod == 'sra' && params.libraryLayout == 'single'){
    xs = singleSra(input)
  } else if(params.downloadMethod == 'sra' && params.libraryLayout == 'paired'){
    xs = pairedSra(input)
  } else if(params.downloadMethod == 'local' && params.libraryLayout == 'single'){
    xs = singleLocal(input)
  } else if(params.downloadMethod == 'local' && params.libraryLayout == 'paired'){
    xs = pairedLocal(input)
  }

  makeTsv(xs.collect())
}
