#!/bin/bash
#SBATCH -J quast_runner
#SBATCH --error=quast_runner_%A_%a.err
#SBATCH --output=quast_runner_%A_%a.out
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00
#SBATCH --partition=project
set -euo pipefail

#TIMER START
STARTTIMER="$(date +%s)"

#INPUT
Data_Folder_input="$1"
Data_Folder_Samplelist_SLURM_ARRAY_READY_input="$2"
index_set="$3"
main_output_folder_input="$4"
config="${5:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.env}"
reference_fasta="${6:-}"

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

#CONDA
conda_source="$(config_value "conda_source" "/opt/anaconda3/etc/profile.d/conda.sh")"
conda_env_name="$(config_value "conda_env_name" "quast_JOSS")"
quast_threads="$(config_value "quast_threads" "$(config_value "threads" "1")")"

. "$conda_source"
conda activate "$conda_env_name"

#INPUT
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
    echo "SLURM_ARRAY_TASK_ID is not set"
    exit 1
fi

array_line="$(awk -F "__@__" -v idx="$index_set" -v task="$SLURM_ARRAY_TASK_ID" '$1 == idx && $2 == task {print; exit}' "$Data_Folder_Samplelist_SLURM_ARRAY_READY_input")"

if [[ -z "$array_line" ]]; then
    echo "No sample found for chunk $index_set task $SLURM_ARRAY_TASK_ID"
    exit 1
fi

sample_id="$(echo "$array_line" | awk -F "__@__" '{print $3}')"
fasta_filename="$(echo "$array_line" | awk -F "__@__" '{print $4}')"

if [[ "$fasta_filename" = /* ]]; then
    fasta_path="$fasta_filename"
else
    fasta_path="$Data_Folder_input/$fasta_filename"
fi

sample_output="$main_output_folder_input/processing_files/$sample_id/quast_out"
mkdir -p "$sample_output"

#RUN
echo "Running QUAST on $fasta_path"
quast_args=("$fasta_path" -o "$sample_output" -l "$sample_id" -t "$quast_threads")
if [[ -n "$reference_fasta" ]]; then
    quast_args+=(-r "$reference_fasta")
fi
quast.py "${quast_args[@]}"

#MOVING SLURM OUT/ERR
if [[ -n "${SLURM_ARRAY_JOB_ID:-}" ]]; then
    mkdir -p "$main_output_folder_input/processing_files/$sample_id/slurm_outputs"
    [[ -f "quast_runner_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" ]] && mv "quast_runner_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" "$main_output_folder_input/processing_files/$sample_id/slurm_outputs"
    [[ -f "quast_runner_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out" ]] && mv "quast_runner_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out" "$main_output_folder_input/processing_files/$sample_id/slurm_outputs"
fi

#TIMER END
ENDTIMER="$(date +%s)"
DURATION=$((ENDTIMER - STARTTIMER))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$(((DURATION % 3600) % 60))
echo "RUNTIMER: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"
