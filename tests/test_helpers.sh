#!/bin/bash

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

make_tmpdir() {
    mktemp -d "${TMPDIR:-/tmp}/quast_wrapper_test.XXXXXX"
}

assert_file_exists() {
    local path="$1"
    [[ -f "$path" ]] || fail "expected file to exist: $path"
}

assert_dir_exists() {
    local path="$1"
    [[ -d "$path" ]] || fail "expected directory to exist: $path"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-values differ}"
    [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
    local path="$1"
    local text="$2"
    grep -Fq "$text" "$path" || fail "expected $path to contain: $text"
}

assert_line_count() {
    local expected="$1"
    local path="$2"
    local actual
    actual="$(wc -l < "$path" | tr -d '[:space:]')"
    assert_eq "$expected" "$actual" "unexpected line count in $path"
}

assert_awk() {
    local program="$1"
    local path="$2"
    shift 2

    if [[ "$#" -eq 0 ]]; then
        awk -F '\t' "$program" "$path" || fail "awk assertion failed for $path"
        return
    fi

    local awk_args=()
    local assignment
    for assignment in "$@"; do
        awk_args+=("-v" "$assignment")
    done

    awk -F '\t' "${awk_args[@]}" "$program" "$path" || fail "awk assertion failed for $path"
}

assert_command_fails() {
    local output_path="$1"
    shift

    set +e
    "$@" > "$output_path" 2>&1
    local status=$?
    set -e

    [[ "$status" -ne 0 ]] || fail "expected command to fail: $*"
}

write_test_config() {
    local path="$1"
    local scripts_dir="${2:-$REPO_ROOT/scripts}"
    local local_jobs="${3:-1}"
    local quast_threads="${4:-1}"

    cat > "$path" <<EOF
slurm_array_scripts=$scripts_dir
conda_source=/opt/anaconda3/etc/profile.d/conda.sh
conda_env_name=quast_JOSS
qc_parameters=$REPO_ROOT/scripts/QC_parameters.yml
local_jobs=$local_jobs
quast_threads=$quast_threads
threads=$quast_threads
EOF
}

quast_config_available() {
    local config_path="$1"

    bash -c '
        set -euo pipefail
        source "$1"
        [[ -f "$conda_source" ]]
        source "$conda_source"
        conda activate "$conda_env_name"
        command -v quast.py >/dev/null
        command -v parallel >/dev/null
    ' _ "$config_path" >/dev/null 2>&1
}

skip_without_quast() {
    local config_path="$1"
    if ! quast_config_available "$config_path"; then
        echo "SKIP: quast.py and GNU parallel are not available through the configured conda environment"
        exit 0
    fi
}

local_runner_function_export_available() {
    local config_path="${1:-}"

    bash -c '
        set -euo pipefail
        if [[ -n "${1:-}" ]]; then
            source "$1"
            source "$conda_source"
            conda activate "$conda_env_name"
        fi
        command -v parallel >/dev/null
        run_quast() { :; }
        export -f run_quast
        printf "%s\n" "0__@__1__@__sample__@__sample.fasta" | parallel --colsep "__@__" '"'"'bash -c '"'"'"'"'"'"'"'"'run_quast "$@"'"'"'"'"'"'"'"'"' _ {3} {4}'"'"'
    ' _ "$config_path" >/dev/null 2>&1
}

skip_without_local_runner_support() {
    local config_path="${1:-}"
    if ! local_runner_function_export_available "$config_path"; then
        echo "SKIP: GNU parallel did not preserve exported Bash functions for the current LOCAL runner"
        exit 0
    fi
}

write_fasta() {
    local path="$1"
    local contigs="$2"
    local contig_length="$3"
    local pattern="$4"
    local n_prefix="${5:-0}"

    awk -v contigs="$contigs" -v contig_length="$contig_length" -v pattern="$pattern" -v n_prefix="$n_prefix" '
        function base_at(pos, pattern_len) {
            if (n_prefix > 0) {
                n_prefix--
                return "N"
            }
            pattern_len = length(pattern)
            return substr(pattern, ((pos - 1) % pattern_len) + 1, 1)
        }

        BEGIN {
            for (c = 1; c <= contigs; c++) {
                print ">contig_" c
                line = ""
                for (i = 1; i <= contig_length; i++) {
                    line = line base_at(i)
                    if (length(line) == 80) {
                        print line
                        line = ""
                    }
                }
                if (length(line) > 0) {
                    print line
                }
            }
        }
    ' /dev/null > "$path"
}
