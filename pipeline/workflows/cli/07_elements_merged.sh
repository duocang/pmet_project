#!/bin/bash
# 07_elements_merged.sh — PMET on a genomic element, taking the per-gene
# UNION across all isoforms (merged overlapping intervals; no isoform
# specificity). Thin wrapper over pipeline/workflows/cli/_common.sh;
# differs from 06_elements_longest.sh only in the four configuration
# variables set below.

set -euo pipefail

script_dir=$(cd -- "$(dirname "$0")/../../.." && pwd)
cd "$script_dir"

strategy=merged
res_dir=results/07_elements_merged
delete_temp=yes
purpose_text="Search motif pairs on the per-gene UNION of a genomic element across all isoforms"

source "$script_dir/pipeline/workflows/cli/_common.sh"
