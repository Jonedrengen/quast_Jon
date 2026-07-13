#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir"' EXIT

make_report() {
    local sample_dir="$1"
    local header="$2"
    local row="$3"
    mkdir -p "$tmpdir/processing_files/$sample_dir/quast_out"
    printf '%s\n%s\n' "$header" "$row" > "$tmpdir/processing_files/$sample_dir/quast_out/transposed_report.tsv"
}

tab=$'\t'
ns_metric="# N's per 100 kbp"
base_header="Assembly${tab}Total length${tab}GC (%)${tab}# contigs${tab}N50${tab}${ns_metric}"
ref_header="${base_header}${tab}Duplication ratio${tab}Genome fraction (%)"
reordered_header="Genome fraction (%)${tab}Unused column${tab}${ns_metric}${tab}Assembly${tab}N50${tab}# contigs${tab}Duplication ratio${tab}GC (%)${tab}Total length"

make_report "missing_reference_metrics" \
    "$base_header" \
    $'passing_no_ref\t5000000\t50.00\t1\t5000000\t0.00'

make_report "failing_required_metrics" \
    "$ref_header" \
    $'bad_assembly\t4200000\t52.00\t301\t49999\t0.02\t1.06\t94.99'

make_report "passing_reference_metrics" \
    "$ref_header" \
    $'passing_with_ref\t5000000\t50.00\t1\t5000000\t0.00\t1.01\t97.5'

make_report "failing_reference_metrics" \
    "$ref_header" \
    $'bad_ref_metrics\t5000000\t50.00\t1\t5000000\t0.00\t1.10\t94.9'

make_report "empty_optional_metric" \
    "$ref_header" \
    $'empty_optional\t5000000\t50.00\t1\t5000000\t0.00\t\t97.5'

make_report "reordered_extra_columns" \
    "$reordered_header" \
    $'98.1\tignored\t0.00\treordered_pass\t5000000\t1\t1.00\t50.00\t5000000'

mkdir -p "$tmpdir/processing_files/missing_report/quast_out"

bash "$REPO_ROOT/scripts/quast_aggregator.sh" "$tmpdir" > "$tmpdir/aggregator.log"

metrics_file="$tmpdir/compiled_files/quast_metrics.tsv"
qc_file="$tmpdir/compiled_files/quast_qc.tsv"
system_status_report="$tmpdir/logs/system_status_report.txt"
failed_file="$tmpdir/logs/failed_assemblies.txt"

assert_file_exists "$metrics_file"
assert_file_exists "$qc_file"
assert_file_exists "$system_status_report"
assert_file_exists "$failed_file"
assert_line_count 8 "$metrics_file"
assert_line_count 8 "$qc_file"

assert_awk '
    $1 == "passing_no_ref" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $7 != "NA" || $8 != "NA" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "bad_assembly" {
        if ($2 != "FAILED" || $3 != "FAILED" || $4 != "FAILED" || $5 != "FAILED" || $6 != "FAILED" || $7 != "FAILED" || $8 != "FAILED" || $9 != "FAILED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "passing_with_ref" {
        if ($7 != "PASSED" || $8 != "PASSED" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "bad_ref_metrics" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $7 != "FAILED" || $8 != "FAILED" || $9 != "FAILED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "empty_optional" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $7 != "NA" || $8 != "PASSED" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "reordered_pass" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $7 != "PASSED" || $8 != "PASSED" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_awk '
    $1 == "missing_report" {
        if ($2 != "FAILED" || $3 != "FAILED" || $4 != "FAILED" || $5 != "FAILED" || $6 != "FAILED" || $7 != "NA" || $8 != "NA" || $9 != "FAILED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$qc_file"

assert_contains "$system_status_report" $'missing_report\tFAILED'
assert_contains "$system_status_report" $'missing_reference_metrics\tSUCCESS'
assert_contains "$failed_file" $'bad_assembly\tFAILED'
assert_contains "$failed_file" $'bad_ref_metrics\tFAILED'
assert_contains "$failed_file" $'missing_report\tFAILED'

empty_tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir" "$empty_tmpdir"' EXIT
mkdir -p "$empty_tmpdir/processing_files"
bash "$REPO_ROOT/scripts/quast_aggregator.sh" "$empty_tmpdir" > "$empty_tmpdir/aggregator.log"
assert_file_exists "$empty_tmpdir/compiled_files/quast_metrics.tsv"
assert_file_exists "$empty_tmpdir/compiled_files/quast_qc.tsv"
assert_file_exists "$empty_tmpdir/logs/system_status_report.txt"
assert_line_count 1 "$empty_tmpdir/compiled_files/quast_metrics.tsv"
assert_line_count 1 "$empty_tmpdir/compiled_files/quast_qc.tsv"
assert_line_count 1 "$empty_tmpdir/logs/system_status_report.txt"

custom_tmpdir="$(make_tmpdir)"
custom_parameters="$custom_tmpdir/custom_parameters.yml"
trap 'rm -rf "$tmpdir" "$empty_tmpdir" "$custom_tmpdir"' EXIT
mkdir -p "$custom_tmpdir/processing_files/custom_thresholds/quast_out"

cat > "$custom_tmpdir/processing_files/custom_thresholds/quast_out/transposed_report.tsv" <<EOF
$base_header
custom_threshold_pass${tab}4050000${tab}52.00${tab}350${tab}40000${tab}0.50
EOF

cat > "$custom_parameters" <<'EOF'
pass_criteria:
  total_length_bp:
    min: 4000000
    max: 4100000
  gc_percent:
    min: 51
    max: 53
  contigs_500bp_or_longer:
    max: 400
  n50_bp:
    min: 30000
  ns_per_100_kbp:
    max: 1
  duplication_ratio:
    max: 1.05
  genome_fraction_percent:
    min: 95
EOF

bash "$REPO_ROOT/scripts/quast_aggregator.sh" "$custom_tmpdir" "$custom_parameters" > "$custom_tmpdir/aggregator.log"
assert_awk '
    $1 == "custom_threshold_pass" {
        if ($2 != "PASSED" || $3 != "PASSED" || $4 != "PASSED" || $5 != "PASSED" || $6 != "PASSED" || $9 != "PASSED") exit 1
        found = 1
    }
    END {exit found ? 0 : 1}
' "$custom_tmpdir/compiled_files/quast_qc.tsv"

echo "test_aggregator.sh passed"
