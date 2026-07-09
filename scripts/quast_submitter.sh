#!/bin/bash
#SBATCH -J quast_submitter
#SBATCH --error=quast_submitter_%j.err
#SBATCH --output=quast_submitter_%j.out
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --partition=project

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function usage {
    echo "Usage essential: $0 -i <input_folder> -s <sample_list> -o <output_dir>"
    echo "  -i: Path to the input folder containing FASTA files"
    echo "  -s: Path to the sample list file (one FASTA filename per line; optional)"
    echo "  -o: Path to the output directory where results will be stored"
    echo
    echo "Usage optional"
    echo "  -m: Mode of operation ('SLURM' or 'LOCAL'),        default = 'SLURM'"
    echo "  -j: Jobname,                                       default = 'quast_runner'"
    echo "  -c: config                                         default = scripts/config.env"
    echo "  -r: Reference FASTA for reference-based QUAST metrics"
    echo
    echo "avoid spaces, dots, and special characters in sample names to prevent issues with file handling"
}

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

while getopts "i:s:o:m:j:c:r:" opt; do
  case $opt in
    i) input_folder="$OPTARG" ;;
    s) sample_list="$OPTARG" ;;
    o) output_dir="$OPTARG" ;;
    m) mode="$OPTARG" ;;
    j) jobname="$OPTARG" ;;
    c) config="$OPTARG";;
    r) reference_fasta="$OPTARG";;
    \?) echo "Invalid option -$OPTARG" >&2 ;;
  esac
done

mode="${mode:-SLURM}"
jobname="${jobname:-quast_runner}"
config="${config:-$script_dir/config.env}"
reference_fasta="${reference_fasta:-}"

if [[ -z "$input_folder" ]] || [[ -z "$output_dir" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$input_folder" ]]; then
    echo "found no input folder: $input_folder"
    echo "__________________________________________________________"
    usage
    exit 1
fi

if [[ ! -f "$config" ]]; then
    echo "found no config file: $config"
    exit 1
fi

if [[ -n "$reference_fasta" ]] && [[ ! -f "$reference_fasta" ]]; then
    echo "found no reference FASTA: $reference_fasta"
    exit 1
fi

if [[ "$mode" != "SLURM" ]] && [[ "$mode" != "LOCAL" ]]; then
    echo "mode must be SLURM or LOCAL"
    exit 1
fi

slurm_script_location="$(config_value "slurm_array_scripts" "$script_dir")"

mkdir -p "$output_dir"
mkdir -p "$output_dir/processing_files"
mkdir -p "$output_dir/compiled_files"
mkdir -p "$output_dir/logs"
if [[ "$mode" == "SLURM" ]]; then
    mkdir -p "$output_dir/slurm"
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        [[ -f "quast_submitter_${SLURM_JOB_ID}.out" ]] && mv "quast_submitter_${SLURM_JOB_ID}.out" "$output_dir/slurm"
        [[ -f "quast_submitter_${SLURM_JOB_ID}.err" ]] && mv "quast_submitter_${SLURM_JOB_ID}.err" "$output_dir/slurm"
    fi
fi

if [[ -z "$sample_list" ]]; then
    echo "no sample list found, creating one from input folder"
    echo "__________________________________________________________"
    sample_list="$output_dir/sample_list.txt"
    find "$input_folder" -maxdepth 1 -type f \( -name "*.fasta" -o -name "*.fa" -o -name "*.fna" -o -name "*.fasta.gz" -o -name "*.fa.gz" -o -name "*.fna.gz" \) -exec basename {} \; | sort > "$sample_list"
elif [[ ! -f "$sample_list" ]]; then
    echo "found no sample list: $sample_list"
    exit 1
fi

samplelist_filename="$(basename "${sample_list%.*}")"
slurm_array_ready_file="$output_dir/${samplelist_filename}_SLURM-ARRAY-READY.txt"

bash "$slurm_script_location/quast_SLURM_array.sh" "$sample_list" "$slurm_array_ready_file"

if [[ ! -s "$slurm_array_ready_file" ]]; then
    echo "Error: failed to generate non-empty $slurm_array_ready_file"
    exit 1
fi

if [[ "$mode" == "SLURM" ]]; then
    numFiles="$(wc -l < "$slurm_array_ready_file")"
    Slurm_MaxArraySize=1000

    if (( numFiles % Slurm_MaxArraySize == 0 )); then
        Slurm_chunks=$(( numFiles / Slurm_MaxArraySize ))
    else
        Slurm_chunks=$(( numFiles / Slurm_MaxArraySize + 1 ))
    fi

    if (( Slurm_chunks == 1 )); then
        Slurm_CalcRunParallel=12
    elif (( Slurm_chunks == 2 )); then
        Slurm_CalcRunParallel=6
    elif (( Slurm_chunks == 3 )); then
        Slurm_CalcRunParallel=4
    elif (( Slurm_chunks == 4 )); then
        Slurm_CalcRunParallel=3
    elif (( Slurm_chunks <= 6 )); then
        Slurm_CalcRunParallel=2
    else
        Slurm_CalcRunParallel=1
    fi

    for ((i=0; i<Slurm_chunks; i++)); do
        index_set="$i"
        array_start="$(grep "^${i}__@__" "$slurm_array_ready_file" | head -1 | awk -F "__@__" '{print $2}')"
        array_end="$(grep "^${i}__@__" "$slurm_array_ready_file" | tail -1 | awk -F "__@__" '{print $2}')"

        echo "sbatch --array=${array_start}-${array_end}%${Slurm_CalcRunParallel} -J $jobname $slurm_script_location/quast_runner.sh $input_folder $slurm_array_ready_file $index_set $output_dir $config $reference_fasta"
        sbatch --array="${array_start}-${array_end}%${Slurm_CalcRunParallel}" -J "$jobname" "$slurm_script_location/quast_runner.sh" "$input_folder" "$slurm_array_ready_file" "$index_set" "$output_dir" "$config" "$reference_fasta"
    done

    echo "sbatch --dependency=singleton -J $jobname $slurm_script_location/quast_aggregator.sh $output_dir"
    sbatch --dependency=singleton -J "$jobname" "$slurm_script_location/quast_aggregator.sh" "$output_dir"
fi

if [[ "$mode" == "LOCAL" ]]; then
    bash "$slurm_script_location/quast_runner_local.sh" "$input_folder" "$slurm_array_ready_file" "$output_dir" "$config" "$reference_fasta"
fi
