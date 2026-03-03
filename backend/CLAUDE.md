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
# All tests (154 tests, uses real PostgreSQL `todo_test` DB)
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

### Intent Detection Eval (run after prompt changes)
```bash
docker exec todo-backend python evaluation/run_eval.py                          # Full run (65 cases, ~90s)
docker exec todo-backend python evaluation/run_eval.py --filter-category ADD    # One intent type
docker exec todo-backend python evaluation/run_eval.py --filter-id add_01       # Single case
docker exec todo-backend python evaluation/run_eval.py --no-llm                 # Dry-run (harness only)
# Results saved to evaluation/results/ (JSON, auto-timestamped)
# Baseline: 58/65 (89.2%) — 2026-02-25
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
2. `TaskService.build_full_tree_context()` — builds indented tree string for AI context (compressed when `SEARCH_ENGINE=pg_native` for ~56% token savings)
3. `GeminiService.detect_intent()` — returns intent (ADD/COMPLETE/DELETE/EDIT/MOVE/QUERY/BREAKDOWN) + params. When `pg_native`: text queries only, no UUIDs. When `fuzzy`: UUIDs + matchedTasks.
4. Confidence check (rejects < 0.6)
5. Task resolution: `pg_native` → `TaskSearchService` (pg_trgm trigram search in PG). `fuzzy` → Gemini IDs + RapidFuzz fallback.
6. Intent handler executes action, returns `AgentResponse`
7. Ambiguous commands return `type="question"` with matches → client calls `POST /api/agent/resolve`
8. Unknown category → returns `select_category` question → user picks → `POST /api/agent/resolve`

### Brain Dump Pipeline (`POST /api/agent/braindump`)
Two-step proposal-then-commit flow for multi-task voice input:
1. Client streams audio via WebSocket (`/ws/ramble`) → Gemini Live transcribes in real-time
2. Client sends transcript to `/api/agent/braindump` → `GeminiService.detect_brain_dump()` extracts multiple tasks
3. Returns `BrainDumpResponse` with `List[BrainDumpTaskProposal]` (not yet created)
4. User reviews/edits proposals in UI → submits via `POST /api/agent/braindump/submit`
5. `AgentService.submit_brain_dump()` batch-creates tasks

### Key Layers
- **`routers/`** — API endpoints. Services are instantiated per-request (no DI container). DB session via `Depends(get_db)`.
- **`services/task_service.py`** — All task CRUD, tree operations (`_get_all_descendants` recursive), completion cascading, category management (5-category limit).
- **`services/agent_service.py`** — Voice command orchestrator. Uses deterministic UUIDs for root categories (`uuid5` with fixed namespace).
- **`services/gemini_service.py`** — Gemini 2.5 Flash Lite integration. Sync API calls wrapped in async service. `detect_brain_dump()` extracts multiple tasks from free-form text.
- **`services/ramble_service.py`** — Gemini Live API streaming transcription. `RambleSession` manages WebSocket connection for real-time audio→text. Uses `google-genai` SDK (separate from `google-generativeai` used elsewhere).
- **`services/query_builder.py`** — Dynamic SQLAlchemy query construction with multi-field filtering/sorting/pagination.
- **`services/task_search_service.py`** — PG-native task search using `pg_trgm` trigram similarity. Weighted: title 70% + description 30%. `resolve_single()` returns confident match or ambiguous candidates.
- **`utils/fuzzy_matcher.py`** — RapidFuzz matching (max of `token_set_ratio`, `partial_ratio`, stripped ratio). Weighted: title 70%, description 30%. Threshold: 60%. Near-exact matches (≥90) suppress weaker results. Used when `SEARCH_ENGINE=fuzzy`.
- **`utils/date_parser.py`** — Flexible date parsing ("today", "next monday", ISO strings) → timezone-aware UTC.

### Database
- **Two tables**: `tasks` and `categories`
- **`tasks`**: Self-referencing `parent_id` FK (SET NULL on delete), `category_id` FK to `categories` (SET NULL on delete)
- **`categories`**: Persistent domain definitions (id, user_id, name, position). Unique constraint on `(user_id, name)`.
- **Key columns**: UUID pk, JSONB `ai_placement_json`, ARRAY `tags`, computed `overdue` status (in Pydantic, not DB)
- **Statuses**: `active` and `completed` only (no `archived`)
- **Indexes**: `(user_id, category)`, `(user_id, category_id)`, `(user_id, status)`, `parent_id`, `created_at`, `title` (GIN trigram), `description` (GIN trigram)

### Key Patterns

**Session Management (`get_db`):** Auto-commits on success, auto-rollbacks on exception. Services call `flush()` for ID generation mid-transaction, `commit()` for final persistence, `refresh()` to reload from DB.

**Multi-Intent Processing:** `detect_intent()` can return multiple intents. `AgentService` executes them sequentially, stops on first `type="question"`, and aggregates successes into one response.

**Ambiguous Command Resolution:** Fuzzy search returns 0 → error; 1 → execute; >1 → return `type="question"` with matches for client disambiguation via `/api/agent/resolve`.

**Category Auto-Creation:** `_resolve_category_id()` auto-creates categories from the 5 valid domains on first use. Returns `None` for invalid names. Hard limit enforced in both `TaskService` and `AgentService`.

**Tree Safety:** `update_task()` guards against circular references (moving task under itself or its descendants). `_get_all_descendants()` uses BFS with cycle detection. `_activate_ancestor_chain()` walks up parent chain to reactivate completed ancestors when a child becomes active.

**Error Convention:** Services raise `ValueError` for business logic errors → routers catch and return `HTTPException(400)`. Pydantic validation → 422 automatic. Low confidence → `AgentResponse(success=False, type="error")`.

**WebSocket Ramble:** 5-minute session limit with 30-second heartbeats. Client sends `start` → streams base64 PCM `audio` chunks → sends `stop`. Server emits real-time `transcription` events.

### Testing Patterns

- **Test helpers** (`tests/helpers.py`): `make_task()` and `make_task_tree()` factories for creating test data
- **Mock pattern**: `_intent()` helper builds Gemini response format; `mock_gemini.detect_intent = AsyncMock(return_value=_intent("ADD", title="x", category="work"))`
- **Dependency override**: API tests swap `get_db` via `app.dependency_overrides[get_db]` to share test session
- **Cleanup**: `conftest.py` deletes all tasks/categories after each test (real DB, not mocks)

## Environment Variables

All config from Docker environment (no `.env` file). Managed via Pydantic `Settings` in `config.py`:

| Variable | Required | Default |
|---|---|---|
| `DATABASE_URL` | Yes | — |
| `GEMINI_API_KEY` | Yes | — |
| `APP_ENV` | No | `development` |
| `DEBUG` | No | `True` |
| `SEARCH_ENGINE` | No | `fuzzy` (`pg_native` or `fuzzy`) |

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
| `POST` | `/api/agent/braindump` | Extract task proposals from transcript |
| `POST` | `/api/agent/braindump/submit` | Commit reviewed task proposals |
| `WebSocket` | `/ws/ramble` | Stream audio for real-time transcription |
| `GET` | `/health` | Health check |
