# PMET monorepo

PMET (Promoter Motif Enrichment Tool) — unified repo for the C/C++ engines, the bash + python + R pipeline glue, the FastAPI/Next.js web app, and deploy assets.

## Layout

```
core/          C/C++ engines (indexing, pairing) + CMake
pipeline/      shared bash + python + R helpers; workflows
apps/
  cli/         command-line entry points
  backend/     FastAPI + Celery worker
  frontend/    Next.js
deploy/        docker-compose, nginx, dockerfiles
data/          demo / fixtures only (large data is gitignored)
tests/         baseline fingerprints + integration tests
docs/
legacy/        retired code preserved by source of origin
build/         binaries (gitignored)
```

## Quick start (local CLI)

```bash
make build       # builds core engines into ./build/
make demo        # runs indexing + pairing against data/*/demo
make baseline    # captures fingerprints for regression checks
```

## Research / CLI pipelines (the numbered `0X_*.sh` workflows)

The numbered analysis scripts live at
[`pipeline/workflows/cli/`](pipeline/workflows/cli/). All expect to be
invoked with the **repo root as cwd** (they `cd` there themselves) and
resolve helpers via `pipeline/{lib,python,r}/`.

**Pre-flight (run once):**

```bash
make build                                     # produce ./build/* binaries
bash pipeline/workflows/cli/00_env_check.sh    # check tools, fetch TAIR10 if missing
```

**Two ways to run a workflow, e.g. `03_promoter.sh`:**

```bash
# A) Direct — accepts overrides via getopts; defaults reproduce the canonical TAIR10 demo:
bash pipeline/workflows/cli/03_promoter.sh

# B) Interactive menu — pick from the numbered list:
bash apps/cli/run.sh
```

`03_promoter.sh -h` prints the full option list. Common overrides:

```bash
bash pipeline/workflows/cli/03_promoter.sh \
    -s data/TAIR10.fasta \
    -a data/TAIR10.gff3 \
    -m data/Franco-Zorrilla_et_al_2014.meme \
    -g data/genes/genes_cell_type_treatment.txt \
    -t 8 \
    -o results/03_promoter/01_homotypic \
    -x results/03_promoter/02_heterotypic \
    -y results/03_promoter/plot
```

Outputs land under `results/<workflow_name>/` (gitignored). Heatmaps need
`Rscript` + the R packages listed in
[`pipeline/r/install_packages.R`](pipeline/r/install_packages.R); without
them stages [1] and [2] still produce the data, [3] is skipped with a
warning.

**Workflow index**:

| script | location | purpose |
|---|---|---|
| `pair_only.sh`           | `pipeline/workflows/`     | Re-pair an existing homotypic index (used by web `promoters_pre` mode and CLI re-run scenarios) |
| `00_env_check.sh`        | `pipeline/workflows/cli/` | Tool/dep check; downloads TAIR10 if absent |
| `01_perf_cpu.sh`         | `pipeline/workflows/cli/` | Perf benchmark: single-cpu vs parallel heterotypic |
| `02_perf_params.sh`      | `pipeline/workflows/cli/` | Perf benchmark: sweep PMET parameters on promoters |
| `03_promoter.sh`         | `pipeline/workflows/cli/` | Promoter homotypic + heterotypic + heatmaps |
| `04_intervals.sh`        | `pipeline/workflows/cli/` | Same flow on user-supplied intervals (peaks) |
| `05_promoter_gap.sh`     | `pipeline/workflows/cli/` | Promoter gap-extension analysis |
| `06_elements_longest.sh` | `pipeline/workflows/cli/` | Genomic-element pipeline, longest-isoform strategy |
| `07_elements_merged.sh`  | `pipeline/workflows/cli/` | Genomic-element pipeline, merged-isoform strategy |

The remaining web-app workflows (called by `apps/pmet_backend/services/executor.py`)
still live under [`pipeline/workflows/web/`](pipeline/workflows/web/):
`promoter.sh`, `intervals.sh`. They will be merged with their CLI counterparts
(`03_promoter.sh`, `04_intervals.sh`) into top-level `promoter.sh` and
`intervals.sh` in follow-up commits.

## Deploy the web app

The web app (FastAPI + Celery + Next.js + nginx, behind redis) ships as a
docker-compose stack under `deploy/`. From the repo root:

```bash
make up          # build images + start the stack (5-10 min on first run)
make logs        # tail logs from all services
make ps          # show container status
make down        # stop the stack
make rebuild     # rebuild images and restart (after editing app code)
```

Once `make up` finishes, open **http://localhost:5960** — nginx fronts the
frontend (`/`) and the API (`/api/...`). Container layout:

| service  | role                             | host port |
|----------|----------------------------------|-----------|
| nginx    | reverse proxy                    | **5960**  |
| frontend | Next.js                          | (internal 3000) |
| api      | FastAPI                          | (internal 8000) |
| worker   | Celery worker                    | —         |
| redis    | Celery broker + result backend   | —         |

What gets bind-mounted from the host (so edits take effect without rebuild):

- `apps/pmet_backend/` → `/app/pmet_backend` (uvicorn auto-reloads; worker needs `make restart-worker`)
- `pipeline/`         → `/app/pipeline`     (workflow scripts, python/R helpers)
- `data/`             → `/app/data`         (genomes, pre-computed indexing, demo)
- `deploy/result/`    → `/app/result`       (per-task outputs)

The frontend is **baked into its image** at build time (no bind mount), so
frontend edits need `make rebuild` (or `cd deploy && make rebuild-frontend`
for just the frontend).

### First-time data setup

The pre-computed species indexes (~GBs) aren't shipped in the repo. Run
once on the host (not in a container):

```bash
cd deploy && make fetch-data
```

This downloads TAIR10 + per-species indexes into `data/indexing/` (16G if
you grab everything).

### Email notifications

The backend sends per-task completion emails. Configure SMTP credentials
at `data/configure/email_credential.txt` (gitignored — never commit it).
Format is 5 lines: `username`, `password` (Gmail app-password recommended),
`from_address`, `smtp_server`, `port`.

### More deploy targets

`make up` / `make down` cover the common path. For finer-grained control
(rebuild a single service, restart nginx after editing `nginx.conf`, etc.):

```bash
cd deploy && make help
```

## Migration status

This repo was unified from three separate subdirs (`PMET_project`,
`pmet_analysis_pipeline`, `pmet_shiny_app`) at tag `v0.1.0-monorepo`. See
`tests/baseline/README.md` for the fingerprints used to verify no
regressions across the move.
