# PMET Backend Service

FastAPI + Celery based backend for PMET task management.

## Quick Start

### Local Development

1. Start Redis:
```bash
docker run -d -p 6379:6379 redis:7-alpine
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Start API server:
```bash
uvicorn api.main:app --reload --port 8000
```

4. Start Celery worker (in another terminal):
```bash
celery -A worker.celery_app worker --loglevel=info
```

### Docker Compose

```bash
cd pmet_backend
docker-compose up -d
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | / | API info |
| GET | /health | Health check |
| GET | /docs | Swagger documentation |
| POST | /api/tasks | Create new PMET task |
| GET | /api/tasks/{task_id} | Get task status |
| GET | /api/tasks/{task_id}/result | Download result |
| GET | /api/tasks | List tasks |
| POST | /api/files/upload | Upload file |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| REDIS_URL | redis://localhost:6379/0 | Redis connection URL |
| PMET_WORKERS | 2 | Number of Celery workers |

## Architecture

```
pmet_backend/
├── api/
│   ├── main.py              # FastAPI application
│   ├── routes/
│   │   ├── tasks.py         # Task endpoints
│   │   └── files.py         # File upload endpoints
│   └── models/
│       └── task.py          # Pydantic models
├── worker/
│   ├── celery_app.py        # Celery configuration
│   └── tasks/
│       └── pmet.py          # PMET task implementation
├── services/
│   ├── executor.py          # PMET shell/binary execution
│   ├── mail.py              # Email notifications
│   ├── storage.py           # File storage management
│   └── database.py          # SQLite metadata store
├── config.py                # Configuration
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```
