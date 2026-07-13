#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir"' EXIT

input_dir="$REPO_ROOT/tests/test_fasta/data"
output_dir="$tmpdir/output"
sample_list="$tmpdir/sample_list.txt"
config_file="$tmpdir/config.env"

assert_dir_exists "$input_dir"
find "$input_dir" -maxdepth 1 -type f \( \
    -name "*.fasta" -o \
    -name "*.fa" -o \
    -name "*.fna" -o \
    -name "*.fasta.gz" -o \
    -name "*.fa.gz" -o \
    -name "*.fna.gz" \
\) -exec basename {} \; | sort > "$sample_list"

sample_count="$(wc -l < "$sample_list" | tr -d '[:space:]')"
[[ "$sample_count" -gt 0 ]] || fail "no FASTA files found in $input_dir"

write_test_config "$config_file" "$REPO_ROOT/scripts" 1 1
skip_without_quast "$config_file"
skip_without_local_runner_support "$config_file"

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
assert_line_count "$((sample_count + 1))" "$metrics_file"
assert_line_count "$((sample_count + 1))" "$qc_file"

while read -r fasta_name; do
    [[ -z "$fasta_name" ]] && continue
    sample_id="${fasta_name%.gz}"
    sample_id="${sample_id%.fasta}"
    sample_id="${sample_id%.fa}"
    sample_id="${sample_id%.fna}"
    assert_contains "$system_status_report" "$sample_id"
done < "$sample_list"

echo "run_integration.sh passed"
