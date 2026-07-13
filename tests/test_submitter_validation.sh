#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir"' EXIT

input_dir="$tmpdir/input"
output_dir="$tmpdir/output"
config_file="$tmpdir/config.env"
mkdir -p "$input_dir"
write_test_config "$config_file"
touch "$input_dir/example.fasta"

assert_command_fails "$tmpdir/missing_input.log" \
    bash "$REPO_ROOT/scripts/quast_submitter.sh" \
        -i "$tmpdir/missing_input" \
        -s "$tmpdir/sample_list.txt" \
        -o "$output_dir" \
        -c "$config_file" \
        -m LOCAL
assert_contains "$tmpdir/missing_input.log" "found no input folder"

assert_command_fails "$tmpdir/missing_config.log" \
    bash "$REPO_ROOT/scripts/quast_submitter.sh" \
        -i "$input_dir" \
        -s "$tmpdir/sample_list.txt" \
        -o "$output_dir" \
        -c "$tmpdir/missing_config.env" \
        -m LOCAL
assert_contains "$tmpdir/missing_config.log" "found no config file"

assert_command_fails "$tmpdir/invalid_mode.log" \
    bash "$REPO_ROOT/scripts/quast_submitter.sh" \
        -i "$input_dir" \
        -o "$output_dir" \
        -c "$config_file" \
        -m BADMODE
assert_contains "$tmpdir/invalid_mode.log" "mode must be SLURM or LOCAL"

assert_command_fails "$tmpdir/missing_reference.log" \
    bash "$REPO_ROOT/scripts/quast_submitter.sh" \
        -i "$input_dir" \
        -o "$output_dir" \
        -c "$config_file" \
        -m LOCAL \
        -r "$tmpdir/missing_reference.fasta"
assert_contains "$tmpdir/missing_reference.log" "found no reference FASTA"

assert_command_fails "$tmpdir/missing_qc_parameters.log" \
    bash "$REPO_ROOT/scripts/quast_submitter.sh" \
        -i "$input_dir" \
        -o "$output_dir" \
        -c "$config_file" \
        -p "$tmpdir/missing_parameters.yml" \
        -m LOCAL
assert_contains "$tmpdir/missing_qc_parameters.log" "found no QC parameters file"

stub_scripts="$tmpdir/stub_scripts"
stub_output="$tmpdir/stub_output"
stub_config="$tmpdir/stub_config.env"
mkdir -p "$stub_scripts" "$input_dir/nested"
cp "$REPO_ROOT/scripts/quast_SLURM_array.sh" "$stub_scripts/quast_SLURM_array.sh"

cat > "$stub_scripts/quast_runner_local.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
data_folder="$1"
array_list="$2"
main_output="$3"
config="$4"
reference="${5:-}"
mkdir -p "$main_output/logs" "$main_output/compiled_files"
{
    printf 'data_folder=%s\n' "$data_folder"
    printf 'array_list=%s\n' "$array_list"
    printf 'config=%s\n' "$config"
    printf 'reference=%s\n' "$reference"
} > "$main_output/logs/stub_runner_args.txt"
EOF
chmod +x "$stub_scripts/quast_runner_local.sh"

write_test_config "$stub_config" "$stub_scripts"
touch "$input_dir/b_sample.fa" \
      "$input_dir/a_sample.fasta" \
      "$input_dir/c_sample.fna" \
      "$input_dir/d_sample.fasta.gz" \
      "$input_dir/e_sample.fa.gz" \
      "$input_dir/f_sample.fna.gz" \
      "$input_dir/ignored.txt" \
      "$input_dir/nested/nested_sample.fasta"

bash "$REPO_ROOT/scripts/quast_submitter.sh" \
    -i "$input_dir" \
    -o "$stub_output" \
    -c "$stub_config" \
    -m LOCAL > "$tmpdir/omitted_sample_list.log"

assert_file_exists "$stub_output/sample_list.txt"
assert_file_exists "$stub_output/sample_list_SLURM-ARRAY-READY.txt"
assert_file_exists "$stub_output/logs/stub_runner_args.txt"

cat > "$tmpdir/expected_sample_list.txt" <<'EOF'
a_sample.fasta
b_sample.fa
c_sample.fna
d_sample.fasta.gz
e_sample.fa.gz
example.fasta
f_sample.fna.gz
EOF
diff -u "$tmpdir/expected_sample_list.txt" "$stub_output/sample_list.txt"

cat > "$tmpdir/expected_array.txt" <<'EOF'
0__@__1__@__a_sample__@__a_sample.fasta
0__@__2__@__b_sample__@__b_sample.fa
0__@__3__@__c_sample__@__c_sample.fna
0__@__4__@__d_sample__@__d_sample.fasta.gz
0__@__5__@__e_sample__@__e_sample.fa.gz
0__@__6__@__example__@__example.fasta
0__@__7__@__f_sample__@__f_sample.fna.gz
EOF
diff -u "$tmpdir/expected_array.txt" "$stub_output/sample_list_SLURM-ARRAY-READY.txt"

echo "test_submitter_validation.sh passed"
