# Security Hardening — Execution Plan

**Parent:** [security-audit-2026-03-05.md](security-audit-2026-03-05.md)
**Branch:** `feat/security-hardening`

---

## Phase 1: Critical — Ship Blockers

> Goal: Eliminate all CRITICAL findings. No deploy without these.

### Task 1.1: Secrets Management
**Fixes:** C1, C3, C7 (partial)
**Files:** `backend/.env`, `backend/docker-compose.yml`, `backend/config.py`, `.gitignore`
**Steps:**
1. Create `backend/.env.example` with placeholder values (no real secrets)
2. Update `docker-compose.yml` to use `${VAR}` substitution for:
   - `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DATABASE_URL`
   - `GEMINI_API_KEY`, `SARVAM_API_KEY`
   - `FIREBASE_PROJECT_ID`
3. Add `env_file: .env` to docker-compose services
4. Verify `.env` is in `.gitignore` (already listed — confirm enforced)
5. Remove hardcoded secrets from `docker-compose.yml`
6. Rotate all compromised keys: Gemini, Sarvam AI, Firebase
**Verify:** `docker-compose up --build` works with `.env` file, fails without it
**Tests:** Existing backend tests pass via `docker exec`

### Task 1.2: CORS Lockdown
**Fixes:** C2
**File:** `backend/main.py:26-32`
**Steps:**
1. Add `CORS_ORIGINS` to `config.py` Settings (comma-separated string, default `http://localhost:8000`)
2. Replace `allow_origins=["*"]` with `allow_origins=settings.cors_origins.split(",")`
3. Set `allow_credentials=False` (Flutter app uses Authorization header, not cookies)
4. Restrict `allow_methods` to `["GET","POST","PATCH","PUT","DELETE"]`
5. Restrict `allow_headers` to `["Authorization","Content-Type"]`
**Verify:** `curl -H "Origin: http://evil.com" -I http://localhost:8001/health` returns no CORS headers
**Tests:** Existing tests pass (no CORS dependency in test client)

### Task 1.3: Input Validation Hardening
**Fixes:** C5
**File:** `backend/models/schemas.py`
**Steps:**
1. Add `PriorityEnum(str, Enum)` with values `high`, `medium`, `low`
2. Update all `priority` fields to use `Optional[PriorityEnum]`
3. Add `max_length=5000` to all `description` fields
4. Add `max_length=500` to `content` in `BrainDumpTaskProposal`
5. Constrain `estimated_hours: Optional[float] = Field(None, ge=0.0, le=999.9)`
6. Constrain `tags: Optional[List[str]] = Field(None, max_length=20)` with item validation
7. Add `@field_validator` for tags: strip whitespace, max 50 chars per tag
**Verify:** `docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance`
**Tests:** Add test cases for rejected invalid input (negative hours, bad priority, oversized description)

### Task 1.4: Prompt Injection Mitigation
**Fixes:** C4
**File:** `backend/services/gemini_service.py:71-78,236`
**Steps:**
1. JSON-encode user input before interpolation: `json.dumps({"transcription": transcription})`
2. Add output schema validation — verify LLM response matches expected JSON structure
3. Add a `sanitize_prompt_input()` helper that strips XML-like tags from user input
4. Apply to both `detect_brain_dump()` and `generate_subtasks()` prompts
**Verify:** Run eval suite: `docker exec todo-backend python evaluation/run_eval.py`
**Tests:** Add test case with adversarial prompt injection input, verify it doesn't produce rogue actions

### Task 1.5: Production Config Defaults
**Fixes:** C7
**Files:** `backend/config.py`, `backend/Dockerfile`, `backend/database.py`
**Steps:**
1. Change `config.py`: `debug: bool = False` (default off)
2. Add `app_env: str = "production"` to Settings
3. Update `database.py`: `echo=False` (always, remove debug dependency)
4. Create `backend/Dockerfile.dev` with `--reload` for development
5. Update production `Dockerfile`: remove `--reload`, add `--workers 4`
6. Update `docker-compose.yml` to use `Dockerfile.dev` for local dev
**Verify:** `docker-compose up --build` starts without debug output, no SQL echo
**Tests:** Existing tests pass

### Task 1.6: Frontend URL Configuration
**Fixes:** C6
**File:** `frontend/lib/config/constants.dart`
**Steps:**
1. Replace hardcoded URL with `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8001/api')`
2. Add `WS_BASE_URL` similarly for WebSocket
3. Update `frontend/CLAUDE.md` with build instructions: `flutter run --dart-define=API_BASE_URL=https://...`
4. Document HTTPS requirement for production builds
**Verify:** `cd frontend && flutter analyze` (0 issues), `flutter test`
**Tests:** Update `constants_test.dart` for new defaults

---

## Phase 2: High — Security Hardening

> Goal: Close all HIGH findings. Required before public beta.

### Task 2.1: WebSocket Auth Fix
**Fixes:** H1, H2
**File:** `backend/routers/ramble.py:22-50`
**Steps:**
1. Move `verify_id_token()` BEFORE `websocket.accept()`
2. On auth failure: `await websocket.close(code=4001)` without accepting
3. Extract `user_id` from decoded token, pass to ramble service
4. Document that token is still in query param (WebSocket header limitation in browsers — acceptable for mobile-only app, but log a TODO for first-message auth pattern)
**Verify:** Connect without token → connection rejected before accept. Connect with invalid token → 4001 close.
**Tests:** Add WebSocket auth test cases in `test_brain_dump.py` or new `test_ramble.py`

### Task 2.2: IDOR — Parent Task Ownership Validation
**Fixes:** H3
**Files:** `backend/routers/tasks.py`, `backend/services/task_service.py`
**Steps:**
1. In `create_task()`: if `parent_id` provided, fetch parent task and verify `parent.user_id == user_id`
2. In `update_task()`: same check when `parent_id` is being changed
3. Return 403 if parent not owned by user, 404 if parent doesn't exist
**Verify:** `docker exec todo-backend python -m pytest tests/test_api_tasks.py -v`
**Tests:** Add test: create task with other user's parent_id → 403

### Task 2.3: Security Headers Middleware
**Fixes:** H4
**File:** `backend/main.py`
**Steps:**
1. Add middleware function `add_security_headers()`
2. Set headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection: 1; mode=block`
3. Conditionally add `Strict-Transport-Security` when `app_env == "production"`
4. Disable Swagger docs in production: `docs_url=None if not debug`
5. Remove `environment` from health endpoint response
**Verify:** `curl -I http://localhost:8001/health` shows security headers
**Tests:** Add test asserting headers present on responses

### Task 2.4: WebSocket Input Validation & Hardening
**Fixes:** H5, H6, H7
**File:** `backend/routers/ramble.py`
**Steps:**
1. Wrap `json.loads(raw)` in try/except `json.JSONDecodeError`
2. Add `VALID_TYPES = {"start", "audio", "stop"}` whitelist
3. Validate audio chunk size: `MAX_AUDIO_CHUNK_SIZE = 200_000` (bytes of base64)
4. Add per-connection message counter + rate: max 100 messages/second
5. Replace all `f"...{e}"` error messages with generic client-facing messages
6. Keep `logger.error(..., exc_info=True)` server-side only
**Verify:** Send malformed JSON → graceful error. Send oversized chunk → rejected.
**Tests:** Add WebSocket validation test cases

### Task 2.5: Input Sanitization
**Fixes:** H8
**File:** `backend/models/schemas.py`
**Steps:**
1. Add `@field_validator('title', 'description', mode='before')` to strip HTML tags
2. Use `re.sub(r'<[^>]+>', '', value)` — lightweight, no dependency
3. Apply to `CreateTaskRequest`, `UpdateTaskRequest`, `BrainDumpTaskProposal`
**Verify:** Create task with `<script>alert(1)</script>` in title → stored without tags
**Tests:** Add sanitization test cases

### Task 2.6: Category Authorization Fix
**Fixes:** H9
**File:** `backend/routers/categories.py:40-50`
**Steps:**
1. Update `delete_category()` service to distinguish "not found" vs "not owned"
2. Return 403 for ownership failures, 404 for genuinely missing
3. Log unauthorized deletion attempts
**Verify:** Delete other user's category → 403
**Tests:** Add authorization test case

### Task 2.7: Frontend Auth Interceptor Fix
**Fixes:** H11
**File:** `frontend/lib/services/auth_interceptor.dart`
**Steps:**
1. Wrap `getIdToken()` in try/catch
2. On failure: `handler.reject(DioException(...))` instead of proceeding
3. Log auth failure for debugging
**Verify:** `cd frontend && flutter test`
**Tests:** Add test: mock `getIdToken()` failure → request rejected

---

## Definition of Done (per phase)

### Phase 1 Complete When:
- [ ] All backend tests pass: `docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance`
- [ ] All frontend tests pass: `cd frontend && flutter test`
- [ ] Frontend analyze clean: `cd frontend && flutter analyze` (0 issues)
- [ ] Eval suite passes: `docker exec todo-backend python evaluation/run_eval.py` (no regression)
- [ ] No hardcoded secrets in any tracked file: `git grep -i "AIzaSy\|sk_hzn\|todo123"` returns nothing
- [ ] CORS restricted (manual curl test)
- [ ] Debug mode off by default (manual check)

### Phase 2 Complete When:
- [ ] All Phase 1 checks still pass
- [ ] WebSocket rejects unauthenticated connections (manual test)
- [ ] Parent task IDOR blocked (test case)
- [ ] Security headers present on responses (curl test)
- [ ] Malformed WebSocket input handled gracefully (test case)
- [ ] HTML stripped from task content (test case)
- [ ] Auth interceptor rejects on token failure (flutter test)

---

## Estimated Scope

| Phase | Tasks | Files Changed | New Tests |
|-------|-------|---------------|-----------|
| Phase 1 | 6 tasks | ~10 files | ~15 test cases |
| Phase 2 | 7 tasks | ~8 files | ~20 test cases |

**Note:** Phase 3 (Medium findings) is intentionally deferred to backlog. Will plan separately after Phase 1+2 ship.
