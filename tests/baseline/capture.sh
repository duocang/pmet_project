#!/usr/bin/env bash
# Baseline fingerprint capture.
# Records: binary hashes, demo output hashes, smoke status, pytest status.
# Run from repo root: bash tests/baseline/capture.sh > tests/baseline/fingerprints.txt
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

hash_file() {
  if [ -f "$1" ]; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "MISSING"
  fi
}

hash_dir_files() {
  local d="$1"
  if [ -d "$d" ]; then
    (cd "$d" && find . -type f -not -name ".DS_Store" 2>/dev/null | sort | xargs shasum -a 256 2>/dev/null)
  else
    echo "DIR_MISSING $d"
  fi
}

echo "# baseline captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# host: $(uname -mrs)"
echo "# git: $(git rev-parse --short HEAD 2>/dev/null) on $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
echo ""

echo "## section:binaries"
for d in PMET_project pmet_analysis_pipeline pmet_shiny_app; do
  for b in index_c index_cpp index_fimo_fused pair_original pair_parallel; do
    printf "%s/build/%s\t%s\n" "$d" "$b" "$(hash_file "$d/build/$b")"
  done
done
echo ""

echo "## section:core_demo_indexing_existing_outputs"
hash_dir_files "PMET_project/results/demo"
echo ""

for v in c cpp fused; do
  echo "## section:core_demo_run_indexing_$v"
  out_dir="$(mktemp -d)"
  if bash PMET_project/scripts/run_indexing.sh -v "$v" -o "$out_dir" >"/tmp/baseline_idx_$v.log" 2>&1; then
    echo "# RUN_OK"
    hash_dir_files "$out_dir"
  else
    echo "# RUN_FAIL exit=$?"
    tail -20 "/tmp/baseline_idx_$v.log" | sed 's/^/# /'
  fi
  rm -rf "$out_dir"
  echo ""
done

echo "## section:core_demo_run_pairing"
out_dir="$(mktemp -d)"
if bash PMET_project/scripts/run_pairing.sh -o "$out_dir" >/tmp/baseline_pair.log 2>&1; then
  echo "# RUN_OK"
  hash_dir_files "$out_dir"
else
  echo "# RUN_FAIL exit=$?"
  tail -20 /tmp/baseline_pair.log | sed 's/^/# /'
fi
rm -rf "$out_dir"
echo ""

echo "## section:analysis_smoke"
if bash pmet_analysis_pipeline/scripts/pipeline/00_requirements.sh >/tmp/baseline_smoke.log 2>&1; then
  echo "# SMOKE_OK"
  tail -5 /tmp/baseline_smoke.log | sed 's/^/# /'
else
  echo "# SMOKE_FAIL exit=$?"
  tail -20 /tmp/baseline_smoke.log | sed 's/^/# /'
fi
echo ""

echo "## section:backend_pytest"
if (cd pmet_shiny_app && python3 pmet_backend/test_api.py) >/tmp/baseline_pytest.log 2>&1; then
  echo "# PYTEST_OK"
  tail -5 /tmp/baseline_pytest.log | sed 's/^/# /'
else
  echo "# PYTEST_FAIL exit=$?"
  tail -20 /tmp/baseline_pytest.log | sed 's/^/# /'
fi
