#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

tmpdir="$(make_tmpdir)"
trap 'rm -rf "$tmpdir"' EXIT

sample_list="$tmpdir/sample_list.txt"
array_file="$tmpdir/sample_list_SLURM-ARRAY-READY.txt"
expected_file="$tmpdir/expected.txt"

absolute_fasta="$tmpdir/absolute.sample.fna.gz"
touch "$absolute_fasta"

cat > "$sample_list" <<EOF
# comment skipped

alpha.fasta
relative/beta.fa
gamma.fna
delta.fasta.gz
epsilon.fa.gz
zeta.fna.gz
$absolute_fasta
ignored.txt
notes.fasta.bak
EOF

cat > "$expected_file" <<EOF
0__@__1__@__alpha__@__alpha.fasta
0__@__2__@__beta__@__relative/beta.fa
0__@__3__@__gamma__@__gamma.fna
0__@__4__@__delta__@__delta.fasta.gz
0__@__5__@__epsilon__@__epsilon.fa.gz
0__@__6__@__zeta__@__zeta.fna.gz
0__@__7__@__absolute.sample__@__$absolute_fasta
EOF

bash "$REPO_ROOT/scripts/quast_SLURM_array.sh" "$sample_list" "$array_file" > "$tmpdir/array.log"
diff -u "$expected_file" "$array_file"
assert_contains "$tmpdir/array.log" "Skipping non-FASTA entry: ignored.txt"
assert_contains "$tmpdir/array.log" "Skipping non-FASTA entry: notes.fasta.bak"

large_sample_list="$tmpdir/large_sample_list.txt"
large_array_file="$tmpdir/large_SLURM-ARRAY-READY.txt"
for i in $(seq 1 1001); do
    printf 'sample_%04d.fasta\n' "$i"
done > "$large_sample_list"

bash "$REPO_ROOT/scripts/quast_SLURM_array.sh" "$large_sample_list" "$large_array_file" > "$tmpdir/large_array.log"
assert_line_count 1001 "$large_array_file"
assert_eq "0__@__1__@__sample_0001__@__sample_0001.fasta" "$(sed -n '1p' "$large_array_file")" "first array row mismatch"
assert_eq "0__@__1000__@__sample_1000__@__sample_1000.fasta" "$(sed -n '1000p' "$large_array_file")" "1000th array row mismatch"
assert_eq "1__@__1__@__sample_1001__@__sample_1001.fasta" "$(sed -n '1001p' "$large_array_file")" "1001st array row mismatch"

echo "test_array_generation.sh passed"
