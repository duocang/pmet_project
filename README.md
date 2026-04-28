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

## Quick start

```bash
make build       # builds core engines into ./build/
make demo        # runs indexing + pairing against data/*/demo
make baseline    # captures fingerprints for regression checks
```

## Migration status

This repo is mid-migration from three separate subdirs (`PMET_project`,
`pmet_analysis_pipeline`, `pmet_shiny_app`). See `tests/baseline/README.md`
for the fingerprints used to verify no regressions across the move.
