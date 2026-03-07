#!/usr/bin/env bash
# Database backup script — run via cron or manually.
# Usage: ./scripts/backup.sh [backup_dir]
# Env vars: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
set -euo pipefail

BACKUP_DIR="${1:-/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_HOST="${POSTGRES_HOST:-postgres}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_USER="${POSTGRES_USER:-todo}"
DB_NAME="${POSTGRES_DB:-todo_db}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"

echo "[$(date -Iseconds)] Starting backup of $DB_NAME → $BACKUP_FILE"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$DB_HOST" \
  -p "$DB_PORT" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --no-owner \
  --no-privileges \
  -Fc \
  | gzip > "$BACKUP_FILE"

echo "[$(date -Iseconds)] Backup complete: $(du -h "$BACKUP_FILE" | cut -f1)"

# Rotate old backups
if [ "$RETENTION_DAYS" -gt 0 ]; then
  DELETED=$(find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete -print | wc -l)
  if [ "$DELETED" -gt 0 ]; then
    echo "[$(date -Iseconds)] Rotated $DELETED backups older than $RETENTION_DAYS days"
  fi
fi
