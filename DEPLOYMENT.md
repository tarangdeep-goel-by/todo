# Deployment Guide

## Prerequisites

- Docker and Docker Compose
- PostgreSQL 15+
- Redis 7+
- Firebase project with Auth + FCM enabled
- Google Gemini API key
- Sarvam AI API key

## Environment Variables

Copy `.env.example` to `.env` and fill in all required values:

```bash
# Required
DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/todo_db
GEMINI_API_KEY=<your-key>
SARVAM_API_KEY=<your-key>
FIREBASE_PROJECT_ID=<your-project>
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json

# Production
APP_ENV=production
DEBUG=False
CORS_ORIGINS=https://your-domain.com
REDIS_URL=redis://redis:6379/0
```

## Deploy

```bash
docker compose up --build -d
docker exec todo-backend alembic upgrade head
```

## Database Backup

Automated via `scripts/backup.sh`:

```bash
# Manual backup
docker exec todo-backend /app/scripts/backup.sh /backups

# Cron (host machine) — daily at 2 AM
0 2 * * * docker exec todo-backend /app/scripts/backup.sh /backups

# Restore
gunzip -c backup.sql.gz | docker exec -i todo-postgres psql -U todo todo_db
```

Environment variables for backup:
- `BACKUP_RETENTION_DAYS` (default: 7) — auto-rotate old backups

## Health Check

```
GET /health
```

Returns DB connectivity and background task status. Returns 503 if unhealthy.

## Monitoring

- **Prometheus metrics**: `GET /metrics`
- **Structured logs**: JSON format via structlog, includes trace_id for request correlation
- **Sentry**: Set `SENTRY_DSN` env var to enable error tracking

## Scaling

- Backend is stateless — scale horizontally behind a load balancer
- Notification worker uses Redis distributed lock — safe with multiple replicas
- Set `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT` for connection pool tuning
- Docker resource limits configured in `docker-compose.yml` (backend: 1G/1CPU, postgres: 512M/0.5CPU)

## Account Deletion (GDPR)

```
DELETE /api/account
```

Removes all user data (tasks, categories, FCM tokens). Firebase Auth account must be deleted client-side.
