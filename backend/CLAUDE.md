# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FastAPI backend for a voice-first AI-powered hierarchical todo app. Processes voice commands via Google Gemini (intent detection + transcription refinement), manages tasks in a PostgreSQL tree structure.

## Commands

### Build & Run
```bash
docker-compose up --build          # Start everything (API on :8001, Postgres on :5433)
docker-compose down                # Stop
```

### Testing (always inside Docker — never create local venv)
```bash
# All tests (100 tests, uses real PostgreSQL `todo_test` DB)
docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance

# Single test file
docker exec todo-backend python -m pytest tests/test_agent_service.py -v

# Single test
docker exec todo-backend python -m pytest tests/test_agent_service.py::TestHandleAdd::test_add_task_basic -v

# Performance benchmarks (separate)
docker exec todo-backend python tests/performance/test_agent_performance.py
```

### Database Migrations
```bash
docker exec todo-backend alembic upgrade head           # Apply all
docker exec todo-backend alembic revision --autogenerate -m "description"  # Create new
docker exec todo-backend alembic downgrade -1           # Rollback one
```

## Architecture

### Request Flow
```
Client → FastAPI Router → Service → SQLAlchemy AsyncSession → PostgreSQL
                            ↕
                      GeminiService (AI)
```

### Voice Command Pipeline (`POST /api/agent/process`)
1. `GeminiService.refine_transcription()` — cleans up raw transcript
2. `TaskService.build_full_tree_context()` — builds indented tree string for AI context
3. `GeminiService.detect_intent()` — returns intent (ADD/COMPLETE/DELETE/EDIT/MOVE/QUERY) + params
4. Confidence check (rejects < 0.6)
5. Intent handler executes action, returns `AgentResponse`
6. Ambiguous commands return `type="question"` with matches → client calls `POST /api/agent/resolve`

### Key Layers
- **`routers/`** — API endpoints. Services are instantiated per-request (no DI container). DB session via `Depends(get_db)`.
- **`services/task_service.py`** — All task CRUD, tree operations (`_get_all_descendants` recursive), completion cascading, category management (5-category limit).
- **`services/agent_service.py`** — Voice command orchestrator. Uses deterministic UUIDs for root categories (`uuid5` with fixed namespace).
- **`services/gemini_service.py`** — Gemini 2.5 Flash Lite integration. Sync API calls wrapped in async service.
- **`services/query_builder.py`** — Dynamic SQLAlchemy query construction with multi-field filtering/sorting/pagination.
- **`utils/fuzzy_matcher.py`** — RapidFuzz `token_set_ratio` matching (70% threshold, weighted: title 60%, description 30%, tags 10%).
- **`utils/date_parser.py`** — Flexible date parsing ("today", "next monday", ISO strings) → timezone-aware UTC.

### Database
- **Single table**: `tasks` with self-referencing `parent_id` FK (SET NULL on delete)
- **Key columns**: UUID pk, JSONB `ai_placement_json`, ARRAY `tags`, computed `overdue` status (in Pydantic, not DB)
- **Statuses**: `active` and `completed` only (no `archived`)
- **Indexes**: `(user_id, category)`, `(user_id, status)`, `parent_id`, `created_at`
- **4 migrations** in `migrations/versions/`

### Testing Setup
- Tests use real PostgreSQL (`todo_test` DB), not SQLite — UUID and JSONB types require it
- `conftest.py`: creates `todo_test` DB once, recreates tables per engine fixture, cleans `tasks` table after each test
- `GeminiService` is always mocked (`AsyncMock` with passthrough `refine_transcription`)
- API tests use `httpx.AsyncClient` with `ASGITransport` and FastAPI dependency overrides

## Environment Variables

All config from Docker environment (no `.env` file). Managed via Pydantic `Settings` in `config.py`:

| Variable | Required | Default |
|---|---|---|
| `DATABASE_URL` | Yes | — |
| `GEMINI_API_KEY` | Yes | — |
| `APP_ENV` | No | `development` |
| `DEBUG` | No | `True` |

## API Endpoints

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/agent/process` | Process voice command |
| `POST` | `/api/agent/resolve` | Resolve ambiguous command |
| `GET` | `/api/tasks` | List tasks (advanced filtering/sorting/pagination) |
| `GET` | `/api/tasks/{id}` | Get single task |
| `POST` | `/api/tasks` | Create task |
| `PATCH` | `/api/tasks/{id}` | Update task |
| `PUT` | `/api/tasks/{id}/complete` | Complete task (cascades to children) |
| `DELETE` | `/api/tasks/{id}` | Hard delete task + descendants |
| `GET` | `/health` | Health check |
