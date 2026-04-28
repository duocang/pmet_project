# PMET Deployment Guide

## Prerequisites

- Docker and Docker Compose
- 4GB+ RAM
- 10GB+ disk space

## Quick Deploy

```bash
# Clone repository
git clone <repository-url>
cd pmet_shiny_app

# Configure email (required for notifications)
cp data/configure/email_credential.txt.example data/configure/email_credential.txt
# Edit with your SMTP credentials

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

## Configuration

### Email Configuration

Edit `data/configure/email_credential.txt`:
```
your_email@gmail.com
your_app_password
your_email@gmail.com
smtp.gmail.com
587
```

### CPU Configuration

Edit `data/configure/cpu_configuration.txt`:
```
4
```

### Nginx Link

Edit `data/configure/nginx_link.txt`:
```
http://your-domain.com/result/
```

## Architecture

```
                    ┌────────────┐
                    │   Nginx    │ :80/:443
                    │ (reverse)  │
                    └─────┬──────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
    ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
    │  Frontend │   │    API    │   │   Redis   │
    │  (Next)   │   │ (FastAPI) │   │   Queue   │
    │   :3000   │   │   :8000   │   │   :6379   │
    └───────────┘   └─────┬─────┘   └───────────┘
                          │
                    ┌─────▼─────┐
                    │  Celery   │
                    │  Workers  │
                    └─────┬─────┘
                          │
                    ┌─────▼─────┐
                    │ PMET      │
                    │ Binaries  │
                    └───────────┘
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| nginx | 80, 443 | Reverse proxy, static files |
| frontend | 3000 | Next.js web application |
| api | 8000 | FastAPI REST API |
| worker | - | Celery task processing |
| redis | 6379 | Message queue |

## Scaling Workers

```bash
# Increase worker concurrency
PMET_WORKERS=4 docker-compose up -d

# Or scale horizontally
docker-compose up -d --scale worker=3
```

## SSL Configuration

Place SSL certificates in `nginx/ssl/`:
```
nginx/ssl/
├── cert.pem
└── key.pem
```

Update `nginx/nginx.conf` for HTTPS.

## Health Checks

```bash
# API health
curl http://localhost:8000/health

# Frontend
curl http://localhost:3000

# Redis
docker-compose exec redis redis-cli ping
```

## Logs

```bash
# All logs
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f worker
```

## Backup

```bash
# Backup results
tar -czf pmet_results_$(date +%Y%m%d).tar.gz result/

# Backup database
cp pmet_backend/pmet.db pmet_backup_$(date +%Y%m%d).db
```

## Troubleshooting

### Worker not processing tasks

```bash
# Check worker logs
docker-compose logs worker

# Restart worker
docker-compose restart worker
```

### File upload fails

```bash
# Check nginx config
docker-compose exec nginx nginx -t

# Increase client_max_body_size in nginx/nginx.conf
```

### Email not sending

```bash
# Verify credentials
cat data/configure/email_credential.txt

# Test SMTP connection
python -c "
import smtplib
s = smtplib.SMTP('smtp.gmail.com', 587)
s.starttls()
s.login('your_email@gmail.com', 'your_app_password')
print('OK')
"
```

## Maintenance

```bash
# Update containers
docker-compose pull
docker-compose up -d

# Clean old results (older than 7 days)
find result/ -mtime +7 -delete

# Monitor disk usage
du -sh result/
```
