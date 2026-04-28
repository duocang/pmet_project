# Baseline fingerprints

Captured before the monorepo refactor at commit `123a39b` on `refactor/monorepo`.

## What is captured

`capture.sh` records, by section:

- **binaries** — sha256 of every `*/build/{index_c,index_cpp,index_fimo_fused,pair_original,pair_parallel}`. The three subdirs share identical binaries; this is verified.
- **core_demo_indexing_existing_outputs** — sha256 of `PMET_project/results/demo/fimo_official/*` reference outputs.
- **core_demo_run_indexing_{c,cpp,fused}** — runs `PMET_project/scripts/run_indexing.sh -v <ver>` against `data/indexing/demo` and hashes every produced file.
- **core_demo_run_pairing** — runs `PMET_project/scripts/run_pairing.sh` against `data/pairing/demo` and hashes outputs.
- **analysis_smoke** — runs `pmet_analysis_pipeline/scripts/pipeline/00_requirements.sh` (tool presence check).
- **backend_pytest** — runs `pmet_shiny_app/pmet_backend/test_api.py`.

## Pre-refactor status

| Section | Status | Note |
|---|---|---|
| binaries | OK | three subdir copies are byte-identical |
| core_demo_run_indexing_c | OK | deterministic outputs |
| core_demo_run_indexing_cpp | OK | deterministic outputs |
| core_demo_run_indexing_fused | OK | deterministic outputs |
| core_demo_run_pairing | OK | deterministic outputs |
| analysis_smoke | OK | only checks tool presence |
| backend_pytest | **FAIL** | env-blocked: `No module named 'pydantic'`. Not a code regression — the system python3 lacks backend deps. Re-run after `pip install -r pmet_shiny_app/pmet_backend/requirements.txt` for true baseline. |

## Re-running

```bash
bash tests/baseline/capture.sh > tests/baseline/fingerprints.txt
```

Compare with `git diff tests/baseline/fingerprints.txt` after the refactor.
The "binaries" section paths will change (post-refactor everything is at `build/` only) — that section is expected to differ. The hashes for **demo outputs** must stay identical.
