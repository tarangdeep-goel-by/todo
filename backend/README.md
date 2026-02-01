# Todo Backend API

FastAPI backend for AI-powered voice-first todo list app.

## Features

- **Voice Command Processing**: Detects user intent and executes actions
- **AI-Powered Categorization**: Automatically categorizes tasks using Google Gemini
- **Hierarchical Task Management**: Tree-based task organization
- **PostgreSQL Database**: Production-ready with async support
- **Dockerized**: Everything runs in containers

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Gemini API key from https://ai.google.dev/

### Setup

1. **Add your Gemini API key**:

   Edit `docker-compose.yml` and replace `YOUR_GEMINI_API_KEY_HERE` with your actual API key:

   ```yaml
   environment:
     GEMINI_API_KEY: AIzaSy...your_actual_key_here
   ```

2. **Start the backend**:
   ```bash
   docker-compose up --build
   ```

The backend will be available at:
- API: http://localhost:8000
- Docs: http://localhost:8000/docs
- Health: http://localhost:8000/health

### Stopping

```bash
docker-compose down
```

To remove database data:
```bash
docker-compose down -v
```

## API Endpoints

### Agent API

#### POST /api/agent/process

Process voice command and execute intent.

**Request**:
```json
{
  "transcription": "Add buy groceries",
  "user_id": "default-user"
}
```

**Response**:
```json
{
  "success": true,
  "message": "Created task 'buy groceries' in Personal",
  "type": "confirmation",
  "data": {
    "task_id": "uuid...",
    "title": "buy groceries",
    "category": "personal",
    "reasoning": "Groceries are personal errands"
  }
}
```

### Tasks API

#### GET /api/tasks

List tasks with filters.

**Query Parameters**:
- `user_id` (required)
- `category` (optional): work/personal
- `status` (optional): active/completed/archived
- `parent_id` (optional): Filter by parent

**Example**:
```bash
curl "http://localhost:8000/api/tasks?user_id=default-user&category=work"
```

#### GET /api/tasks/{task_id}

Get specific task.

#### POST /api/tasks

Create task manually (bypasses agent).

**Request**:
```json
{
  "user_id": "default-user",
  "title": "Buy groceries",
  "category": "personal",
  "transcription": "buy groceries"
}
```

#### PATCH /api/tasks/{task_id}

Update task.

#### PUT /api/tasks/{task_id}/complete

Mark task as completed.

#### DELETE /api/tasks/{task_id}

Archive task and descendants.

## Development

### Project Structure

```
backend/
├── main.py                 # FastAPI app entry point
├── config.py              # Environment configuration
├── database.py            # SQLAlchemy setup
├── models/
│   ├── task.py           # SQLAlchemy model
│   └── schemas.py        # Pydantic schemas
├── services/
│   ├── gemini_service.py # Gemini AI integration
│   ├── agent_service.py  # Intent detection + execution
│   └── task_service.py   # Task CRUD operations
├── routers/
│   ├── agent.py          # Agent endpoints
│   └── tasks.py          # Task endpoints
├── migrations/           # Alembic migrations
└── docker-compose.yml    # Docker orchestration
```

### Running Locally (without Docker)

1. **Create virtual environment**:
   ```bash
   python -m venv venv
   source venv/bin/activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Setup PostgreSQL** (manually or with Docker):
   ```bash
   docker run -d --name todo-postgres \
     -e POSTGRES_USER=todo \
     -e POSTGRES_PASSWORD=todo123 \
     -e POSTGRES_DB=todo_db \
     -p 5432:5432 \
     postgres:15-alpine
   ```

4. **Set environment variables**:
   ```bash
   export DATABASE_URL="postgresql+asyncpg://todo:todo123@localhost:5432/todo_db"
   export GEMINI_API_KEY="your_api_key_here"
   export APP_ENV="development"
   export DEBUG="True"
   ```

5. **Run migrations**:
   ```bash
   alembic upgrade head
   ```

6. **Start server**:
   ```bash
   uvicorn main:app --reload
   ```

### Database Migrations

Create new migration:
```bash
alembic revision --autogenerate -m "description"
```

Apply migrations:
```bash
alembic upgrade head
```

Rollback:
```bash
alembic downgrade -1
```

## Testing with curl

### Test agent endpoint:
```bash
curl -X POST http://localhost:8000/api/agent/process \
  -H "Content-Type: application/json" \
  -d '{
    "transcription": "Add buy groceries to shopping list",
    "user_id": "default-user"
  }'
```

### Test tasks endpoint:
```bash
curl "http://localhost:8000/api/tasks?user_id=default-user"
```

## Environment Variables

All environment variables are configured in `docker-compose.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `GEMINI_API_KEY` | Google Gemini API key | **REQUIRED** - Set in docker-compose.yml |
| `DATABASE_URL` | PostgreSQL connection URL | Auto-configured in docker-compose.yml |
| `APP_ENV` | Environment (development/production) | development |
| `DEBUG` | Enable debug mode | True |

**Note**: No `.env` file is used. All configuration is in `docker-compose.yml`.

## Architecture

### Intent Types

The agent supports 6 intent types:

1. **ADD**: Create new task
2. **COMPLETE**: Mark task done
3. **DELETE**: Archive task
4. **EDIT**: Modify task
5. **QUERY**: List tasks
6. **UNKNOWN**: Unclear intent

### Task Tree Structure

Tasks are organized hierarchically:

```
Work (root-work)
├── Project Alpha
│   ├── Backend API
│   └── Frontend UI
└── Meetings

Personal (root-personal)
├── Home
└── Errands
    └── Shopping
```

## Troubleshooting

### Port already in use

If port 8000 or 5432 is in use, edit `docker-compose.yml`:
```yaml
ports:
  - "8001:8000"  # Change to different port
```

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

### Gemini API errors

Verify API key is set in docker-compose.yml:
```bash
grep GEMINI_API_KEY docker-compose.yml
```

Make sure it's not `YOUR_GEMINI_API_KEY_HERE` - replace with your actual key.

Check quota at: https://ai.google.dev/

## License

MIT
