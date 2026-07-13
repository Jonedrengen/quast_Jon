#!/bin/bash
#SBATCH -J quast_aggregator
#SBATCH --error=quast_aggregator_%j.err
#SBATCH --output=quast_aggregator_%j.out
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH --partition=project

#TIMER START
STARTTIMER="$(date +%s)"

#INPUT
main_output_folder_input="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qc_parameters="${2:-$script_dir/QC_parameters.yml}"

if [[ ! -f "$qc_parameters" ]]; then
    echo "found no QC parameters file: $qc_parameters"
    exit 1
fi

function yaml_metric_value {
    local metric="$1"
    local key="$2"
    local default_value="${3:-}"
    local value

    value="$(awk -v metric="$metric" -v key="$key" '
        BEGIN {
            in_pass_criteria = 0
            in_metric = 0
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {
            next
        }
        /^pass_criteria:[[:space:]]*$/ {
            in_pass_criteria = 1
            next
        }
        in_pass_criteria && $0 ~ "^  " metric ":[[:space:]]*$" {
            in_metric = 1
            next
        }
        in_metric && /^  [^[:space:]][^:]*:[[:space:]]*$/ {
            in_metric = 0
        }
        in_metric && $0 ~ "^    " key ":[[:space:]]*" {
            sub("^[[:space:]]*" key ":[[:space:]]*", "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
    ' "$qc_parameters")"

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

total_length_min="$(yaml_metric_value "total_length_bp" "min" "4300000")"
total_length_max="$(yaml_metric_value "total_length_bp" "max" "6200000")"
gc_percent_min="$(yaml_metric_value "gc_percent" "min" "49.5")"
gc_percent_max="$(yaml_metric_value "gc_percent" "max" "51.5")"
contigs_max="$(yaml_metric_value "contigs_500bp_or_longer" "max" "300")"
n50_min="$(yaml_metric_value "n50_bp" "min" "50000")"
ns_max="$(yaml_metric_value "ns_per_100_kbp" "max" "")"
ns_expected="$(yaml_metric_value "ns_per_100_kbp" "expected" "")"
duplication_ratio_max="$(yaml_metric_value "duplication_ratio" "max" "1.05")"
genome_fraction_min="$(yaml_metric_value "genome_fraction_percent" "min" "95")"

if [[ -z "$ns_max" && -z "$ns_expected" ]]; then
    ns_max="0.01"
fi

#FILESYSTEM
mkdir -p "$main_output_folder_input/compiled_files"
mkdir -p "$main_output_folder_input/logs"

folderlist="$main_output_folder_input/logs/tmp_folderlist.txt"
system_status_report="$main_output_folder_input/logs/system_status_report.txt"
metrics_file="$main_output_folder_input/compiled_files/quast_metrics.tsv"
qc_file="$main_output_folder_input/compiled_files/quast_qc.tsv"
failed_file="$main_output_folder_input/logs/failed_assemblies.txt"

find "$main_output_folder_input/processing_files" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort > "$folderlist"

echo -e "sample_id\tstatus" > "$system_status_report"
echo -e "sample_id\ttotal_length\tgc_percent\tcontigs_ge_500bp\tn50\tns_per_100_kbp\tduplication_ratio\tgenome_fraction_percent" > "$metrics_file"
echo -e "sample_id\ttotal_length\tgc_percent\tcontigs_ge_500bp\tn50\tns_per_100_kbp\tduplication_ratio\tgenome_fraction_percent\toverall_status" > "$qc_file"
> "$failed_file"

function append_missing_sample {
    local sample_id="$1"
    echo -e "${sample_id}\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$metrics_file"
    echo -e "${sample_id}\tFAILED\tFAILED\tFAILED\tFAILED\tFAILED\tNA\tNA\tFAILED" >> "$qc_file"
}

function report_column_index {
    local column_name="$1"
    local column
    local index=0
    shift

    for column in "$@"; do
        if [[ "$column" == "$column_name" ]]; then
            printf '%s\n' "$index"
            return
        fi
        index=$((index + 1))
    done

    printf '%s\n' "-1"
}

function split_tsv_fields {
    local line="$1"
    local delimiter=$'\x1f'

    line="${line//$'\t'/$delimiter}"
    IFS="$delimiter" read -r -a tsv_fields <<< "$line"
}

function report_value {
    local column_index="$1"
    local value
    local -a values
    shift
    values=("$@")

    if (( column_index < 0 || column_index >= ${#values[@]} )); then
        printf '%s\n' "NA"
        return
    fi

    value="${values[$column_index]}"
    if [[ -z "$value" || "$value" == "-" ]]; then
        printf '%s\n' "NA"
    else
        printf '%s\n' "$value"
    fi
}

function is_number {
    [[ "$1" =~ ^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$ ]]
}

function qc_required_range {
    local value="$1"
    local min="$2"
    local max="$3"

    if ! is_number "$value"; then
        printf '%s\n' "FAILED"
    elif awk -v value="$value" -v min="$min" -v max="$max" 'BEGIN { exit !(value + 0 >= min && value + 0 <= max) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function qc_required_min {
    local value="$1"
    local min="$2"

    if ! is_number "$value"; then
        printf '%s\n' "FAILED"
    elif awk -v value="$value" -v min="$min" 'BEGIN { exit !(value + 0 >= min) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function qc_required_max {
    local value="$1"
    local max="$2"

    if ! is_number "$value"; then
        printf '%s\n' "FAILED"
    elif awk -v value="$value" -v max="$max" 'BEGIN { exit !(value + 0 <= max) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function qc_required_equal {
    local value="$1"
    local expected="$2"

    if ! is_number "$value" || ! is_number "$expected"; then
        printf '%s\n' "FAILED"
    elif awk -v value="$value" -v expected="$expected" 'BEGIN { exit !(value + 0 == expected + 0) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function qc_optional_min {
    local value="$1"
    local min="$2"

    if ! is_number "$value"; then
        printf '%s\n' "NA"
    elif awk -v value="$value" -v min="$min" 'BEGIN { exit !(value + 0 >= min) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function qc_optional_max {
    local value="$1"
    local max="$2"

    if ! is_number "$value"; then
        printf '%s\n' "NA"
    elif awk -v value="$value" -v max="$max" 'BEGIN { exit !(value + 0 <= max) }'; then
        printf '%s\n' "PASSED"
    else
        printf '%s\n' "FAILED"
    fi
}

function append_report_rows {
    local report_path="$1"
    local report_line
    local header_read=0
    local assembly_index
    local total_length_index
    local gc_percent_index
    local contigs_index
    local n50_index
    local ns_per_100_kbp_index
    local duplication_ratio_index
    local genome_fraction_index
    local sample_id
    local total_length
    local gc_percent
    local contigs
    local n50
    local ns_per_100_kbp
    local duplication_ratio
    local genome_fraction
    local total_qc
    local gc_qc
    local contigs_qc
    local n50_qc
    local ns_qc
    local duplication_qc
    local genome_fraction_qc
    local overall
    local -a columns
    local -a values

    while IFS= read -r report_line || [[ -n "$report_line" ]]; do
        if [[ "$header_read" -eq 0 ]]; then
            split_tsv_fields "$report_line"
            columns=("${tsv_fields[@]}")
            assembly_index="$(report_column_index "Assembly" "${columns[@]}")"
            total_length_index="$(report_column_index "Total length" "${columns[@]}")"
            gc_percent_index="$(report_column_index "GC (%)" "${columns[@]}")"
            contigs_index="$(report_column_index "# contigs" "${columns[@]}")"
            n50_index="$(report_column_index "N50" "${columns[@]}")"
            ns_per_100_kbp_index="$(report_column_index "# N's per 100 kbp" "${columns[@]}")"
            duplication_ratio_index="$(report_column_index "Duplication ratio" "${columns[@]}")"
            genome_fraction_index="$(report_column_index "Genome fraction (%)" "${columns[@]}")"
            header_read=1
            continue
        fi

        [[ -z "$report_line" ]] && continue
        split_tsv_fields "$report_line"
        values=("${tsv_fields[@]}")

        sample_id="$(report_value "$assembly_index" "${values[@]}")"
        total_length="$(report_value "$total_length_index" "${values[@]}")"
        gc_percent="$(report_value "$gc_percent_index" "${values[@]}")"
        contigs="$(report_value "$contigs_index" "${values[@]}")"
        n50="$(report_value "$n50_index" "${values[@]}")"
        ns_per_100_kbp="$(report_value "$ns_per_100_kbp_index" "${values[@]}")"
        duplication_ratio="$(report_value "$duplication_ratio_index" "${values[@]}")"
        genome_fraction="$(report_value "$genome_fraction_index" "${values[@]}")"

        total_qc="$(qc_required_range "$total_length" "$total_length_min" "$total_length_max")"
        gc_qc="$(qc_required_range "$gc_percent" "$gc_percent_min" "$gc_percent_max")"
        contigs_qc="$(qc_required_max "$contigs" "$contigs_max")"
        n50_qc="$(qc_required_min "$n50" "$n50_min")"
        if [[ -n "$ns_expected" ]]; then
            ns_qc="$(qc_required_equal "$ns_per_100_kbp" "$ns_expected")"
        else
            ns_qc="$(qc_required_max "$ns_per_100_kbp" "$ns_max")"
        fi
        duplication_qc="$(qc_optional_max "$duplication_ratio" "$duplication_ratio_max")"
        genome_fraction_qc="$(qc_optional_min "$genome_fraction" "$genome_fraction_min")"

        overall="PASSED"
        if [[ "$total_qc" == "FAILED" || "$gc_qc" == "FAILED" || "$contigs_qc" == "FAILED" || "$n50_qc" == "FAILED" || "$ns_qc" == "FAILED" || "$duplication_qc" == "FAILED" || "$genome_fraction_qc" == "FAILED" ]]; then
            overall="FAILED"
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sample_id" "$total_length" "$gc_percent" "$contigs" "$n50" "$ns_per_100_kbp" "$duplication_ratio" "$genome_fraction" >> "$metrics_file"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sample_id" "$total_qc" "$gc_qc" "$contigs_qc" "$n50_qc" "$ns_qc" "$duplication_qc" "$genome_fraction_qc" "$overall" >> "$qc_file"
    done < "$report_path"
}

while read -r sample_dir; do
    [[ -z "$sample_dir" ]] && continue
    echo "extracting QUAST results from: $sample_dir"
    report_path="$main_output_folder_input/processing_files/$sample_dir/quast_out/transposed_report.tsv"

    if [[ -f "$report_path" ]]; then
        append_report_rows "$report_path"
        echo -e "${sample_dir}\tSUCCESS" >> "$system_status_report"
    else
        append_missing_sample "$sample_dir"
        echo -e "${sample_dir}\tFAILED" >> "$system_status_report"
        echo -e "${sample_dir}\tFAILED" >> "$failed_file"
    fi
    echo
done < "$folderlist"

if awk -F '\t' 'NR > 1 && $NF == "FAILED" {found = 1} END {exit found ? 0 : 1}' "$qc_file"; then
    awk -F '\t' 'NR > 1 && $NF == "FAILED" {print $1 "\tFAILED"}' "$qc_file" >> "$failed_file"
fi

if [[ -s "$failed_file" ]]; then
    echo "$(wc -l < "$failed_file") assemblies failed."
else
    echo "no failed assemblies found."
    rm -f "$failed_file"
fi

if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    mkdir -p "$main_output_folder_input/slurm"
    [[ -f "quast_aggregator_${SLURM_JOB_ID}.err" ]] && mv "quast_aggregator_${SLURM_JOB_ID}.err" "$main_output_folder_input/slurm"
    [[ -f "quast_aggregator_${SLURM_JOB_ID}.out" ]] && mv "quast_aggregator_${SLURM_JOB_ID}.out" "$main_output_folder_input/slurm"
fi

#TIMER END
ENDTIMER="$(date +%s)"
DURATION=$((ENDTIMER - STARTTIMER))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$(((DURATION % 3600) % 60))
echo "RUNTIMER: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"
