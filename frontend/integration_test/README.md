# Frontend E2E Integration Tests

## Prerequisites

1. **Android device/emulator connected** via USB or WiFi (`flutter devices` to verify)
2. **E2E backend running** with `APP_ENV=test` on a dedicated port (default: 8002)

## Backend Setup

The E2E tests need a backend that accepts the test auth token `test-token-e2e`. This is only enabled when `APP_ENV=test` — production and development backends reject it.

```bash
# Start E2E backend (port 8002, separate DB)
cd backend
WT_NAME=todo-fe-e2e WT_API_PORT=8002 WT_PG_PORT=5434 \
  APP_ENV=test \
  COMPOSE_PROJECT_NAME=todo-fe-e2e \
  docker compose -f docker-compose.worktree.yml up --build -d

# Apply migrations
docker exec todo-fe-e2e-backend alembic upgrade head

# Verify test auth works
curl -s http://localhost:8002/health
curl -s -H "Authorization: Bearer test-token-e2e" http://localhost:8002/api/tasks
```

## Running Tests

Find your Mac's local IP first (`ipconfig getifaddr en0`).

```bash
cd frontend

# Single test
flutter test integration_test/flows/auth_test.dart \
  -d <device-id> \
  --dart-define=TEST_MODE=true \
  --dart-define=API_BASE_URL=http://<mac-ip>:8002/api

# All tests (run one at a time for WiFi stability)
for f in integration_test/flows/*_test.dart; do
  flutter test "$f" -d <device-id> \
    --dart-define=TEST_MODE=true \
    --dart-define=API_BASE_URL=http://<mac-ip>:8002/api
done
```

Or use the helper script (emulator only, uses `10.0.2.2` loopback):
```bash
BACKEND_PORT=8002 ./run_e2e.sh
```

### Key dart-defines

| Flag | Purpose |
|------|---------|
| `TEST_MODE=true` | Skips Firebase init, bypasses `AuthGate` to go straight to `HomeScreen` |
| `API_BASE_URL=http://<ip>:8002/api` | Points app at E2E backend. Use `10.0.2.2` for emulator, Mac IP for physical device |

## Test Inventory

| File | What it tests | Needs backend? |
|------|---------------|----------------|
| `flows/auth_test.dart` | Login screen render, loading state, error state, sign-in button | No |
| `flows/create_task_test.dart` | Create task via keyboard input, verify in flat view | Yes |
| `flows/task_lifecycle_test.dart` | Create multiple tasks, verify persistence | Yes |
| `flows/navigation_test.dart` | Node/Flat/Calendar view switching | Yes (fetches tasks) |

## Security

Test auth is safe for three reasons:
1. Backend only accepts `test-token-e2e` when `APP_ENV=test` (`auth.py:46`)
2. The `/test/reset` endpoint returns 404 in production (`routers/test_utils.py:29`)
3. The E2E stack runs on a separate port with its own database — no shared state with dev/prod

## Troubleshooting

- **`WebSocketChannelException`**: WiFi debug connection is flaky. Run tests individually, not batched. USB is more stable.
- **`401 Invalid token`**: Backend isn't running with `APP_ENV=test`. Check with `docker exec todo-fe-e2e-backend env | grep APP_ENV`.
- **`connectionTimeout`**: Wrong `API_BASE_URL`. Physical devices can't reach `10.0.2.2` — use your Mac's network IP.
- **`ptt_button` not found**: Missing `--dart-define=TEST_MODE=true`. Without it, the app shows the login screen instead of HomeScreen.
- **Stale APK / duplicate entry**: Run `flutter clean && flutter pub get` then retry.

## Cleanup

```bash
# Stop E2E stack
COMPOSE_PROJECT_NAME=todo-fe-e2e docker compose -f backend/docker-compose.worktree.yml down -v
```
