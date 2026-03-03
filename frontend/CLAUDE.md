# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Voice-first AI-powered hierarchical todo app. Flutter frontend communicates with a FastAPI backend (`../backend/`) via REST API. Users record voice tasks, AI transcribes and categorizes them into an 8-domain tree (Career, Finance, Health, Relationships, Growth, Recreation, Home, Community).

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

## Directory Structure

```
lib/
├── config/        → constants, theme, spacing, typography
├── models/        → task, category, task_filter, api_response
├── providers/     → task_store, task_filter, view_mode, api, recording
├── screens/       → home, parent_node_view, flat_task_view, ramble_screen
├── services/      → api, audio, speech, haptic, onboarding, ramble_websocket
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

### Input Flow (unified brain dump pipeline)

**Keyboard** (tap pill):
1. `PushToTalkButton` tap → keyboard text field (typing state)
2. User submits → `ApiService.processBrainDump()` → backend `/api/agent/braindump`
3. Backend returns `BrainDumpTaskProposal` list → navigate to `RambleScreen` in review mode
4. User reviews/edits proposals → submit → `/api/agent/braindump/submit` → tasks created
5. On return, success/error snackbar shown

**Voice / Ramble** (long-press pill):
1. `PushToTalkButton` long-press → opens `RambleScreen` (full-screen)
2. `AudioService.startStream()` streams PCM 16kHz mono → `RambleWebSocketService` → backend `/ws/ramble`
3. Gemini Live transcribes in real-time, displayed with animated waveform
4. User stops → edits transcript → sends to `/api/agent/braindump`
5. Backend returns `BrainDumpTaskProposal` cards — user reviews, deselects, edits
6. Submit → `/api/agent/braindump/submit` → batch task creation

### Navigation

No router library — single `HomeScreen` entry point with Material navigation:
- **Full-screen routes**: `Navigator.of(context).push()` (only `RambleScreen`)
- **Modal bottom sheets**: `showModalBottomSheet()` for `FilterSheet`, `TaskParentPicker`
- **Overlays**: `Overlay.of(context).insert()` for custom snackbars, `TaskDetailOverlay`, `WelcomeOverlay`

### Error Handling

- **Dio errors**: All API calls wrapped in `try/on DioException catch (e)` → `_handleError()` extracts user-friendly string from response `detail` field
- **Display**: Custom `showStyledSnackbar()` with `SnackbarStyle.error` (not Material snackbars)
- **No retry logic**: Failures fail immediately. Timeouts: connect=15s, receive=30s, send=15s
- **Store errors**: `TaskStoreState.error` captures non-fatal errors as strings
- **WebSocket**: `RambleWebSocketService` auto-reconnects if connection lost after >3s

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
final result = container.read(tasksByCategoryProvider('career'));
expect(result, hasLength(1));
```

### Audio Details

**Voice Stream** (long-press): Raw PCM 16-bit, 16kHz mono → base64-encoded chunks via WebSocket. Server streams back `transcription` (partial) and `final_transcript` events. Timer warnings when <120s remaining.

### Services (Non-Provider Singletons)

- **`HapticService`** — static methods (light/medium/heavy/selection/vibrate) called on taps, completions, errors
- **`OnboardingService`** — SharedPreferences-backed; tracks `welcomeSeen` flag for `WelcomeOverlay`
- **`SpeechService`** — `speech_to_text` package; 60s listen timeout, partial results enabled, sound level normalized to 0-1

## Key Conventions

- **API base URL**: Hardcoded in `lib/config/constants.dart` — must match your network IP for physical device testing (Android emulator uses `10.0.2.2`)
- **8 domains**: Career, Finance, Health, Relationships, Growth, Recreation, Home, Community — domains come from backend categories
- **Task statuses**: Only `active` and `completed` stored; `overdue` is computed client-side
- **User ID**: Hardcoded `default-user` (MVP, no auth)
- **Key widgets**: `RambleScreen` (brain dump + review UI), `AnimatedWaveform` (60fps ticker-driven), `PushToTalkButton` (dual-mode: tap=keyboard, long-press=voice)
- **Animations**: Custom curves in `AppAnimations` (constants.dart) — `easeOutQuint`, `easeOutCubic`
- **Theme**: OKLCH color system with 8 domain palettes in `lib/config/theme.dart` (dark mode only, no theme provider)
- **Typography**: Google Fonts (Bricolage Grotesque, DM Sans, Space Mono) via `google_fonts` package
- **Responsive sizing**: Font sizes fluid based on viewport width (e.g., domain title: `width * 0.08` clamped 56-72px)
- **Custom painters**: `GrainTexturePainter` (subtle noise on backgrounds), `WaveformPainter` (real-time audio viz)
- **Lint**: `flutter_lints` standard rules, no custom overrides — `flutter analyze` must pass with 0 issues
