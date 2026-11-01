# Todo Backend API

FastAPI backend for Amble, the AI-powered voice-first todo list app. Project overview: [`../README.md`](../README.md); detailed notes: [`../docs/NOTES.md`](../docs/NOTES.md).

## Features

- **Brain dump processing**: Gemini (`gemini-2.5-flash-lite`) turns a transcript into proposed actions (add, complete, edit, delete, breakdown); the client reviews them and submits the batch, which is applied in one transaction
- **Streaming speech-to-text**: `/ws/ramble` WebSocket relays audio to Sarvam AI `saaras:v3` (translate mode, so Hindi/Hinglish comes out as English)
- **Task matching**: PostgreSQL `pg_trgm` (or RapidFuzz) resolves spoken references to existing tasks
- **Hierarchical Task Management**: Unlimited-depth tree under 8 fixed domains (career, finance, health, relationships, growth, recreation, home, community)
- **Firebase Auth**: `/api` task, agent, category and account routes and the WebSocket require a Firebase ID token
- **PostgreSQL Database**: Async SQLAlchemy, Alembic migrations
- **Dockerized**: Postgres, Redis and the API run in containers

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Gemini API key from https://ai.google.dev/
- Sarvam AI API key
- A Firebase project and a service account JSON

### Setup

1. **Configure environment**:

   ```bash
   cp .env.example .env
   # edit .env: POSTGRES_PASSWORD, GEMINI_API_KEY, SARVAM_API_KEY, FIREBASE_PROJECT_ID
   cp /path/to/service-account.json firebase-service-account.json   # a real file, not a symlink
   ```

2. **Start the backend**:
   ```bash
   docker-compose up --build
   ```

   The container runs `alembic upgrade head` before starting uvicorn.

The backend will be available at:
- API: http://localhost:8001
- Docs: http://localhost:8001/docs (only when `DEBUG=True`)
- Health: http://localhost:8001/health

Postgres is on 127.0.0.1:5433 and Redis on 127.0.0.1:6379.

### Stopping

```bash
docker-compose down
```

To remove database data:
```bash
docker-compose down -v
```

## API Endpoints

Task, agent, category, notification, account and log routes need `Authorization: Bearer <Firebase ID token>`. The user is taken from the token; there is no `user_id` parameter.

### Agent API

#### POST /api/agent/braindump

Extract proposed actions from a transcript. Nothing is written to the database.

**Request**:
```json
{
  "transcription": "finished the tax forms, add buy milk",
  "category": null,
  "parent_id": null
}
```

**Response**: `{"success": true, "tasks": [<BrainDumpTaskProposal>...], "transcription": "...", "message": null}`. Each proposal has `action`, `content`, `category`, `parent_id`, `matched_task_id`, `changes`, confidences, `match_explanation` and `alternate_matches` (see `models/schemas.py`). Gibberish input returns `success: false` with no LLM call.

#### POST /api/agent/braindump/submit

Apply the reviewed proposals (`{"tasks": [...]}`, max 50) in one transaction. Both agent endpoints are rate limited to 10/minute.

### WebSocket

#### /ws/ramble

First message must be `{"type": "auth", "token": "<idToken>"}` within 5 s. Then `start`, base64 PCM16 16 kHz `audio` chunks, `stop`. The server sends `transcription` (accumulated text), `final_transcript` and `status` messages. Sessions are capped at 5 minutes.

### Tasks API

#### GET /api/tasks

List tasks with filters, sorting and pagination.

**Query Parameters** (all optional):
- `category`, `priority`, `status`, `tags` (comma-separated); `status` also accepts the computed `overdue` and `due_soon`
- `parent_id` (UUID or `null`)
- `created_at_gte/lte`, `updated_at_gte/lte`, `due_date_gte/lte`, `completed_at_gte/lte`
- `sort` (default `status:asc,due_date:asc,priority:desc,created_at:desc`)
- `limit` (default 50, max 100) and offset

**Example**:
```bash
curl -H "Authorization: Bearer $TOKEN" "http://localhost:8001/api/tasks?category=career&status=active"
```

#### GET /api/tasks/{task_id}

Get specific task.

#### POST /api/tasks

Create task manually (bypasses the agent). `task_id` is an optional client-generated UUID used for offline creates.

**Request**:
```json
{
  "title": "Buy groceries",
  "category": "home",
  "transcription": "buy groceries"
}
```

#### PATCH /api/tasks/{task_id}

Update task.

#### PUT /api/tasks/{task_id}/complete

Mark task as completed (cascades to active descendants).

#### PUT /api/tasks/{task_id}/archive, PUT /api/tasks/{task_id}/restore, GET /api/tasks/archived

Archive (soft delete, with descendants), restore, and list archived tasks. Archived tasks are purged after 30 days.

#### DELETE /api/tasks/{task_id}

Hard delete task and descendants.

#### Other

`GET /api/tasks/search`, `GET /api/tasks/stats`, `POST /api/tasks/bulk`, `/api/categories`, `/api/notifications/token` (FCM), `DELETE /api/account`, `POST /api/logs`, `GET /api/version`, `/metrics`.

## Development

### Project Structure

```
backend/
├── main.py                 # FastAPI app, middleware, background loops (archive purge, due reminders)
├── config.py              # Pydantic settings
├── auth.py                # Firebase ID token verification
├── rate_limit.py          # slowapi limiter
├── database.py            # SQLAlchemy setup
├── models/                # task, category, fcm_token, schemas
├── services/
│   ├── gemini_service.py      # Stage 1 / Stage 2 / subtask prompts
│   ├── agent_service.py       # Brain dump orchestration + batch submit
│   ├── ramble_service.py      # Sarvam streaming STT session
│   ├── task_service.py        # Tree operations, cascades, categories
│   ├── task_search_service.py # pg_trgm search
│   └── intent_prefilter.py    # Gibberish filter
├── routers/               # agent, ramble, tasks, categories, notifications, account, logs, test_utils
├── migrations/            # Alembic migrations
├── evaluation/            # Brain dump prompt eval harness and datasets
├── tests/                 # unit + e2e (+ performance)
└── docker-compose.yml     # Docker orchestration
```

### Running Locally

Use Docker. Tests and the app expect PostgreSQL (UUID/JSONB, `pg_trgm`), and the project's CLAUDE.md asks that no local venv be created. Code is volume-mounted (`.:/app`), so Python changes do not need a rebuild.

### Tests

```bash
docker exec todo-backend python -m pytest tests/ -v --ignore=tests/performance
```

### Database Migrations

Create new migration:
```bash
docker exec todo-backend alembic revision --autogenerate -m "description"
```

Apply migrations:
```bash
docker exec todo-backend alembic upgrade head
```

Rollback:
```bash
docker exec todo-backend alembic downgrade -1
```

## Testing with curl

### Test brain dump endpoint:
```bash
curl -X POST http://localhost:8001/api/agent/braindump \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"transcription": "Add buy groceries"}'
```

### Test tasks endpoint:
```bash
curl -H "Authorization: Bearer $TOKEN" "http://localhost:8001/api/tasks"
```

The HTTP seed scripts (`seed_tasks.*`, `seed_deep_tasks.*`) send no token and get 401s; `seed_realistic.py` and `seed_showcase.py` write straight to the database.

## Environment Variables

Set in `.env` (copied from `.env.example`), read by `docker-compose.yml` and `config.py`:

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Database credentials (compose builds `DATABASE_URL` from these) | `todo` / **REQUIRED** / `todo_db` |
| `GEMINI_API_KEY` | Google Gemini API key | **REQUIRED** |
| `SARVAM_API_KEY` | Sarvam AI API key | **REQUIRED** |
| `FIREBASE_PROJECT_ID` | Firebase project for auth | **REQUIRED** |
| `APP_ENV` | Environment (development/production) | development |
| `DEBUG` | Enable debug mode (also enables `/docs`) | False |
| `SEARCH_ENGINE` | `pg_native` (pg_trgm) or `fuzzy` (RapidFuzz) | `pg_native` in compose, `fuzzy` in code |
| `CORS_ORIGINS`, `LOG_LEVEL`, `SENTRY_DSN`, `FIREBASE_CREDENTIALS_JSON`, `ALLOW_TEST_TOKEN` | Optional | see `config.py` |

`GOOGLE_APPLICATION_CREDENTIALS` and `REDIS_URL` are set by `docker-compose.yml`.

## Architecture

### Action Types

The brain dump pipeline supports 5 actions:

1. **ADD**: Create new task (Stage 2 picks a parent within the domain)
2. **COMPLETE**: Mark task done (cascades to descendants)
3. **EDIT**: Modify task, including reparenting (old MOVE proposals are converted to EDIT)
4. **DELETE**: Hard delete task and its subtree
5. **BREAKDOWN**: Expanded server-side into ADD proposals for 4 to 6 subtasks

### Task Tree Structure

Tasks are organized hierarchically under 8 domains:

```
career
├── Project Alpha
│   ├── Backend API
│   └── Frontend UI
└── Meetings

home
└── Errands
    └── Shopping
```

## Troubleshooting

### Port already in use

The API maps to 8001, Postgres to 5433 and Redis to 6379. To change them, edit `ports` in `docker-compose.yml`, or use `docker-compose.worktree.yml` with `WT_API_PORT` / `WT_PG_PORT`.

### Database connection error

Check PostgreSQL is running:
```bash
docker-compose ps
```

View logs:
```bash
docker-compose logs postgres
docker-compose logs backend
```

### Gemini / Sarvam API errors

Verify the keys are set in `.env`:
```bash
grep -E "GEMINI_API_KEY|SARVAM_API_KEY" .env
```

Check quota at: https://ai.google.dev/

## License

No `LICENSE` file is included in the repo yet.
