#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$repo_root/tests/test_array_generation.sh"
bash "$repo_root/tests/test_submitter_validation.sh"
bash "$repo_root/tests/test_aggregator.sh"
bash "$repo_root/tests/run_synthetic_quast.sh" --smoke

echo "all fast QUAST wrapper tests passed"
