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

#FILESYSTEM
mkdir -p "$main_output_folder_input/compiled_files"
mkdir -p "$main_output_folder_input/logs"

folderlist="$main_output_folder_input/logs/tmp_folderlist.txt"
run_report="$main_output_folder_input/logs/run_report.txt"
metrics_file="$main_output_folder_input/compiled_files/quast_metrics.tsv"
qc_file="$main_output_folder_input/compiled_files/quast_qc.tsv"
failed_file="$main_output_folder_input/logs/failed_assemblies.txt"

find "$main_output_folder_input/processing_files" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort > "$folderlist"

echo -e "sample_id\tstatus" > "$run_report"
echo -e "sample_id\ttotal_length\tgc_percent\tcontigs_ge_500bp\tn50\tns_per_100_kbp\tduplication_ratio\tgenome_fraction_percent" > "$metrics_file"
echo -e "sample_id\ttotal_length\tgc_percent\tcontigs_ge_500bp\tn50\tns_per_100_kbp\tduplication_ratio\tgenome_fraction_percent\toverall_status" > "$qc_file"
> "$failed_file"

function append_missing_sample {
    local sample_id="$1"
    echo -e "${sample_id}\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$metrics_file"
    echo -e "${sample_id}\tFAILED\tFAILED\tFAILED\tFAILED\tFAILED\tNA\tNA\tFAILED" >> "$qc_file"
}

function append_report_rows {
    local report_path="$1"

    awk -F '\t' \
        -v OFS='\t' \
        -v metrics_out="$metrics_file" \
        -v qc_out="$qc_file" \
        -v ns_col_name="# N's per 100 kbp" '
        function metric(name, col) {
            col = idx[name]
            if (col == "" || col > NF || $col == "" || $col == "-") {
                return "NA"
            }
            return $col
        }

        function isnum(value) {
            return value != "NA" && value != "" && value != "-" && value + 0 == value
        }

        function required_range(value, min, max) {
            if (!isnum(value)) {
                return "FAILED"
            }
            return (value + 0 >= min && value + 0 <= max) ? "PASSED" : "FAILED"
        }

        function required_min(value, min) {
            if (!isnum(value)) {
                return "FAILED"
            }
            return (value + 0 >= min) ? "PASSED" : "FAILED"
        }

        function required_max(value, max) {
            if (!isnum(value)) {
                return "FAILED"
            }
            return (value + 0 <= max) ? "PASSED" : "FAILED"
        }

        function optional_min(value, min) {
            if (!isnum(value)) {
                return "NA"
            }
            return (value + 0 >= min) ? "PASSED" : "FAILED"
        }

        function optional_max(value, max) {
            if (!isnum(value)) {
                return "NA"
            }
            return (value + 0 <= max) ? "PASSED" : "FAILED"
        }

        NR == 1 {
            for (i = 1; i <= NF; i++) {
                idx[$i] = i
            }
            next
        }

        NF > 0 {
            sample_id = metric("Assembly")
            total_length = metric("Total length")
            gc_percent = metric("GC (%)")
            contigs = metric("# contigs")
            n50 = metric("N50")
            ns_per_100_kbp = metric(ns_col_name)
            duplication_ratio = metric("Duplication ratio")
            genome_fraction = metric("Genome fraction (%)")

            total_qc = required_range(total_length, 4300000, 6200000)
            gc_qc = required_range(gc_percent, 49.5, 51.5)
            contigs_qc = required_max(contigs, 300)
            n50_qc = required_min(n50, 50000)
            ns_qc = required_max(ns_per_100_kbp, 0.01)
            duplication_qc = optional_max(duplication_ratio, 1.05)
            genome_fraction_qc = optional_min(genome_fraction, 95)

            overall = "PASSED"
            if (total_qc == "FAILED" || gc_qc == "FAILED" || contigs_qc == "FAILED" || n50_qc == "FAILED" || ns_qc == "FAILED" || duplication_qc == "FAILED" || genome_fraction_qc == "FAILED") {
                overall = "FAILED"
            }

            print sample_id, total_length, gc_percent, contigs, n50, ns_per_100_kbp, duplication_ratio, genome_fraction >> metrics_out
            print sample_id, total_qc, gc_qc, contigs_qc, n50_qc, ns_qc, duplication_qc, genome_fraction_qc, overall >> qc_out
        }
    ' "$report_path"
}

while read -r sample_dir; do
    [[ -z "$sample_dir" ]] && continue
    echo "extracting QUAST results from: $sample_dir"
    report_path="$main_output_folder_input/processing_files/$sample_dir/quast_out/transposed_report.tsv"

    if [[ -f "$report_path" ]]; then
        append_report_rows "$report_path"
        echo -e "${sample_dir}\tSUCCESS" >> "$run_report"
    else
        append_missing_sample "$sample_dir"
        echo -e "${sample_dir}\tFAILED" >> "$run_report"
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
