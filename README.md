# Marker alignments in Nextflow

## Introduction
CORRAL is a Nextflow pipeline wrapping a Python module, `marker_alignments`, and combining it with fetch and align steps, to provide a workflow for estimating what taxa are present in the sample.

Our article about CORRAL, "Improved eukaryotic detection compatible with large-scale automated analysis of metagenomes", has now been published in Microbiome: https://doi.org/10.1186/s40168-023-01505-1.

## Installation
This workflow is not containerised, but the dependencies are quite minimal:
- `bowtie2`
- [Marker alignments package](https://github.com/wbazant/marker_alignments) and its tool `marker_alignments`.

Additionally, `samtools stats` is the default and recommended for alignment stats.

By default, `bowtie2`, `marker_alignments` and `samtools` are assumed to be on `$PATH` but you can provide a path to an executable in the pipeline config.


If you want to use `--downloadMethod wget` you also need `wget`. If you want to use `--downloadMethod sra` you need the SRA EUtils, with `prefetch` and `fastq-dump` on `$PATH`.

`--unpackMethod bz2` requires `bzip2` on `$PATH`.

You also need a `bowtie2` reference database of taxonomic markers, like ChocoPhlAn or EukDetect.

### Docker support
This version of the pipeline accompanies the [original CORRAL paper](https://doi.org/10.1101/2022.03.09.483664), contains all code needed to reproduce the results, and will remain supported by the authors. MicrobiomeDB data production since June 2022 is operated by the whole VEuPathDB group which undertook further development of CORRAL under a fork, which is also freely available [here](https://github.com/VEuPathDB/CORRAL/) under the same license.

See [their Dockerfile](https://github.com/VEuPathDB/CORRAL/blob/main/Dockerfile) and [their nextflow.config](https://github.com/VEuPathDB/CORRAL/blob/main/nextflow.config) for how they modified this Nextflow pipeline to enable Docker support.


## Usage

### Summary of input params
Main parameters:

| param         | value type        | description  |
| ------------- | ------------- | ------------ |
| inputPath  | path to file | TSV: sample ID,fastq URL or run ID, [second URL for paired reads] |
| downloadMethod | "wget" / "sra" / "local" | |
| libraryLayout | "single" / "paired" | |
| resultDir  | path to dir  | publish directory |
| refdb | path pattern | bowtie2 -x parameter |
| bowtie2Command | shell | Run bowtie2 |
| alignmentStatsCommand | shell | `samtools stats` by default. Set to 'none' to switch off |
| summarizeAlignmentsCommand | shell | path to `marker_alignments` optionally with filter arguments to use|

Optional parameters:

| param         | value type        | description  |
| ------------- | ------------- | ------------ |
| markerToTaxonPath | path to file | summarize_marker_alignments --refdb-marker-to-taxon-path parameter |
| unpackMethod | "bz2" | for FTP .tar.bz2 content |
| summaryColumn | "cpm","taxon_num_reads","taxon_num_alignments","taxon_num_markers" | Column to report in final matrix (default: cpm) |

### How to use this software
This is research software. You can use it as is to check you are getting the results similar to the ones we did, and you can also build upon it.

The Python module [`marker_alignments`](https://github.com/wbazant/marker_alignments) forms the core of the method, but it is written to accept alignments as input. To complement the module, this Nextflow pipeline helps you orchestrate the process of downloading fastqs and running the alignments, so you can do eukaryotic detection at scale. If you want to do the alignments yourself or orchestrate them differently, you can just use the module.

#### Reference databases
You will need to provide `--refdb` and `--markerToTaxonPath` so that they correspond to your chosen reference. For the publication, we used EukDetect's databases: see [their documentation](https://github.com/allind/EukDetect) for how to download them.

#### Execution environment
If you want to process many samples in parallel, add a configuration file, like the `resource_configuration.conf` file shown below. You might need to adjust the Nextflow commands to make them suitable for your execution environment. We tested this pipeline locally on a Ubuntu laptop, and on our LSF cluster.

#### Experimenting with the method
If you want to experiment with the method - for example, see what happens if you do not filter at all - you can override the default `summarizeAlignmentsCommand` parameter and provide a different `--resultDir`. Nextflow is able to reuse previously done steps, so changing `summarizeAlignmentsCommand` will not re-run the download or alignment steps. Here is an [example](https://github.com/wbazant/markerAlignmentsPaper/blob/master/scripts/run_our_method_on_unknown_euks.sh).

### Example config

#### `run.sh`
```
# assuming reference of markers is provided here
REF_PATH="~/eukaryotic_markers_db"

# A list of samples and where to get them from - see example below
INPUT_TSV="./in.tsv"

# Cluster or local configuration - see example below
RESOURCE_CONF="./resource_configuration.conf"

# Pull the code
nextflow pull wbazant/CORRAL -r main

# Run the pipeline
nextflow run wbazant/CORRAL -r main \
  --inputPath $INPUT_TSV  \
  --resultDir ./results \
  --downloadMethod wget \
  --unpackMethod bz2 \
  --libraryLayout paired \
  --refdb ${REF_PATH}/ncbi_eukprot_met_arch_markers.fna \
  --markerToTaxonPath ${REF_PATH}/busco_taxid_link.txt  \
  -c ./$RESOURCE_CONF \
  -with-trace -resume

```

#### `resource_configuration.conf`

For LSF processing this could be a good config:
```  
process {
  executor = 'lsf'
  maxForks = 60
  
  withLabel: 'download' {
    maxForks = 5
    maxRetries = 3
  }
  withLabel: 'align' {
    errorStrategy = 'finish'
  }
}
```

For processing using local resources, like a laptop, three is a good number of forks (parallel jobs), and you don't need the other stuff, so you can just have a simple config:
```  
process {
  maxForks = 3
}
```


#### `in.tsv`
```
SRS011061       https://downloads.hmpdacc.org/dacc/hhs/genome/microbiome/wgs/analysis/hmwgsqc/v1/SRS011061.tar.bz2
SRS011086       https://downloads.hmpdacc.org/dacc/hhs/genome/microbiome/wgs/analysis/hmwgsqc/v1/SRS011086.tar.bz2
```
This is the correct format of an input file corresponding to arguments `--downloadMethod wget --unpackMethod bz2`. The first column is sample ID, and the second column is a URL.

If you want a paired library layout (the `--libraryLayout paired` option), specify three columns: sampleId, pathForward, pathReverse. [example - paired layout](https://github.com/wbazant/CORRAL/blob/main/data/pairedWget.tsv).

If you want local files (the `--downloadMethod local` option) specify a file path instead of a URL.

