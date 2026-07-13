#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

mode="${1:---all}"
case "$mode" in
    --smoke|--all) ;;
    *) fail "usage: bash tests/run_synthetic_quast.sh [--smoke|--all]" ;;
esac

tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir"' EXIT

input_dir="$tmpdir/input"
output_dir="$tmpdir/output"
sample_list="$tmpdir/sample_list.txt"
config_file="$tmpdir/config.env"
mkdir -p "$input_dir"
write_test_config "$config_file" "$REPO_ROOT/scripts" 1 1
skip_without_quast "$config_file"
skip_without_local_runner_support "$config_file"

add_case() {
    local sample_id="$1"
    local contigs="$2"
    local contig_length="$3"
    local pattern="$4"
    local n_prefix="${5:-0}"

    write_fasta "$input_dir/$sample_id.fasta" "$contigs" "$contig_length" "$pattern" "$n_prefix"
    printf '%s.fasta\n' "$sample_id" >> "$sample_list"
}

add_case "synthetic_pass_5mb" 1 5000000 "ACGT"

if [[ "$mode" == "--all" ]]; then
    add_case "synthetic_low_total_length" 1 4299999 "ACGT"
    add_case "synthetic_high_gc" 1 5000000 "GCGCAT"
    add_case "synthetic_low_gc" 1 5000000 "ATATGC"
    add_case "synthetic_too_many_contigs" 301 16612 "ACGT"
    add_case "synthetic_low_n50" 101 49505 "ACGT"
    add_case "synthetic_high_n_content" 1 5000000 "ACGT" 1
fi

bash "$REPO_ROOT/scripts/quast_submitter.sh" \
    -i "$input_dir" \
    -s "$sample_list" \
    -o "$output_dir" \
    -c "$config_file" \
    -m LOCAL

metrics_file="$output_dir/compiled_files/quast_metrics.tsv"
qc_file="$output_dir/compiled_files/quast_qc.tsv"
system_status_report="$output_dir/logs/system_status_report.txt"

assert_file_exists "$metrics_file"
assert_file_exists "$qc_file"
assert_file_exists "$system_status_report"
expected_rows="$(( $(wc -l < "$sample_list" | tr -d '[:space:]') + 1 ))"
assert_line_count "$expected_rows" "$metrics_file"
assert_line_count "$expected_rows" "$qc_file"

assert_sample_qc() {
    local sample_id="$1"
    local total="$2"
    local gc="$3"
    local contigs="$4"
    local n50="$5"
    local ns="$6"
    local overall="$7"

    assert_awk '
        $1 == sample_id {
            if ($2 != total || $3 != gc || $4 != contigs || $5 != n50 || $6 != ns || $9 != overall) exit 1
            found = 1
        }
        END {exit found ? 0 : 1}
    ' "$qc_file" \
        sample_id="$sample_id" total="$total" gc="$gc" contigs="$contigs" n50="$n50" ns="$ns" overall="$overall"
}

assert_awk '
    $1 == "synthetic_pass_5mb" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $7 != "NA" || $8 != "NA" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"
assert_contains "$system_status_report" $'synthetic_pass_5mb\tSUCCESS'

if [[ "$mode" == "--all" ]]; then
    assert_sample_qc "synthetic_low_total_length" "FAILED" "PASSED" "PASSED" "PASSED" "PASSED" "FAILED"
    assert_sample_qc "synthetic_high_gc" "PASSED" "FAILED" "PASSED" "PASSED" "PASSED" "FAILED"
    assert_sample_qc "synthetic_low_gc" "PASSED" "FAILED" "PASSED" "PASSED" "PASSED" "FAILED"
    assert_sample_qc "synthetic_too_many_contigs" "PASSED" "PASSED" "FAILED" "FAILED" "PASSED" "FAILED"
    assert_sample_qc "synthetic_low_n50" "PASSED" "PASSED" "PASSED" "FAILED" "PASSED" "FAILED"
    assert_sample_qc "synthetic_high_n_content" "PASSED" "PASSED" "PASSED" "PASSED" "FAILED" "FAILED"
fi

echo "run_synthetic_quast.sh $mode passed"
