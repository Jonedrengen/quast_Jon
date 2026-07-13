# QUAST

This repository contains helper scripts and reference material for working with QUAST, a genome assembly quality assessment tool. It is intended to collect local workflow pieces for running QUAST analyses and organizing the resulting assembly evaluation outputs.

all credit goes to the quast devs at: https://github.com/ablab/quast 

## SETUP

only arm64 on mac m3 tested
```bash
conda env create -f env_arm64.yml
conda activate quast_JOSS
git clone https://github.com/ablab/quast
cd quast
./setup.py install
```

verify quast installation.
```bash
quast.py
```

## Wrapper usage

Configure `scripts/config.env` for the machine where the wrapper will run. The local M3 setup uses:

```bash
slurm_array_scripts=/Users/B328695/Desktop/Biotools/quast_Jon/scripts
conda_source=/opt/anaconda3/etc/profile.d/conda.sh
conda_env_name=quast_JOSS
qc_parameters=/Users/B328695/Desktop/Biotools/quast_Jon/scripts/QC_parameters.yml
local_jobs=2
quast_threads=2
```

Run locally on a folder of FASTA assemblies:

```bash
bash scripts/quast_submitter.sh \
  -i tests/inital_test_quast/data \
  -s tests/inital_test_quast/data/sample_list.txt \
  -o tests/output_quast_local \
  -c scripts/config.env \
  -p scripts/QC_parameters.yml \
  -m LOCAL
```

Run with a close reference to include reference-based metrics:

```bash
bash scripts/quast_submitter.sh \
  -i /path/to/assemblies \
  -s /path/to/sample_list.txt \
  -o /path/to/quast_output \
  -c scripts/config.env \
  -p scripts/QC_parameters.yml \
  -m LOCAL \
  -r /path/to/reference.fasta
```

Submit to SLURM:

```bash
bash scripts/quast_submitter.sh \
  -i /path/to/assemblies \
  -s /path/to/sample_list.txt \
  -o /path/to/quast_output \
  -c scripts/config.env \
  -p scripts/QC_parameters.yml \
  -m SLURM
```

The sample list should contain one FASTA filename per line. Supported suffixes are `.fasta`, `.fa`, `.fna`, and their `.gz` variants. If `-s` is omitted, the submitter creates `sample_list.txt` in the output directory from FASTA files found directly inside the input folder.

## Outputs

The wrapper follows the same layout as the Shovill helper scripts:

- `processing_files/<sample_id>/quast_out/` contains the native QUAST output for each assembly.
- `compiled_files/quast_metrics.tsv` contains the numeric metrics used for QC.
- `compiled_files/quast_qc.tsv` contains `PASSED`, `FAILED`, or `NA` flags for each metric plus `overall_status`.
- `logs/system_status_report.txt` records whether each sample produced a QUAST report.
- `logs/failed_assemblies.txt` is written only when missing or failing assemblies are found.

QC thresholds are loaded from `scripts/QC_parameters.yml` by default. Set `qc_parameters` in `scripts/config.env` or pass `-p /path/to/QC_parameters.yml` to use a different threshold file. The default criteria are:

- `Total length`: 4,300,000 to 6,200,000
- `GC (%)`: 49.5 to 51.5
- `# contigs`: at most 300, using QUAST's default 500 bp minimum contig length
- `N50`: at least 50,000
- `# N's per 100 kbp`: expected 0
- `Duplication ratio`: at most 1.05 when a reference is available
- `Genome fraction (%)`: at least 95 when a reference is available

Without `-r`, reference-only metrics are reported as `NA` and do not fail the overall QC result.
