# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice-first AI-powered hierarchical todo app. Flutter frontend communicates with a FastAPI backend (`../backend/`) via REST API. Users record voice; the backend streams it to Sarvam AI (`saaras:v3`) for transcription and Gemini turns the transcript into task proposals placed in an 8-domain tree (Career, Finance, Health, Relationships, Growth, Recreation, Home, Community).

## Commands

```bash
# Run app (physical device — pass your machine's LAN IP; default is http://10.0.2.2:8001/api for the Android emulator)
flutter run --dart-define=API_BASE_URL=http://<lan-ip>:8001/api

# Run all tests (60 test files, ~469 test/testWidgets cases)
flutter test

# Run single test file
flutter test test/providers/task_store_provider_test.dart

# Run tests with name filter
flutter test --name "fetchAll populates store"

# Code analysis (must pass with 0 issues)
flutter analyze

# Install dependencies
flutter pub get

# Backend (must be running for app to work)
cd ../backend && docker-compose up --build   # API at http://localhost:8001
docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance

# Seed test data: seed_tasks.sh / seed_deep_tasks.sh predate Firebase Auth and get 401s now;
# ../backend/seed_realistic.py and seed_showcase.py write straight to the database
```

## Directory Structure

```
lib/
├── config/        → constants, environment (API_BASE_URL), theme, spacing, typography
├── database/      → Drift tables + DAOs (SQLCipher-encrypted local DB)
├── models/        → task, category, task_filter, api_response, api_error
├── providers/     → task_store, task_filter, view_mode, api, recording, auth, connectivity, local_data, mutation, sync, tutorial
├── screens/       → auth_gate, login, home, parent_node_view, flat_task_view, ramble_screen, archive, profile
├── services/      → api, api_retry, audio, speech (unused V1), haptic, onboarding, ramble_websocket, auth_interceptor, sync, task_mutation, local_data, connectivity, notification, tracker/
├── utils/         → liquid_focus_scroll, string_extensions
└── widgets/       → reusable UI components (overlays, sheets, painters, buttons)
```

## Architecture

### State Management: Single Source of Truth

`TaskStoreNotifier` (`lib/providers/task_store_provider.dart`) holds ALL tasks in a `Map<String, Task>`. Every screen reads from derived providers — never from direct API calls.

```
TaskStoreState (Map<String, Task>)
  ├── allTasksProvider           → List<Task>
  ├── tasksByCategoryProvider    → family(category) → List<Task>
  ├── taskByIdProvider           → family(id) → Task?
  ├── childTasksProvider         → family(parentId) → List<Task>
  └── flatViewTasksProvider      → filtered + sorted via TaskFilter
```

**Mutation pattern** (manual edits, offline-first): `TaskMutationService` writes the local Drift DB with `pendingSync`, enqueues to `SyncQueue`, updates the store immediately, then `SyncService` pushes (and pulls deltas) when online. Voice submits go straight to the API, then `taskStoreProvider.fetchAll()`.

### Three View Modes (3-way toggle: Node / Flat / Calendar; `ViewMode.profile` shows `ProfileScreen`)

1. **Node View** (`parent_node_view.dart`): Domain cards with liquid-focus scroll — one card expands (70% height), others compress (7.5%). Gesture-driven with `LiquidFocusScrollController`.
2. **Flat View** (`flat_task_view.dart`): All tasks in a filtered/sorted list with `FilterSheet` and `ActiveFilterChips`.
3. **Calendar View** (`calendar_task_view.dart`): Active tasks grouped by due date sections (Overdue → Today → Tomorrow → Next 7 days → Later → No Date).

### Client-Side Filtering & Sorting

`_filterAndSort()` in `task_store_provider.dart` mirrors backend semantics:
- **Computed status**: "overdue" = active + past due date; "due_soon" = active + due within 48 h (not stored, derived at render time)
- **Default sort**: status:asc → due_date:asc → priority:desc → created_at:desc
- **Status rank**: overdue(0) < due_soon(1) < active(2) < completed(3)
- **Priority rank**: high(3) > medium(2) > low(1) > none(0)

### Input Flow (unified brain dump pipeline)

**Manual** (tap pill in `BottomNavBar`):
1. Opens `AddTaskSheet` (structured form: title, domain, priority, date, parent)
2. Creates the task through `TaskMutationService` (works offline). No LLM call.

**Voice / Ramble** (long-press pill):
1. `BottomNavBar` long-press (blocked when offline), Android widget / QS tile / `amble://ramble` deep link, or "Ramble subtasks" from `TaskDetailOverlay` → opens `RambleScreen` (full-screen)
2. `AudioService.startStream()` streams PCM 16kHz mono → `RambleWebSocketService` → backend `/ws/ramble`
3. Sarvam AI `saaras:v3` (translate mode, via the backend) transcribes to English in real time, displayed with animated waveform
4. User stops → edits transcript → sends to `/api/agent/braindump`
5. Backend returns `BrainDumpTaskProposal` cards — user reviews, deselects, edits
6. Submit → `/api/agent/braindump/submit` → batch task creation

### Navigation

No router library — single `HomeScreen` entry point with Material navigation:
- **Full-screen routes**: `Navigator.of(context).push()` (`RambleScreen`, `ArchiveScreen`)
- **Modal bottom sheets**: `showModalBottomSheet()` for `AddTaskSheet`, `FilterSheet`, `TaskParentPicker`
- **Overlays**: `Overlay.of(context).insert()` for custom snackbars, `TaskDetailOverlay`

### Error Handling

- **Dio errors**: All API calls wrapped in `try/on DioException catch (e)` → `_handleError()` extracts user-friendly string from response `detail` field
- **Display**: Custom `showStyledSnackbar()` with `SnackbarStyle.error` (not Material snackbars)
- **Retry**: some `ApiService` reads use `retryWithBackoff()` (`api_retry.dart`); other calls fail immediately. Timeouts: connect=15s, receive=30s, send=15s
- **Store errors**: `TaskStoreState.error` captures non-fatal errors as strings
- **WebSocket**: `RambleWebSocketService` auto-reconnects (up to 3 times: 1 s, 2 s, 4 s) only if the connection had been up for 3 s or more

### Key Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `taskStoreProvider` | StateNotifierProvider | Single source of truth for all tasks |
| `apiServiceProvider` | Provider | Dio-based HTTP client (singleton) |
| `taskFilterProvider` | StateNotifierProvider | Active filter state for flat view |
| `recordingStateProvider` | StateProvider | Recording state: idle/listening/processing/typing |
| `recordingPathProvider` | StateProvider | Current audio file path |
| `waveformDataProvider` | StateProvider | Audio amplitude samples (last 50) |
| `transcriptionTextProvider` | StateProvider | Partial/final transcript text |
| `viewModeProvider` | StateProvider | Node / Flat / Calendar toggle |
| `categoriesProvider` | StateProvider | Backend categories (fetched separately) |
| `authStateProvider` / `authServiceProvider` | StreamProvider / Provider | Firebase Auth state and Google sign-in/sign-out |
| `audioServiceProvider` | Provider | Native audio recording + amplitude |
| `rambleWebSocketProvider` | Provider | WebSocket client for `/ws/ramble` |
| `taskMutationServiceProvider` | Provider | Offline-first manual mutations |
| `syncServiceProvider` | Provider | Push queue + delta pull |
| `isOnlineProvider` | Provider | Backend reachability |

## Testing Patterns

Tests use `mocktail` for mocking and `ProviderContainer` for isolated provider tests.

**Test helpers** (`test/helpers/test_helpers.dart`):
- `createTestTask(...)` — factory with sensible defaults
- `buildTestApp(child, overrides)` — wraps widget in ProviderScope + MaterialApp
- `MockApiService` — mock for `ApiService`

**Provider test pattern** (`task_store_provider_test.dart`):
```dart
final container = ProviderContainer(overrides: [
  apiServiceProvider.overrideWithValue(mockApi),
]);
final store = container.read(taskStoreProvider.notifier);
store.upsertTask(task);
final result = container.read(tasksByCategoryProvider('career'));
expect(result, hasLength(1));
```

### Audio Details

**Voice Stream** (long-press): Raw PCM 16-bit, 16kHz mono → base64-encoded chunks via WebSocket. Server streams back `transcription` (the whole accumulated text so far) and `final_transcript` events, plus a `time_remaining` status every 30 s; the timer turns to a warning colour at ≤60 s.

### Services (Non-Provider Singletons)

- **`HapticService`** — static methods (light/medium/heavy/selection/vibrate) called on taps, completions, errors
- **`OnboardingService`** — SharedPreferences-backed onboarding/tutorial flags (e.g. swipe tutorial step)
- **`SpeechService`** — `speech_to_text` package from the V1 voice flow. Still initialised by `HomeScreen` but never used to listen (dead code)

## Key Conventions

- **API base URL**: `Environment.apiBaseUrl` in `lib/config/environment.dart`, set with `--dart-define=API_BASE_URL=...` (default `http://10.0.2.2:8001/api`, the Android emulator's host). Non-HTTPS is only allowed for localhost/private IPs. `AppConstants.apiBaseUrl` in `constants.dart` is not used for requests
- **8 domains**: Career, Finance, Health, Relationships, Growth, Recreation, Home, Community — domains come from backend categories
- **Task statuses**: `active`, `completed`, `archived` stored; `overdue` and `due_soon` are computed
- **Authentication**: Firebase Auth via `auth_provider.dart` (Google sign-in only). `auth_interceptor.dart` Dio interceptor attaches `Authorization: Bearer <idToken>` to all requests. `firebase_options.dart` has platform config.
- **Key widgets**: `RambleScreen` (brain dump + review UI), `AnimatedWaveform` (60fps ticker-driven), `BottomNavBar` pill (tap = `AddTaskSheet`, long-press = Ramble). `PushToTalkButton` still exists but is not mounted anywhere
- **Animations**: Custom curves in `AppAnimations` (constants.dart) — `easeOutQuint`, `easeOutCubic`
- **Theme**: OKLCH color system with 8 domain palettes in `lib/config/theme.dart` (dark mode only, no theme provider)
- **Typography**: Google Fonts (Bricolage Grotesque, DM Sans, Space Mono) via `google_fonts` package
- **Responsive sizing**: Font sizes fluid based on viewport width (e.g., domain title: `width * 0.08` clamped 56-72px)
- **Custom painters**: `GrainTexturePainter` (subtle noise on backgrounds), `WaveformPainter` (real-time audio viz)
- **Lint**: `flutter_lints` standard rules, no custom overrides — `flutter analyze` must pass with 0 issues
