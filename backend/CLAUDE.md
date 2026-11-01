# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

FastAPI backend for a voice-first AI-powered hierarchical todo app. Streams voice to Sarvam AI (`saaras:v3`, translate mode) for speech-to-text, uses Google Gemini (`gemini-2.5-flash-lite`) to turn the transcript into task actions, and manages tasks in a PostgreSQL tree structure.

## Commands

### Build & Run
```bash
docker-compose up --build          # Start everything (API on :8001, Postgres on 127.0.0.1:5433, Redis on 127.0.0.1:6379)
docker-compose down                # Stop
```

### Testing (always inside Docker — never create local venv)
```bash
# All tests (uses real PostgreSQL `todo_test` DB)
docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance

# Single test file
docker exec todo-backend python -m pytest tests/test_brain_dump.py -v

# Single test
docker exec todo-backend python -m pytest tests/test_brain_dump.py::TestProcessBrainDump::test_gibberish_returns_empty_proposals -v

# Performance benchmarks (separate)
docker exec todo-backend python tests/performance/test_agent_performance.py
```

### Database Migrations
```bash
docker exec todo-backend alembic upgrade head           # Apply all
docker exec todo-backend alembic revision --autogenerate -m "description"  # Create new
docker exec todo-backend alembic downgrade -1           # Rollback one
```

### Brain Dump Action Detection Eval (run after prompt changes)
```bash
docker exec todo-backend python evaluation/run_eval.py                          # Full run (evaluation/eval_config.json, 137 cases)
docker exec todo-backend python evaluation/run_eval.py --filter-category add    # One action type
docker exec todo-backend python evaluation/run_eval.py --filter-id add_01       # Single case
docker exec todo-backend python evaluation/run_eval.py --no-llm                 # Dry-run (harness only)
docker exec todo-backend python evaluation/run_eval.py --no-prefilter           # Skip pre-filter, LLM-only
docker exec todo-backend python evaluation/run_eval.py --eval-config evaluation/eval_smoke.json  # Other datasets: eval_smoke.json (56), eval_realworld.json (553)
docker exec todo-backend python evaluation/run_eval.py --with-judge --html   # LLM judge + HTML report
# Results saved to evaluation/results/ (JSON, auto-timestamped)
```

## Architecture

### Request Flow
```
Client → FastAPI Router → Service → SQLAlchemy AsyncSession → PostgreSQL
                            ↕
                      GeminiService (AI)
```

### Brain Dump Pipeline (`POST /api/agent/braindump`)
Unified proposal-then-commit flow for all input (keyboard text and voice):
0. `intent_prefilter.prefilter()` — catches gibberish before any Gemini call
1. `TaskService.build_full_tree_context()` — always builds full indented tree string for AI context (compressed tree was removed — full tree works better for LLM; the unused `_build_compressed_tree` is still in `task_service.py`)
2. Stage 1: `GeminiService.detect_brain_dump()` — extracts actions (add/complete/edit/delete/breakdown) with `actionConfidence` and `domainConfidence`
3. Stage 2: `GeminiService.place_in_subtree()` — one call per ADD (up to 5 in parallel) picks a parent from that domain's subtree only
4. Dedupe, drop proposals with `min(actionConfidence, domainConfidence) < 0.6`, resolve complete/edit/delete/breakdown references to the top `_search_tasks()` hit (no hit → dropped), expand BREAKDOWN into ADD proposals via `generate_subtasks()`, parse dates
5. Returns `BrainDumpResponse` with `List[BrainDumpTaskProposal]` (not yet created)
6. User reviews/edits proposals in RambleScreen → submits via `POST /api/agent/braindump/submit`
7. `AgentService.submit_brain_dump()` batch-creates/updates/deletes tasks in one transaction (any failure rolls back the batch). Note: this path does not check that `matched_task_id`/`parent_id` belong to the caller.

For voice input: Client streams audio via WebSocket (`/ws/ramble`) → Sarvam AI (`saaras:v3`, `translate` mode) transcribes to English → then same pipeline above.

### Key Layers
- **`routers/`** — API endpoints. Services are instantiated per-request (no DI container). DB session via `Depends(get_db)`.
- **`services/task_service.py`** — All task CRUD, tree operations (`_get_all_descendants` recursive), completion cascading, category management (8-category limit).
- **`services/intent_prefilter.py`** — Rule-based pre-filter: gibberish detection (vowel ratio + consonant clusters). Runs before LLM to save API calls on nonsense input.
- **`services/agent_service.py`** — Brain dump orchestrator. `process_brain_dump()` extracts proposals, `submit_brain_dump()` executes them.
- **`services/gemini_service.py`** — Gemini 2.5 Flash Lite integration via the `google-genai` async client (`client.aio`), with timeout and retry/backoff. `detect_brain_dump()` (Stage 1) extracts task actions from free-form text, `place_in_subtree()` (Stage 2) picks parents, `generate_subtasks()` for breakdown action.
- **`services/ramble_service.py`** — Sarvam AI streaming STT (`saaras:v3`). `RambleSession` manages WebSocket connection for real-time audio→text. Uses `sarvamai` SDK with `translate` mode — outputs English directly (no separate transliteration step).
- **`services/query_builder.py`** — Dynamic SQLAlchemy query construction with multi-field filtering/sorting/pagination.
- **`services/task_search_service.py`** — PG-native task search using `pg_trgm` trigram similarity. Weighted: title 70% + description 30%. `resolve_single()` returns confident match or ambiguous candidates, but `AgentService` does not use it (it takes the top `search()` hit).
- **`utils/fuzzy_matcher.py`** — RapidFuzz matching (max of `token_set_ratio`, `partial_ratio`, stripped ratio). Weighted: title 70%, description 30%. Threshold: 60%. Near-exact matches (≥90) suppress weaker results. Used when `SEARCH_ENGINE=fuzzy`.
- **`utils/date_parser.py`** — Flexible date parsing ("today", "next monday", ISO strings) → timezone-aware UTC.

### Database
- **Three tables**: `tasks`, `categories`, `fcm_tokens` (per-device push tokens)
- **`tasks`**: Self-referencing `parent_id` FK (SET NULL on delete), `category_id` FK to `categories` (SET NULL on delete)
- **`categories`**: Persistent domain definitions (id, user_id, name, position). Unique constraint on `(user_id, name)`.
- **Key columns**: UUID pk, JSONB `ai_placement_json`, ARRAY `tags`, computed `overdue` status (never stored; computed as `status == active && due_date < now` in `QueryBuilder` filters/sort and the stats query)
- **Statuses**: `active`, `completed`, `archived` (check constraint). Archived tasks are purged after 30 days by a background loop in `main.py`
- **Indexes**: `(user_id, category)`, `(user_id, category_id)`, `(user_id, status)`, `parent_id`, `created_at`, `(user_id, due_date)`, `title` (GIN trigram), `description` (GIN trigram)

### Key Patterns

**Session Management (`get_db`):** Auto-commits on success, auto-rollbacks on exception. Services call `flush()` for ID generation mid-transaction, `commit()` for final persistence, `refresh()` to reload from DB.

**Multi-Action Processing:** `detect_brain_dump()` returns multiple task proposals. `submit_brain_dump()` executes them via `_execute_action()` (add/complete/edit/delete; legacy `move` is converted to `edit` with `changes.parent_id`; breakdown is already expanded to ADDs before reaching the client).

**Category Auto-Creation:** `_resolve_category_id()` auto-creates categories on first use. 8 default domains: career, finance, health, relationships, growth, recreation, home, community. `max_categories: 8` enforced in `TaskService` via settings; the `AgentService` ADD path hardcodes `8` and falls back to `home` when full.

**Tree Safety:** `update_task()` guards against circular references (moving task under itself or its descendants). `_get_all_descendants()` uses BFS with cycle detection. `_activate_ancestor_chain()` walks up parent chain to reactivate completed ancestors when a child becomes active.

**Search Dispatch:** `AgentService._search_tasks()` is the single entry point for task matching. Delegates to `TaskSearchService` (pg_trgm) or `FuzzyMatcher` based on `SEARCH_ENGINE` setting. Returns `(match, confidence, alternates)`.

**Error Convention:** Services raise `ValueError` for business logic errors → routers catch and return `HTTPException(400)`. Pydantic validation → 422 automatic. Gibberish input → `BrainDumpResponse(success=False, tasks=[])`.

**WebSocket Ramble:** 5-minute session limit with a `time_remaining` status every 30 seconds. First message must be `{"type":"auth","token":...}` within 5 s, then the client sends `start` → streams base64 PCM `audio` chunks → sends `stop`. Server emits real-time `transcription` events. Uses Sarvam AI `saaras:v3` in `translate` mode — speech in any supported language is output as English text (no separate transliteration).

### Testing Patterns

- **Test helpers** (`tests/helpers.py`): `make_task()` and `make_task_tree()` factories for creating test data
- **Mock pattern**: `mock_gemini.detect_brain_dump = AsyncMock(return_value=[{"content": "Buy groceries", "category": "home", "confidence": 0.9}])`
- **Dependency override**: API tests swap `get_db` via `app.dependency_overrides[get_db]` to share test session
- **Cleanup**: `conftest.py` deletes all tasks/categories after each test (real DB, not mocks)

## Authentication & Security

- **Firebase Auth**: `auth.py` — `get_current_user` dependency verifies Firebase ID tokens via `firebase-admin` SDK. Returns user UID. Used as `Depends(get_current_user)` on protected routes.
- **Rate limiting**: `rate_limit.py` — `slowapi` limiter keyed by Bearer token (falls back to client IP). Applied via `@limiter.limit()` decorators on routes.
- **Structured logging**: `structured_logging.py` — `structlog` JSON logs with context vars (`trace_id_var`, `user_id_var`, `session_id_var`). Use `get_logger(__name__)` in all modules.
- **Request logging**: `middleware/request_logging.py` — logs every request/response with trace ID, duration, status code. Propagates `X-Request-Id` and `X-Session-Id` headers.

## Environment Variables

Config loaded from `.env` file via `docker-compose.yml` `env_file: .env`. Managed via Pydantic `Settings` in `config.py`:

| Variable | Required | Default |
|---|---|---|
| `DATABASE_URL` | Yes | — |
| `GEMINI_API_KEY` | Yes | — |
| `SARVAM_API_KEY` | Yes | — |
| `FIREBASE_PROJECT_ID` | Yes | — |
| `GOOGLE_APPLICATION_CREDENTIALS` | No | — |
| `APP_ENV` | No | `development` |
| `DEBUG` | No | `False` |
| `SEARCH_ENGINE` | No | `fuzzy` (code), `pg_native` (Docker compose) |
| `LOG_LEVEL` | No | `INFO` |
| `CORS_ORIGINS` | No | `http://localhost:8000,http://localhost:8001` |
| `MAX_CATEGORIES` | No | `8` |
| `FIREBASE_CREDENTIALS_JSON` | No | — (base64 service account, used on Render) |
| `REDIS_URL` | No | — (enables the notification-loop lock) |
| `SENTRY_DSN` | No | — |
| `ALLOW_TEST_TOKEN` | No | `False` (enables `test-token-e2e` outside production) |

Also: Gemini timeout/retry knobs, DB pool knobs, `MAX_WS_CONNECTIONS_PER_USER` (3), `NOTIFICATION_CHECK_INTERVAL_MINUTES` (15), `TRUSTED_PROXY_COUNT`. See `config.py`.

## API Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/tasks` | List tasks (advanced filtering/sorting/pagination) |
| `GET` | `/api/tasks/{id}` | Get single task |
| `POST` | `/api/tasks` | Create task |
| `PATCH` | `/api/tasks/{id}` | Update task |
| `PUT` | `/api/tasks/{id}/complete` | Complete task (cascades to children) |
| `PUT` | `/api/tasks/{id}/archive` | Archive task (soft delete, cascades) |
| `PUT` | `/api/tasks/{id}/restore` | Restore archived task |
| `GET` | `/api/tasks/archived` | List archived tasks |
| `GET` | `/api/tasks/search` | Search tasks |
| `GET` | `/api/tasks/stats` | Task counts (incl. computed overdue) |
| `POST` | `/api/tasks/bulk` | Bulk actions |
| `DELETE` | `/api/tasks/{id}` | Hard delete task + descendants |
| `GET`/`POST`/`DELETE` | `/api/categories` | Categories |
| `POST`/`DELETE` | `/api/notifications/token` | FCM device token |
| `DELETE` | `/api/account` | Delete account and data |
| `POST` | `/api/logs` | Client log ingest |
| `DELETE` | `/api/test/reset` | Test reset (non-production only) |
| `POST` | `/api/agent/braindump` | Extract task proposals from transcript |
| `POST` | `/api/agent/braindump/submit` | Commit reviewed task proposals |
| `WebSocket` | `/ws/ramble` | Stream audio for real-time transcription |
| `GET` | `/health` | Health check |
| `GET` | `/api/version`, `/metrics` | Version, Prometheus metrics |
