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

## Pipeline workflows

All workflows live under [`pipeline/workflows/`](pipeline/workflows/) and
expect the **repo root as cwd** (they `cd` there themselves). Helpers
come from `pipeline/{lib,python,r}/`. Output lands under `results/`
(gitignored).

**Pre-flight (run once):**

```bash
make build                                          # produce ./build/* binaries
bash pipeline/workflows/cli/00_env_check.sh         # check tools, fetch TAIR10 if missing
```

**Two ways to run, e.g. `promoter.sh`:**

```bash
# A) Direct — defaults reproduce the canonical TAIR10 demo, all overridable via getopts:
bash pipeline/workflows/promoter.sh

# B) Interactive menu — pick from the listed workflows:
bash apps/cli/run.sh
```

Each script's `-h` prints the full option list. Common promoter override:

```bash
bash pipeline/workflows/promoter.sh \
    -s data/TAIR10.fasta \
    -a data/TAIR10.gff3 \
    -m data/Franco-Zorrilla_et_al_2014.meme \
    -g data/genes/genes_cell_type_treatment.txt \
    -t 8
```

Heatmaps (stage [3]) need `Rscript` + the R packages listed in
[`pipeline/r/install_packages.R`](pipeline/r/install_packages.R); the
data stages [1]+[2] still produce `motif_output.txt` if Rscript is
missing — the heatmap stage is skipped with a warning.

**Workflow index**:

| script | location | purpose |
|---|---|---|
| `promoter.sh`            | `pipeline/workflows/`     | **Full promoter pipeline** — homotypic + heterotypic + heatmaps. Used by CLI demo and web `promoters` mode. |
| `intervals.sh`           | `pipeline/workflows/`     | **Full interval pipeline** — same flow on user-supplied intervals (e.g. ATAC-seq peaks). Used by web `intervals` mode. |
| `elements.sh`            | `pipeline/workflows/`     | **Genomic-element pipeline** (UTR / CDS / mRNA / exon). `-s longest \| merged` selects the isoform-aggregation strategy. Loops over every gene list in `data/genes/*.txt`. |
| `pair_only.sh`           | `pipeline/workflows/`     | **Re-pair an existing homotypic index** — skips the expensive indexing stage. Used by web `promoters_pre` mode and CLI re-runs. |
| `00_env_check.sh`        | `pipeline/workflows/cli/` | Tool/dep check; downloads TAIR10 if absent |
| `01_perf_cpu.sh`         | `pipeline/workflows/cli/` | Perf benchmark: single-cpu vs parallel heterotypic |
| `02_perf_params.sh`      | `pipeline/workflows/cli/` | Perf benchmark: sweep PMET parameters on promoters |
| `05_promoter_gap.sh`     | `pipeline/workflows/cli/` | Promoter gap-extension analysis |

`pipeline/workflows/cli/` underscore-prefixed files (`_common.sh`,
`_pmet_index_element.sh`) are libraries / sub-workflows sourced by 06/07;
they don't appear in the launcher menu.

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
