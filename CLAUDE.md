# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice-first AI-powered hierarchical todo app. Flutter mobile frontend communicates with a FastAPI backend via REST API. Users speak voice commands, backend AI (Gemini) transcribes, detects intent (ADD/COMPLETE/EDIT/DELETE/MOVE/QUERY/BREAKDOWN), and executes against a PostgreSQL database. Tasks are organized into 5 domains (Work, Personal, Health, Learning, Projects) with unlimited tree depth.

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
docker exec todo-backend python -m pytest tests/test_agent_service.py -v                     # Single file
docker exec todo-backend python -m pytest tests/test_agent_service.py::TestHandleAdd::test_add_task_basic -v  # Single test
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

# Intent detection eval (65 cases, ~90s with LLM)
docker exec todo-backend python evaluation/run_eval.py                    # Full run
docker exec todo-backend python evaluation/run_eval.py --filter-id add_01 # Single case
docker exec todo-backend python evaluation/run_eval.py --no-llm          # Dry-run (harness only)
```

## Architecture

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│  Flutter Frontend    │  REST   │  FastAPI Backend                 │
│  (Riverpod state)    │ ◄─────► │  (async Python)                  │
│                      │         │                                  │
│  TaskStoreNotifier   │  WS     │  /api/agent/process  ← voice     │
│  ├── allTasks        │ ◄─────► │  /api/agent/resolve  ← disambig  │
│  ├── byCategory      │         │  /api/agent/braindump ← ramble   │
│  ├── byId            │         │  /ws/ramble           ← stream   │
│  ├── children        │         │  /api/tasks/*         ← CRUD     │
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

### Two Voice Input Modes

1. **Single Command** (tap mic): Record → upload .m4a → `/api/agent/process` → single intent executed
2. **Brain Dump / Ramble** (long-press mic): Stream PCM audio via `/ws/ramble` → Gemini Live transcribes in real-time → user reviews transcript → `/api/agent/braindump` extracts multiple task proposals → user reviews/edits → `/api/agent/braindump/submit` creates tasks in batch

### Detailed Guides

- **Backend**: See [`backend/CLAUDE.md`](backend/CLAUDE.md) — voice command pipeline, services, database schema, API endpoints, testing setup
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

### 5-Domain Limit
Categories (Work, Personal, Health, Learning, Projects) are enforced in `agent_service.py`. The frontend defines them in `AppConstants.domainNames`. Adding a 6th is blocked.

## Environment

**Backend** (Docker env in `docker-compose.yml`):
- `DATABASE_URL`: `postgresql+asyncpg://todo:todo123@postgres:5432/todo_db`
- `GEMINI_API_KEY`: Google Gemini API key
- `SEARCH_ENGINE`: `pg_native` (pg_trgm trigram search) or `fuzzy` (RapidFuzz). Default: `fuzzy`

**Frontend** (`frontend/lib/config/constants.dart`):
- `apiBaseUrl`: Must match your machine's network IP for physical device testing (Android emulator uses `10.0.2.2`)
- `defaultUserId`: `default-user` (no auth in MVP)

## Testing Notes

- **Never create a local Python venv** — backend tests must run in Docker (PostgreSQL UUID/JSONB types incompatible with SQLite)
- Backend container must be running (`docker-compose up`) before running `docker exec` test commands
- Backend uses real `todo_test` database, not mocks for DB layer
- Test UUIDs must be valid format (`"00000000-0000-0000-0000-000000000001"`), not arbitrary strings
- Frontend tests use `mocktail` + `ProviderContainer` with `MockApiService`
