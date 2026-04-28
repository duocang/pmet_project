#!/bin/bash
# 06_elements_longest.sh — PMET on a genomic element, picking the
# longest isoform per gene. Thin wrapper over scripts/pipeline/
# _elements_common.sh; differs from 07_elements_merged.sh only in the
# four configuration variables set below.

set -euo pipefail

script_dir=$(cd -- "$(dirname "$0")/../../.." && pwd)
cd "$script_dir"

strategy=longest
res_dir=results/06_elements_longest
delete_temp=no
purpose_text="Search motif pairs on the longest isoform of any genomic element"

source "$script_dir/pipeline/workflows/cli/_common.sh"
