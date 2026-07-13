#!/bin/bash
set -euo pipefail

Data_Folder_input="$1"
SLURM_array_list="$2"
main_output_folder_input="$3"
config="$4"
reference_fasta="${5:-}"
qc_parameters="${6:-}"

function config_value {
    local key="$1"
    local default_value="${2:-}"
    local value=""

    if [[ -f "$config" ]]; then
        value="$(grep -E "^${key}=" "$config" | tail -1 | awk -F'=' '{print $2}' | xargs)"
    fi

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

#INPUT
threads_fallback="$(config_value "threads" "1")"
local_jobs="$(config_value "local_jobs" "$threads_fallback")"
quast_threads="$(config_value "quast_threads" "$threads_fallback")"

#CONDA
conda_source="$(config_value "conda_source" "/opt/anaconda3/etc/profile.d/conda.sh")"
conda_env="$(config_value "conda_env_name" "quast_JOSS")"
. "$conda_source"
conda activate "$conda_env"
quast_cmd="$(command -v quast.py)"

run_quast() {
    local sample_id="$1"
    local fasta_filename="$2"
    local fasta_path
    local sample_output
    local quast_args

    if [[ "$fasta_filename" = /* ]]; then
        fasta_path="$fasta_filename"
    else
        fasta_path="${Data_Folder_input}/${fasta_filename}"
    fi

    sample_output="$main_output_folder_input/processing_files/$sample_id/quast_out"
    mkdir -p "$sample_output"

    echo "Running QUAST on $fasta_path"
    quast_args=("$fasta_path" -o "$sample_output" -l "$sample_id" -t "$quast_threads")
    if [[ -n "$reference_fasta" ]]; then
        quast_args+=(-r "$reference_fasta")
    fi

    "$quast_cmd" "${quast_args[@]}"
}

export Data_Folder_input main_output_folder_input reference_fasta quast_threads quast_cmd
export -f run_quast

parallel -j "$local_jobs" --colsep '__@__' 'bash -c '"'"'run_quast "$@"'"'"' _ {3} {4}' :::: "$SLURM_array_list"

#AGGREGATOR
slurm_array_scripts="$(config_value "slurm_array_scripts" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
qc_parameters="${qc_parameters:-$(config_value "qc_parameters" "$slurm_array_scripts/QC_parameters.yml")}"
bash "$slurm_array_scripts/quast_aggregator.sh" "$main_output_folder_input" "$qc_parameters"
