# CLAUDE.md - Todo App Technical Guide

Developer guide for Claude Code when working on this Flutter todo app.

## Project Overview

Voice-first AI-powered hierarchical todo list app. Users record tasks, AI transcribes and categorizes them into a tree structure.

## Tech Stack

- **Flutter**: 3.38+ (Impeller rendering, Material 3)
- **Database**: Drift 2.23+ (type-safe SQLite ORM with compile-time validation)
- **State**: Riverpod 2.6+ (modern provider-based state management)
- **AI**: Google Gemini API (2.0 Flash model for transcription + categorization)
- **Audio**: record package (multiplatform native recording)
- **Navigation**: GoRouter 14.6+

## Architecture Patterns

### State Management (Riverpod)

**Provider Types Used**:
- `Provider`: Singletons (database, repositories, services)
- `StateNotifierProvider`: Mutable state (recording, transcription, categorization)
- `FutureProvider`: Async data (tasks, queries)
- `StateProvider`: Simple state (current recording path)

**Key Providers** (lib/providers/):
- `databaseProvider`: AppDatabase singleton with auto-disposal
- `taskRepositoryProvider`: Task CRUD operations
- `audioServiceProvider`: Audio recording service
- `geminiServiceProvider`: Gemini API client
- `recordingStateProvider`: Recording state (idle/recording/processing)
- `tasksByCategoryProvider`: Family provider for category-based queries
- `childTasksProvider`: Family provider for tree queries

### Database (Drift)

**Schema** (lib/data/database/tables.dart):
```dart
@DataClassName('TaskData')
class Tasks extends Table {
  TextColumn get id => text()();                    // UUID primary key
  TextColumn get userId => text()();                // default-user for MVP
  TextColumn get title => text()();                 // Task title
  TextColumn get description => text().nullable()();
  TextColumn get parentId => text().nullable()      // Self-referencing FK
      .references(Tasks, #id)();
  TextColumn get category => text()();              // work/personal
  TextColumn get status => text()                   // active/completed/archived
      .withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get audioFileUri => text().nullable()();
  TextColumn get transcription => text()();
  TextColumn get aiPlacementJson => text()();       // JSON string
}
```

**Key Methods** (lib/data/database/database.dart):
- `getTasksByCategory(category)`: Filter by work/personal
- `getTasksByParent(parentId)`: Get immediate children
- `getAllDescendants(taskId)`: Recursive tree traversal for archival
- `batchUpdateStatus(ids, status, completedAt)`: Bulk operations

**Repository Pattern** (lib/data/repositories/task_repository.dart):
- Wraps Drift database with domain models
- Converts between `TaskData` (DB) and `Task` (domain model)
- Implements business logic (completion, archival, seeding)

### Data Models

**Task** (lib/data/models/task.dart):
- Domain model with enums for category/status
- `copyWith` for immutability
- Separate from `TaskData` (DB layer)

**AIPlacement** (lib/data/models/ai_placement.dart):
- Stores AI suggestion metadata
- JSON serialization for storage
- Fields: `suggestedParent`, `confidence`, `reasoning`

### Services Layer

**GeminiService** (lib/services/gemini_service.dart):
- **transcribeAudio**: Converts audio file → text
  - Uses DataPart for multimodal input
  - Returns plain text (strips formatting)
- **categorizeTask**: Analyzes task + context → category/parent
  - Builds tree context string from existing tasks
  - Returns JSON with category, suggestedParent, confidence, reasoning
  - Handles markdown code blocks in response

**AudioService** (lib/services/audio_service.dart):
- **startRecording**: AAC-LC codec, 128kbps, 44.1kHz
- **stopRecording**: Returns file path
- **cancelRecording**: Stops + deletes file
- Saves to app documents dir: `{docs}/audio_recordings/recording_{timestamp}.m4a`

**PermissionService** (lib/services/permission_service.dart):
- Wraps permission_handler
- Requests/checks RECORD_AUDIO permission
- Handles permanently denied state

### UI Patterns

**Screens** (lib/screens/):
- `HomeScreen`: Bottom navigation (Work/Personal tabs)
- `WorkScreen` / `PersonalScreen`: Category views with task trees
- `AddTaskScreen`: Multi-stage flow (record → transcribe → categorize → review → save)
- `TaskDetailScreen`: Read-only task view

**Widgets** (lib/widgets/):
- `TaskCard`: Animated card with expand/collapse, completion checkbox
  - Uses `AnimationController` for scale animation on tap
  - Shows strikethrough + opacity change when completed
  - Indent based on depth (24px per level)
- `TaskTree`: Recursive widget for tree rendering
  - Auto-expands by default
  - Filters archived tasks
  - Passes callbacks up for tap/complete
- `TaskTreeList`: Wraps root category + children
  - Shows empty state if no tasks
  - RefreshIndicator support
- `VoiceRecorder`: Recording UI with pulsing animation
  - Updates duration every 100ms while recording
  - Haptic feedback on start/stop
  - Permission check before recording
- `AISuggestion`: Displays AI categorization with confidence
  - Color-coded confidence (green/orange/red)
  - Accept/Reject buttons
- `EmptyState`: Generic empty state component

**Animations**:
- Duration constants in `AppTheme` (200-400ms)
- `Curves.easeInOut` for most transitions
- `AnimatedContainer`, `AnimatedOpacity`, `AnimatedRotation` for implicit animations
- `ScaleTransition` with `AnimationController` for explicit control
- `Hero` transitions between screens

### Add Task Flow

**States** (lib/screens/add_task_screen.dart):
1. **recording**: Show voice recorder
2. **transcribing**: Upload audio → Gemini
3. **categorizing**: Send transcription + tree context → Gemini
4. **reviewing**: Show AI suggestion, allow accept/reject
5. **saving**: Create task in DB, invalidate cache, navigate back

**Error Handling**:
- Transcription error: Show snackbar, pop back
- Categorization error: Show snackbar, fall back to manual selection
- Save error: Show snackbar, stay on review state

### Completion Logic

**markTaskDone** (lib/data/repositories/task_repository.dart):
- Marks task as completed with timestamp
- Does NOT auto-complete parent (user might add more children later)

**archiveTask**:
- Gets ALL descendants recursively
- Batch updates all to archived status
- Used when marking parent complete (archives entire subtree)

### Tree Building

**Task Tree Context** (for Gemini):
```
Work (root-work)
  ├── Project Alpha (task-123)
  │   ├── Backend API (task-456)
  │   └── Frontend UI (task-789)
  └── Meetings (task-012)

Personal (root-personal)
  ├── Home (task-345)
  └── Errands (task-678)
```

Built by `_buildTreeContext` in GeminiService, sent to AI for context-aware categorization.

### Root Categories

**Seeded on app start** (lib/providers/task_provider.dart):
- `seedRootCategoriesProvider` ensures Work/Personal exist
- IDs: `root-work`, `root-personal`
- Created in `TaskRepository.seedRootCategories()`

### Permissions

**iOS** (ios/Runner/Info.plist):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record voice tasks</string>
```

**Android** (android/app/src/main/AndroidManifest.xml):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

## Development Workflow

### Code Generation

After changing Drift tables:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### Adding a New Provider

1. Create in `lib/providers/`
2. Use appropriate provider type (Provider/StateNotifierProvider/FutureProvider)
3. Add `ref.onDispose()` for cleanup if needed
4. Family providers for parameterized queries

### Adding a New Screen

1. Create in `lib/screens/`
2. Add route to `lib/config/router.dart`
3. Use ConsumerWidget for Riverpod access
4. Implement pull-to-refresh with `ref.invalidate()`

### Testing

**Widget Tests**:
- Wrap in ProviderScope
- Example: `test/widget_test.dart`

**Integration Tests**:
- Mock providers for controlled testing
- Test add task flow end-to-end

## Common Patterns

### Invalidating Cache

After mutations:
```dart
ref.invalidate(childTasksProvider);
ref.invalidate(tasksByCategoryProvider);
```

### Error Handling

Show SnackBar:
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text(errorMessage)),
);
```

### Haptic Feedback

```dart
HapticFeedback.lightImpact();   // Light tap
HapticFeedback.mediumImpact();  // Medium impact
HapticFeedback.selectionClick(); // Selection change
```

### Safe mounted checks

```dart
if (mounted) {
  // Use context here
}
```

## File Organization

- **config/**: App-wide configuration (theme, router, env)
- **data/**: Data layer (DB, models, repos)
- **providers/**: Riverpod providers
- **screens/**: Full-page screens
- **services/**: Business logic (API clients, platform services)
- **utils/**: Pure functions, constants
- **widgets/**: Reusable components

## Environment Variables

**lib/config/env.dart** (gitignored):
- `geminiApiKey`: Gemini API key
- `defaultUserId`: "default-user" for MVP
- `audioFileExtension`: ".m4a"
- `audioFolderName`: "audio_recordings"

**Template**: lib/config/env.example.dart

## Database Migrations

Currently schema version 1. For future migrations:
1. Increment `schemaVersion` in `AppDatabase`
2. Implement `onUpgrade` callback
3. Use Drift migration tools

## Performance Considerations

- **Tree rendering**: Virtualized with ListView
- **Deep nesting**: Lazy loading with expand/collapse
- **Audio files**: Stored locally, not in DB (only URI stored)
- **AI calls**: Show loading states, handle failures gracefully
- **Provider invalidation**: Selective cache invalidation to minimize rebuilds

## Known Limitations (MVP)

- Single user only (userId hardcoded)
- No offline queue for AI requests
- No task editing/deletion UI (only completion)
- No task reordering
- No search/filter
- No notifications

## Future Architecture Changes

- **Multi-user**: Add authentication, sync provider, userId from auth
- **Cloud sync**: Add Supabase provider, conflict resolution
- **Offline support**: Queue AI requests, sync when online
- **Advanced features**: Task editing, reordering, search requires UI + repo methods
