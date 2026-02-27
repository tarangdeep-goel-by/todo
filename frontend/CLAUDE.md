# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice-first AI-powered hierarchical todo app. Flutter frontend communicates with a FastAPI backend (`../backend/`) via REST API. Users record voice tasks, AI transcribes and categorizes them into a 5-domain tree (Work, Personal, Health, Learning, Projects).

## Commands

```bash
# Run app (physical device — update apiBaseUrl in lib/config/constants.dart to your machine IP)
flutter run

# Run all tests (125 tests)
flutter test

# Run single test file
flutter test test/providers/task_store_provider_test.dart

# Run tests with name filter
flutter test --name "filters tasks by category"

# Code analysis (must pass with 0 issues)
flutter analyze

# Install dependencies
flutter pub get

# Backend (must be running for app to work)
cd ../backend && docker-compose up --build   # API at http://localhost:8001
docker exec todo-backend python -m pytest tests/ -v --tb=short --ignore=tests/performance

# Seed test data
cd ../backend && ./seed_tasks.sh        # 12 basic tasks
cd ../backend && ./seed_deep_tasks.sh   # 62-task deep hierarchy
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

**Mutation pattern**: Optimistic update to store, then async backend sync.
```dart
store.upsertTask(updatedTask);          // Immediate UI
await apiService.updateTask(taskId, payload);  // Backend sync
```

### Three View Modes (3-way toggle: Node / Flat / Calendar)

1. **Node View** (`parent_node_view.dart`): Domain cards with liquid-focus scroll — one card expands (70% height), others compress (7.5%). Gesture-driven with `LiquidFocusScrollController`.
2. **Flat View** (`flat_task_view.dart`): All tasks in a filtered/sorted list with `FilterSheet` and `ActiveFilterChips`.
3. **Calendar View** (`calendar_task_view.dart`): Active tasks grouped by due date sections (Overdue → Today → Tomorrow → Next 7 days → Later → No Date).

### Client-Side Filtering & Sorting

`_filterAndSort()` in `task_store_provider.dart` mirrors backend semantics:
- **Computed status**: "overdue" = active + past due date (not stored, derived at render time)
- **Default sort**: status:asc → due_date:asc → priority:desc → created_at:desc
- **Status rank**: overdue(0) < active(1) < completed(2)
- **Priority rank**: high(3) > medium(2) > low(1) > none(0)

### Voice Command Flow

**Single Command** (tap mic):
1. `PushToTalkButton` tap → keyboard input or `processAndHandleAgentResponse()` utility
2. Audio uploaded via `ApiService.processAgent()` → backend `/api/agent/process`
3. Backend uses Gemini to transcribe, detect intent (ADD/COMPLETE/EDIT/DELETE/QUERY/BREAKDOWN)
4. If ambiguous, backend returns `type: "question"` → `QuestionBottomSheet` shown (also handles `select_category` and `create_category` actions)
5. User answers → `ApiService.resolveAgent()` → backend `/api/agent/resolve`
6. On success, `store.upsertTask()` updates UI immediately

**Brain Dump / Ramble** (long-press mic):
1. `PushToTalkButton` long-press → opens `RambleSheet` (full-screen bottom sheet)
2. `AudioService.startStream()` streams PCM 16kHz mono → `RambleWebSocketService` → backend `/ws/ramble`
3. Gemini Live transcribes in real-time, displayed with animated waveform
4. User stops → edits transcript → sends to `/api/agent/braindump`
5. Backend returns `BrainDumpTaskProposal` cards — user reviews, deselects, edits
6. Submit → `/api/agent/braindump/submit` → batch task creation

### Key Providers

| Provider | Type | Purpose |
|----------|------|---------|
| `taskStoreProvider` | StateNotifierProvider | Single source of truth |
| `apiServiceProvider` | Provider | Dio-based HTTP client |
| `taskFilterProvider` | StateNotifierProvider | Active filter state for flat view |
| `recordingProvider` | StateNotifierProvider | Recording state machine |
| `viewModeProvider` | StateProvider | Node / Flat / Calendar toggle |
| `audioServiceProvider` | Provider | Native audio recording + amplitude |
| `rambleWebSocketProvider` | Provider | WebSocket client for `/ws/ramble` |

## Testing Patterns

Tests use `mocktail` for mocking and `ProviderContainer` for isolated provider tests.

**Test helpers** (`test/helpers/test_helpers.dart`):
- `createTestTask(...)` — factory with sensible defaults
- `buildTestApp(child, overrides)` — wraps widget in ProviderScope + MaterialApp
- `MockApiService` — mock for `ApiService`

**Provider test pattern** (38 tests in `task_store_provider_test.dart`):
```dart
final container = ProviderContainer(overrides: [
  apiServiceProvider.overrideWithValue(mockApi),
]);
final store = container.read(taskStoreProvider.notifier);
store.upsertTask(task);
final result = container.read(tasksByCategoryProvider('work'));
expect(result, hasLength(1));
```

## Key Conventions

- **API base URL**: Hardcoded in `lib/config/constants.dart` — must match your network IP for physical device testing (Android emulator uses `10.0.2.2`)
- **5 domains**: Work, Personal, Health, Learning, Projects — defined in `AppConstants.domainNames`, must match backend
- **Task statuses**: Only `active` and `completed` stored; `overdue` is computed client-side
- **User ID**: Hardcoded `default-user` (MVP, no auth)
- **Key widgets**: `RambleSheet` (brain dump UI), `AnimatedWaveform` (60fps ticker-driven), `QuestionBottomSheet` (disambiguation + category picker)
- **Shared utility**: `agent_response_handler.dart` — `processAndHandleAgentResponse()` handles both keyboard and voice input routing
- **Animations**: Custom curves in `AppAnimations` (constants.dart) — `easeOutQuint`, `easeOutCubic`
- **Theme**: OKLCH color system with 5 domain palettes in `lib/config/theme.dart` (dark mode only, no theme provider)
- **Typography**: Google Fonts (Bricolage Grotesque, DM Sans, Space Mono) via `google_fonts` package
