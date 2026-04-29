# PMET — Paired Motif Enrichment Tool

[www.PMET.online](http://pmet.online/)

PMET identifies cooperative transcription factor (TF) activity by evaluating both
homotypic and heterotypic motif combinations across promoter sets.

This repository contains the full web application: a Next.js frontend, a FastAPI
backend, a Celery worker pool, and the compiled PMET execution engine.

---

## Architecture

```
                       ┌──────────────────────┐
            :80  ──────▶│  nginx (reverse proxy)│
                       └──────┬────────┬──────┘
                              │        │
                ┌──────────────┘        └──────────────┐
                ▼                                       ▼
        ┌──────────────┐                       ┌──────────────┐
        │  frontend    │                       │  api         │
        │  Next.js 14  │                       │  FastAPI     │
        │  :3000       │                       │  :8000       │
        └──────────────┘                       └──────┬───────┘
                                                      │  enqueue
                                                      ▼
                                              ┌──────────────┐
                                              │  redis :6379 │
                                              └──────┬───────┘
                                                      │
                                                      ▼
                                              ┌──────────────┐
                                              │  celery      │
                                              │  worker      │
                                              └──────┬───────┘
                                                      │  exec
                                                      ▼
                                              ┌──────────────────┐
                                              │ pmet_pipeline/*.sh│
                                              │ + C/C++ binaries │
                                              └──────────────────┘
```

| Service  | Image                                 | Port (host) |
| -------- | ------------------------------------- | ----------- |
| nginx    | `nginx:stable-alpine`                 | 80          |
| frontend | built from `pmet_frontend/Dockerfile` | – (proxied) |
| api      | built from `pmet_backend/Dockerfile`  | – (proxied) |
| worker   | same image as api                     | –           |
| redis    | `redis:7-alpine`                      | –           |

---

## Prerequisites

- Docker and Docker Compose v2+
- macOS / Linux host (the included PMET binaries in `pmet_pipeline/build/` are
  Mach-O for Apple Silicon — Linux deployment requires recompiling them; source
  is in `legacy/PMETdev/src/`)
- Indexing data downloaded into `data/indexing/` (one-time, see below)

---

## One-time setup

### 1. Configure runtime files

These three files live in `data/configure/` and are git-ignored. Create them
before the first run:

| File                    | Format                                                                      |
| ----------------------- | --------------------------------------------------------------------------- |
| `cpu_configuration.txt` | Single integer — number of worker threads (e.g. `2`)                        |
| `nginx_link.txt`        | URL prefix used in result-ready emails (e.g. `https://pmet.online/result/`) |
| `email_credential.txt`  | 5 lines: `username`, `password`, `address`, `smtp_server`, `port`           |

### 2. Download reference genomes + pre-computed indexing data

```bash
make fetch-data        # or: bash scripts/download_pmet_data.sh
```

This populates:

- `data/Arabidopsis_thaliana.TAIR10.dna.toplevel.fasta` and `data/TAIR10.gff3` — Arabidopsis reference used by
  the full-promoters mode's "Use example" links.
- `data/indexing/` — pre-computed motif databases for the 21 supported plant
  species (used by the pre-computed-promoters mode).

Safe to re-run; anything already present is skipped.

---

## Build and start (Docker, recommended)

```bash
make build      # build frontend + api/worker images (5–10 min first time)
make start      # bring up redis, api, worker, frontend, nginx
bash scripts/verify_setup.sh
```

Visit **http://localhost** for the application. Useful endpoints behind nginx:

| URL                        | Purpose                          |
| -------------------------- | -------------------------------- |
| `http://localhost/`        | Frontend (Next.js)               |
| `http://localhost/health`  | API health check                 |
| `http://localhost/api/...` | FastAPI endpoints                |
| `http://localhost/result/` | Browse generated result archives |

Stopping and cleanup:

```bash
make logs       # tail logs from all services
make stop       # docker-compose down
make clean      # down -v + wipe result/
```

---

## After changing code

Not every code change needs the same action. Use this table:

| You edited...                                        | Run                     | Why                                                                                     |
| ---------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------- |
| `pmet_frontend/**` (any `.tsx`, `.ts`, CSS, etc.)    | `make rebuild-frontend` | Frontend is baked into its image at build time — no bind mount, so rebuild is required. |
| `pmet_backend/api/**` (FastAPI routes, schemas)      | _nothing_               | Uvicorn runs with `--reload` and the source is bind-mounted.                            |
| `pmet_backend/worker/**`, `pmet_backend/services/**` | `make restart-worker`   | Celery does not auto-reload, but the source is bind-mounted, so a restart is enough.    |
| `nginx/nginx.conf`                                   | `make restart-nginx`    | Config is mounted read-only; restart reloads it.                                        |
| `pmet_backend/Dockerfile`, `requirements.txt`        | `make rebuild-backend`  | Image contents changed.                                                                 |
| `pmet_frontend/Dockerfile`, `package.json`           | `make rebuild-frontend` | Image contents changed.                                                                 |
| `docker-compose.yml`                                 | `make rebuild`          | Orchestration changed — safest to rebuild all.                                          |
| Not sure?                                            | `make rebuild`          | Always correct, just slower (full image rebuild).                                       |

After any of the `rebuild-*` or `restart-*` commands, do a **hard refresh** in the
browser (`Cmd+Shift+R` / `Ctrl+Shift+R`) so cached JS chunks are replaced.

Run `make help` for the full list of targets.

---

## Faster frontend iteration (optional)

The Docker flow above is enough for most work — the API already hot-reloads,
and `make rebuild-frontend` refreshes the frontend image in about a minute.
If that is still too slow while iterating on UI, run the Next.js dev server
on the host alongside the Docker stack:

```bash
make start                     # Docker stack keeps running (api, worker, redis, nginx)
cd pmet_frontend && npm install   # first time only
NEXT_PUBLIC_API_URL=http://localhost/api make frontend
```

Then open **http://localhost:3000** instead of :80. HMR gives you sub-second
reloads. No rebuild required while iterating. All other services still come
from Docker.

## Running everything without Docker

Generally not recommended — the Docker flow is simpler and matches production.
If you really need bare-metal dev (e.g. attaching a Python debugger), the
Make targets exist (`make api`, `make worker`, `make frontend`), and you need
a local Redis running on `:6379` (`brew install redis && brew services start redis`
on macOS, or the package manager equivalent on Linux).

---

## Project structure

```
.
├── docker-compose.yml      # Orchestrates all 5 services
├── Makefile                # start / stop / build / logs / api / worker / frontend
│
├── pmet_backend/           # FastAPI + Celery
│   ├── api/                # HTTP endpoints (tasks, files, results)
│   ├── worker/             # Celery tasks (PMET runner)
│   ├── services/           # executor, mail, storage, database
│   ├── config.py
│   ├── Dockerfile
│   └── requirements.txt
│
├── pmet_frontend/          # Next.js 14 + Tailwind
│   ├── app/                # App-router pages (home, submit, tasks, about, data)
│   ├── components/         # Reusable UI
│   ├── lib/                # API client, types
│   ├── public/figures/     # Workflow + motif diagrams
│   └── Dockerfile
│
├── pmet_pipeline/          # Shell wrappers + compiled PMET binaries (build/)
│
├── nginx/nginx.conf        # Reverse proxy config
│
├── scripts/
│   ├── download_pmet_data.sh
│   └── verify_setup.sh     # Health probes for the running stack
│
├── data/
│   ├── configure/          # cpu_configuration.txt, nginx_link.txt, email_credential.txt
│   ├── indexing/           # Pre-computed indices (downloaded, gitignored)
│   ├── demo_*              # Sample inputs
│   └── *_meta.json         # Reference metadata
│
└── result/                 # Runtime task outputs (gitignored)
```

---

## API reference

| Method | Endpoint                       | Description                  |
| ------ | ------------------------------ | ---------------------------- |
| POST   | `/api/tasks`                   | Submit a new analysis task   |
| GET    | `/api/tasks`                   | List tasks (filter by email) |
| GET    | `/api/tasks/{id}`              | Get a single task's status   |
| GET    | `/api/tasks/{id}/result`       | Download the result archive  |
| GET    | `/api/results/{id}`            | Parsed result rows (JSON)    |
| GET    | `/api/results/{id}/summary`    | Result statistics            |
| GET    | `/api/results/{id}/genes-used` | Genes used by the analysis   |
| POST   | `/api/files/upload`            | Upload a single input file   |

Live OpenAPI docs at `http://localhost/api/docs` once the stack is running.

---

## Analysis modes

1. **Pre-computed Promoters** — fastest path, uses pre-indexed motif databases
   for 21 plant species; only a gene list is required.
2. **Full Promoters** — bring your own genome (FASTA), annotation (GFF3) and
   motif file (MEME).
3. **Intervals** — analyze custom genomic intervals (ChIP-seq peaks, ATAC
   regions) against your motif database.

---

## Development

```bash
make test       # python test_api.py — basic API smoke checks
make logs       # docker-compose logs -f
make clean      # remove containers, volumes, and result/
```

## License

See `LICENSE.md`.
