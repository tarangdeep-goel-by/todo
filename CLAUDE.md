# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice-first AI-powered hierarchical todo app. Flutter mobile frontend communicates with a FastAPI backend via REST API. Users input tasks via keyboard or voice, backend AI (Gemini) extracts task proposals (ADD/COMPLETE/EDIT/DELETE/MOVE/BREAKDOWN), user reviews and confirms, then tasks are executed against a PostgreSQL database. Tasks are organized into 8 domains (Career, Finance, Health, Relationships, Growth, Recreation, Home, Community) with unlimited tree depth.

## Quick Start

```bash
# Backend (Docker-first, always use Docker)
cd backend && docker-compose up --build    # API: http://localhost:8001, Postgres: :5433
# Volume-mounted (.:/app) — Python code changes reflect without rebuild
# Only re-run --build if Dockerfile or requirements.txt changes

# Frontend
cd frontend && flutter pub get && flutter run

# Seed test data
cd backend && ./seed_tasks.sh              # 12 basic tasks
cd backend && ./seed_deep_tasks.sh         # 62-task deep hierarchy
```

## Commands

```bash
# Backend tests (inside Docker)
docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance
docker exec todo-backend python -m pytest tests/test_brain_dump.py -v                        # Single file
docker exec todo-backend python -m pytest tests/test_brain_dump.py::TestBrainDump::test_gibberish_returns_empty_proposals -v  # Single test
docker exec todo-backend python tests/performance/test_agent_performance.py                  # Performance benchmarks

# Frontend tests
cd frontend && flutter test                                              # All
cd frontend && flutter test test/providers/task_store_provider_test.dart  # Single file
cd frontend && flutter test --name "filters tasks by category"           # By name
cd frontend && flutter analyze                                           # Lint (must be 0 issues)

# Database migrations
docker exec todo-backend alembic upgrade head                            # Apply
docker exec todo-backend alembic revision --autogenerate -m "description"  # Create new
docker exec todo-backend alembic downgrade -1                              # Rollback one

# Brain dump action detection eval (65 cases, ~90s with LLM)
docker exec todo-backend python evaluation/run_eval.py                    # Full run
docker exec todo-backend python evaluation/run_eval.py --filter-id add_01 # Single case
docker exec todo-backend python evaluation/run_eval.py --no-llm          # Dry-run (harness only)
docker exec todo-backend python evaluation/run_eval.py --no-prefilter    # Skip pre-filter, LLM-only
```

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│  Flutter Frontend    │  REST   │  FastAPI Backend                 │
│  (Riverpod state)    │ ◄─────► │  (async Python)                  │
│                      │         │                                  │
│  TaskStoreNotifier   │  WS     │  /api/agent/braindump ← extract  │
│  ├── allTasks        │ ◄─────► │  /api/agent/braindump/submit     │
│  ├── byCategory      │         │  /ws/ramble           ← stream   │
│  ├── byId            │         │  /api/tasks/*         ← CRUD     │
│  ├── children        │         │  /api/categories/*    ← domains  │
│  └── flatFiltered    │         │                                  │
│                      │         │  AgentService → GeminiService    │
│  RambleSheet ──────► │         │  RambleService (Gemini Live)     │
│  PushToTalkButton    │         │  TaskService  → QueryBuilder     │
└─────────────────────┘         └──────────┬───────────────────────┘
                                           │
                                    ┌──────┴──────┐
                                    │ PostgreSQL   │
                                    │ (port 5433)  │
                                    └─────────────┘
```

### Two Input Modes (unified brain dump pipeline)

1. **Keyboard** (tap pill): Type text → `POST /api/agent/braindump` → task proposals → RambleScreen review → submit
2. **Voice / Ramble** (long-press pill): Stream PCM audio via `/ws/ramble` → Gemini Live transcribes in real-time → user reviews transcript → `/api/agent/braindump` extracts task proposals → user reviews/edits → `/api/agent/braindump/submit` creates tasks in batch

### Detailed Guides

- **Backend**: See [`backend/CLAUDE.md`](backend/CLAUDE.md) — brain dump pipeline, services, database schema, API endpoints, testing setup
- **Frontend**: See [`frontend/CLAUDE.md`](frontend/CLAUDE.md) — TaskStoreNotifier, derived providers, view modes, voice flow, testing patterns

## Cross-Cutting Concerns

### Computed "overdue" Status
"Overdue" is never stored in the database. Both backend (`schemas.py` validator) and frontend (`_computeDisplayStatus()`) compute it identically: `status == 'active' && due_date < now`. Client-side filter/sort logic must mirror backend `QueryBuilder` semantics exactly.

### Default Sort Order
Both frontend and backend use: `status:asc → due_date:asc → priority:desc → created_at:desc`
- Status rank: overdue(0) < active(1) < completed(2)
- Priority rank: high(3) > medium(2) > low(1) > none(0)
- Null dates sort last

### Optimistic Updates
Frontend mutations update `TaskStoreNotifier` immediately, then sync to backend async. If backend fails, the store should be reverted.

### 8-Domain Limit
Categories (Career, Finance, Health, Relationships, Growth, Recreation, Home, Community) are enforced in `agent_service.py` (max 8). The frontend dynamically creates domain palettes from backend categories.

## Authentication

Firebase Auth end-to-end. Backend verifies ID tokens, frontend manages auth state.

- **Backend**: `auth.py` → `get_current_user` dependency verifies Firebase ID tokens. Used as `Depends(get_current_user)` on protected routes. Returns user UID string.
- **Frontend**: `auth_provider.dart` manages Firebase Auth state (login/signup/logout). `auth_interceptor.dart` is a Dio interceptor that attaches `Authorization: Bearer <idToken>` to all API requests.
- **Rate limiting**: `rate_limit.py` uses `slowapi` — keyed by Bearer token (one bucket per auth session), falls back to client IP.

## Security & Observability

- **Structured logging**: `structured_logging.py` uses `structlog` for JSON-formatted logs with context vars (`trace_id`, `user_id`, `session_id`).
- **Request logging middleware**: `middleware/request_logging.py` logs `api.request`/`api.response` with trace IDs, duration, status. Skips `/health`, `/docs`.
- **Trace propagation**: Client sends `X-Request-Id` and `X-Session-Id` headers; middleware sets context vars for downstream log entries.

## Environment

**Backend** (Docker env via `.env` file, referenced by `docker-compose.yml` `env_file: .env`):

| Variable | Required | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | Yes | — | Auto-composed in docker-compose from `POSTGRES_*` vars |
| `GEMINI_API_KEY` | Yes | — | Google Gemini API key |
| `SARVAM_API_KEY` | Yes | — | Sarvam AI streaming STT |
| `FIREBASE_PROJECT_ID` | Yes | — | Firebase project for auth |
| `GOOGLE_APPLICATION_CREDENTIALS` | No | — | Path to Firebase service account JSON (mapped to `/app/firebase-service-account.json` in Docker) |
| `SEARCH_ENGINE` | No | `fuzzy` (code) / `pg_native` (Docker) | `pg_native` (pg_trgm) or `fuzzy` (RapidFuzz) |
| `LOG_LEVEL` | No | `INFO` | Structured logging level |
| `CORS_ORIGINS` | No | `http://localhost:8000,http://localhost:8001` | Comma-separated allowed origins |
| `APP_ENV` | No | `development` | Environment name |
| `DEBUG` | No | `False` | Debug mode |

**Frontend** (`frontend/lib/config/constants.dart`):
- `apiBaseUrl`: Must match your machine's network IP for physical device testing (Android emulator uses `10.0.2.2`)

## Testing Notes

- **Never create a local Python venv** — backend tests must run in Docker (PostgreSQL UUID/JSONB types incompatible with SQLite)
- Backend container must be running (`docker-compose up`) before running `docker exec` test commands
- Backend uses real `todo_test` database, not mocks for DB layer
- Test UUIDs must be valid format (`"00000000-0000-0000-0000-000000000001"`), not arbitrary strings
- Frontend tests use `mocktail` + `ProviderContainer` with `MockApiService`
- Current counts: ~175 backend tests, ~342 frontend tests
