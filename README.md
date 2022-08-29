# Marker alignments in Nextflow

## Introduction
CORRAL is a Nextflow pipeline wrapping a Python module, `marker_alignments`, and combining it with fetch and align steps, to provide a workflow for estimating what taxa are present in the sample.


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
| alignmentStatsCommand | shell | `samtools stats` or other |
| summarizeAlignmentsCommand | shell | path to `marker_alignments` optionally with filter arguments to use|

Optional parameters:

| param         | value type        | description  |
| ------------- | ------------- | ------------ |
| marker_to_taxon_path | path to file | summarize_marker_alignments --marker_to_taxon_path parameter |
| unpackMethod | "bz2" | for FTP .tar.bz2 content |

### How to use this software
This is research software. You can use it as is to check you are getting the results similar to the ones we did, and you can also build upon it.

The Python module [`marker_alignments`](https://github.com/wbazant/marker_alignments) does almost all the tricks, but it requires alignments as input. Meanwhile, this pipeline helps you orchestrate the process of downloading fastqs and running the alignments, so you can do eukaryotic detection at scale.

#### Reference databases
You will need to provide `--refdb` and `--refdb-marker-to-taxon-path` so that they correspond to your chosen reference. For the publication, we used EukDetect's databases: see [their documentation](https://github.com/allind/EukDetect) for how to download them.

#### Execution environment
We ran this pipeline locally on a Ubuntu laptop, and on our LSF cluster, adding a `cluster.conf` file that made sense for our run. You might need to adjust the Nextflow commands to make them suitable for your execution environment. 

#### Experimenting with the method
If you want to experiment with the method - for example, see what happens if you do not filter at all - you can override the default `summarizeAlignmentsCommand` parameter and provide a different `--resultDir`. Nextflow is able to reuse previously done steps, so changing `summarizeAlignmentsCommand` will not re-run the download or alignment steps. Here is an [example](https://github.com/wbazant/markerAlignmentsPaper/blob/master/scripts/run_our_method_on_unknown_euks.sh).

### Example - cluster run

#### `run.sh`
```
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REF_PATH="~/eukprot"

nextflow pull wbazant/CORRAL -r main

nextflow run wbazant/CORRAL -r main \
  --inputPath $DIR/in.tsv  \
  --resultDir $DIR/results \
  --downloadMethod wget \
  --unpackMethod bz2 \
  --libraryLayout paired \
  --refdb ${REF_PATH}/ncbi_eukprot_met_arch_markers.fna \
  --marker_to_taxon_path ${REF_PATH}/busco_taxid_link.txt  \
  -c $DIR/cluster.conf \
  -with-trace -resume | tee $DIR/tee.out

```

#### `cluster.conf`

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
If you want to run the pipeline locally, remove `executor = 'lsf'`, and reduce the number of forks. Raising it above what you can download in parallel, or to the number of cores of your CPU, will not speed things up, so for example `maxForks = 3` will be a good value. Monitor the temperature of your machine and make sure it does not overheat: `bowtie2` uses the CPU really intensely.

#### `in.tsv`
```
SRS011061       https://downloads.hmpdacc.org/dacc/hhs/genome/microbiome/wgs/analysis/hmwgsqc/v1/SRS011061.tar.bz2
SRS011086       https://downloads.hmpdacc.org/dacc/hhs/genome/microbiome/wgs/analysis/hmwgsqc/v1/SRS011086.tar.bz2
```
This is the correct content for `--downloadMethod wget --unpackMethod bz2`. For other input combinations, check the pipeline code - it's usually two or three columns. The first one is an sample ID, the second one is path or URL, and for the `libraryLayout paired` and no `--unpackMethod` it's pathForward then pathReverse.


