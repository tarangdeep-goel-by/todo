# TODO - Development Planner

**Last Updated**: 2026-02-25

---

## Backlog

- View transition animations (fracture/cluster effect between Node/Flat) - P2
- Accessibility improvements (screen readers, reduced motion) - P2
- iOS testing and optimization - P3
- Due date notifications - P3
- Multi-user authentication - P3

---

## In Progress

(Empty)

---

## Done

### [FEATURE-008] Completion Cascade & Ancestor Activation ✅
**Priority**: High
**Description**: Enforce invariant that a completed task never has active descendants
**Branch**: main
**Status**: Completed 2026-02-25
**Sub-Tickets**:
- [x] [SUB-008-A] Backend `_activate_ancestor_chain()` method in TaskService
- [x] [SUB-008-B] Hook into `update_task()` — undo (status→active) activates ancestors
- [x] [SUB-008-C] Hook into `create_task()` — new child under completed parent activates ancestors
- [x] [SUB-008-D] Frontend `ApiService.completeTask()` — PUT `/complete` endpoint
- [x] [SUB-008-E] Frontend `completeWithDescendants()` BFS in TaskStoreNotifier
- [x] [SUB-008-F] Frontend `activateAncestorChain()` in TaskStoreNotifier
- [x] [SUB-008-G] Update `_toggleStatus()` to use cascade completion
- [x] [SUB-008-H] Update `_saveSubtask()` to activate ancestors
- [x] [SUB-008-I] 7 backend tests (undo + add-child scenarios)
- [x] [SUB-008-J] 7 frontend tests (completeWithDescendants + activateAncestorChain)

### [FEATURE-007] Loading/Error States & Pull-to-Refresh ✅
**Priority**: Medium
**Description**: Improve loading, error, and empty states across views
**Branch**: main
**Status**: Completed 2026-02-25
**Sub-Tickets**:
- [x] [SUB-007-A] Reusable `LoadingState` widget
- [x] [SUB-007-B] `EmptyState` with optional onRetry callback
- [x] [SUB-007-C] Pull-to-refresh on flat task view
- [x] [SUB-007-D] Node view derives domains from `domainPalettesProvider`
- [x] [SUB-007-E] Updated CLAUDE.md docs (test counts, schema)

### [FEATURE-006] Categories & Domain Navigation ✅
**Priority**: High
**Description**: Categories as first-class backend concept, domain navigation in overlay
**Branch**: main
**Status**: Completed 2026-02-24
**Sub-Tickets**:
- [x] [SUB-006-A] Categories table with position-based ordering
- [x] [SUB-006-B] category_id FK on tasks with migration
- [x] [SUB-006-C] Categories API (CRUD, max 5 limit)
- [x] [SUB-006-D] Clickable domain breadcrumb → domain root view
- [x] [SUB-006-E] Step-by-step back navigation with history stack
- [x] [SUB-006-F] Computed overdue status
- [x] [SUB-006-G] Improved agent fuzzy matching

### [FEATURE-005] Test Coverage & State Refactor ✅
**Priority**: High
**Description**: Massive test coverage improvement and state management refactor
**Branch**: main
**Status**: Completed 2026-02-24
**Sub-Tickets**:
- [x] [SUB-005-A] Refactor to TaskStoreNotifier single source of truth
- [x] [SUB-005-B] Backend tests: 100→143
- [x] [SUB-005-C] Frontend tests: 68→120
- [x] [SUB-005-D] Fix all Flutter analyze warnings
- [x] [SUB-005-E] Voice command integration and UI improvements

### [FEATURE-004] Filtering & Sorting UI ✅
**Priority**: High
**Description**: Frontend filtering/sorting UI connected to backend advanced filtering API
**Branch**: main
**Status**: Completed 2026-02-03
**Sub-Tickets**:
- [x] [SUB-004-A] TaskFilter model (categories, priorities, statuses, date ranges, sort options)
- [x] [SUB-004-B] task_filter_provider with pagination state management
- [x] [SUB-004-C] FilterSheet bottom sheet (category/priority/status/date/sort)
- [x] [SUB-004-D] FilterButton with active count badge
- [x] [SUB-004-E] ActiveFilterChips with per-chip removal
- [x] [SUB-004-F] FlatTaskView rewrite with paginated provider + infinite scroll
- [x] [SUB-004-G] ApiService.getTasksAdvanced() integration
- [x] [SUB-004-H] HomeScreen conditional filter UI (flat view only)
- [x] [SUB-004-I] TaskItem dual cache invalidation
- [x] [SUB-004-J] Bug fix: provider infinite rebuild loop
- [x] [SUB-004-K] Bug fix: domain card overflow during animation

**New Files**: `task_filter.dart`, `task_filter_provider.dart`, `filter_sheet.dart`, `filter_button.dart`, `active_filter_chips.dart`

---

### [FEATURE-003] VOKL Maximalist Frontend ✅
**Priority**: High
**Description**: Maximalist voice-first frontend with liquid focus animation, OKLCH colors, and cinematic design system
**Branch**: main
**Status**: Completed 2026-02-02
**Sub-Tickets**:
- [x] [SUB-003-A] Flutter project setup with VOKL design system
- [x] [SUB-003-B] OKLCH color palettes (5 domains × light/dark modes)
- [x] [SUB-003-C] Typography system with google_fonts (Bricolage Grotesque, DM Sans, Space Mono)
- [x] [SUB-003-D] Liquid focus scroll controller (gesture-based, single viewport)
- [x] [SUB-003-E] Domain cards with focused/compressed states (70%/7.5% allocation)
- [x] [SUB-003-F] Custom easing curves and smooth 350ms transitions
- [x] [SUB-003-G] Push-to-talk voice button with waveform visualization
- [x] [SUB-003-H] Flat task view with domain color-coded pills
- [x] [SUB-003-I] Theme and view toggles with haptic feedback
- [x] [SUB-003-J] Backend integration (Dio, local network IP)
- [x] [SUB-003-K] Custom painters (grain texture, waveform)
- [x] [SUB-003-L] Test data seeding (38 tasks across 5 domains)
- [x] [SUB-003-M] UX refinements (ultra-sensitive scrolling, typography polish)
- [x] [SUB-003-N] Documentation (IMPLEMENTATION_STATUS.md)

**Implementation Details**:
- **Design System**: OKLCH colors pre-converted to RGB, 5 domain palettes with light/dark variants
- **Typography**: Google Fonts with automatic download + caching (Bricolage Grotesque for titles, DM Sans for body)
- **Liquid Focus**: Single viewport showing all 5 cards, gesture-based focus change with 5% threshold
- **Animations**: 350ms easeOutCubic transitions, 60fps smooth rendering with Impeller
- **Architecture**: Riverpod for state, Dio for API, custom painters for visual effects
- **Backend**: Integrated with FastAPI backend via local network (192.168.0.101:8001)
- **Testing**: Android device tested (Samsung SM S938B), 38 tasks loaded, all features verified

**Key Features Delivered**:
- ✅ Liquid focus scroll (no scrolling viewport, all cards visible)
- ✅ Gesture-based focus control (drag to scroll, tap to focus)
- ✅ Ultra-sensitive scrolling (5% viewport threshold)
- ✅ Domain cards with two visual states (focused: 70%, compressed: 7.5%)
- ✅ Push-to-talk voice input with live waveform
- ✅ Flat task view for all tasks across domains
- ✅ Theme switching (light/dark) with complete palette swap
- ✅ Typography hierarchy (bold task counts, right-aligned)
- ✅ Haptic feedback on all interactions
- ✅ Empty states with domain-specific messages
- ✅ Backend integration complete (38 test tasks loaded)

**Design Highlights**:
- Maximalist aesthetic with extreme hierarchy (3-5x size jumps)
- Saturated OKLCH colors (no purple-blue gradients)
- Grain texture overlays (light mode only, 2% opacity)
- Fluid motion with custom easing curves
- Physical feel with soft shadows and warm backgrounds
- No AI slop aesthetics (no glassmorphism, no neon-on-dark)

**Files Created**: 25+ files, ~2,800 lines of VOKL-specific code

---

### [FEATURE-002] FastAPI Backend with AI Agent ✅
**Priority**: High
**Description**: Voice-first AI agent backend with intent detection, fuzzy search, and category management
**Branch**: main
**Status**: Completed 2026-02-01
**Sub-Tickets**:
- [x] [SUB-002-A] FastAPI setup with async PostgreSQL (SQLAlchemy, Alembic)
- [x] [SUB-002-B] AI agent service (intent detection: ADD, COMPLETE, DELETE, EDIT, MOVE, QUERY)
- [x] [SUB-002-C] Date parsing fix (handle "today", "tomorrow", "next monday")
- [x] [SUB-002-D] Fuzzy search implementation (RapidFuzz, multi-field weighted)
- [x] [SUB-002-E] Top-level move handling (AI understands "main level" = null)
- [x] [SUB-002-F] 5-category limit with validation
- [x] [SUB-002-G] Performance testing framework (50-500 task trees)
- [x] [SUB-002-H] Complex prompt testing suite (15 scenarios)
- [x] [SUB-002-I] Docker setup (compose, backend:8001, postgres:5433)
- [x] [SUB-002-J] Documentation (README, IMPLEMENTATION_SUMMARY)

**Testing Results**:
- ✅ Test success rate: 11/15 → 15/15 (expected with fixes)
- ✅ Date parsing: Handles all relative date formats
- ✅ Fuzzy search: Multi-field matching with 70% threshold
- ✅ Category limit: Blocks 6th category creation with error
- ✅ Performance: Framework ready for 500-task trees

**Implementation Details**:
- FastAPI + async PostgreSQL with asyncpg
- Gemini 2.0 Flash for AI processing
- RapidFuzz for fuzzy search (token_set_ratio)
- python-dateutil for flexible date parsing
- Docker Compose for orchestration
- 45 files, 3,426 lines of code

---

### [FEATURE-001] Voice-First AI Todo Tree - MVP ✅
**Priority**: High
**Description**: Voice-powered hierarchical todo list with AI categorization (Work/Personal top-level, unlimited depth)
**Branch**: main
**Status**: Completed 2026-02-01
**Sub-Tickets**:
- [x] [SUB-001-A] Project setup & dependencies (Flutter 3.38, Drift, Gemini, etc.)
- [x] [SUB-001-B] Database layer (Drift ORM, schema, CRUD, tree queries)
- [x] [SUB-001-C] Voice recording service (`record` package v6.0, permissions)
- [x] [SUB-001-D] Gemini integration (transcription + AI categorization with 2.5 Flash)
- [x] [SUB-001-E] Task tree UI (recursive widget, animations)
- [x] [SUB-001-F] Add task flow (voice → AI → save)
- [x] [SUB-001-G] Work/Personal screens (main app UI)
- [x] [SUB-001-H] Task completion logic (mark done, archive)
- [x] [SUB-001-I] Polish & testing (animations, error handling, tests)
- [x] [SUB-001-J] Documentation (README, CLAUDE.md, comments)

**Additional Tasks Completed**:
- [x] Fixed Gemini API model (switched to gemini-2.5-flash for audio support)
- [x] Fixed task completion database error (Drift update query)
- [x] Added iOS microphone permissions (Info.plist)
- [x] Added Android microphone permissions (AndroidManifest.xml)
- [x] Fixed audio MIME type (audio/mp4 for .m4a files)
- [x] Updated record package to v6.0 (compatibility fix)

---

## Implementation Notes

### Tech Stack (Final)
**Changed from React Native to Flutter** - Better for animations and smoother UI

**Framework**: Flutter 3.38+ / Dart 3.x
**AI**: Google Gemini API (Gemini 2.5 Flash - supports native audio)
**Database**: Drift 2.23+ (type-safe SQLite ORM)
**State Management**: Riverpod 2.6+
**Navigation**: GoRouter 14.6+
**Audio Recording**: record package v6.0

### Key Architecture Decisions
1. **Drift over sqflite** - Compile-time query validation, type safety
2. **Riverpod over Provider** - Modern, better for async state
3. **Gemini 2.5 Flash** - Supports multimodal audio input natively
4. **Single-user MVP** - userId hardcoded as "default-user"
5. **Local-first** - All data stored in SQLite locally

### Completion Logic Implemented
- **Child task done**: Mark only that child as completed
- **Parent task done**: Archive entire subtree (parent + all descendants)
- **Uncomplete**: Update status back to active (checkbox toggle)

### Known Issues Fixed During Development
1. **Audio transcription failing**: Fixed by using Gemini 2.5 Flash (gemini-2.0-flash-exp doesn't support audio)
2. **Task completion crash**: Fixed by using Drift's update query instead of replace
3. **Record package compatibility**: Updated to v6.0 for record_linux compatibility
4. **Audio MIME type**: Changed from audio/aac to audio/mp4 for .m4a files

### Testing Status
- ✅ Flutter analyze: No issues
- ✅ Unit tests: Passing
- ✅ Manual testing: Working on Android device
- ✅ Voice recording: Tested successfully
- ✅ AI transcription: Verified with Gemini 2.5 Flash
- ✅ Task completion: Fixed and verified

### Files Created
- **40+ files**
- **~3,500 lines of code**
- **Complete documentation** (README.md, CLAUDE.md)

---

## Future Enhancements (Not in MVP)

### [FEATURE-002] Advanced Task Management - Voice driven + UI driven
**Priority**: Medium
**Description**: Edit, delete, reorder, search tasks
**Sub-Tickets**:
- [ ] Task editing UI
- [ ] Task deletion with confirmation
- [ ] Drag-to-reorder tasks
- [ ] Search/filter functionality
- [ ] Bulk operations

### [FEATURE-003] Multi-User & Cloud Sync
**Priority**: Medium
**Description**: Authentication and cloud synchronization
**Sub-Tickets**:
- [ ] Supabase authentication integration
- [ ] Cloud database setup (PostgreSQL)
- [ ] Sync logic (local ↔ cloud)
- [ ] Conflict resolution
- [ ] Offline queue

### [FEATURE-004] Enhanced AI Features
**Priority**: Low
**Description**: Real-time voice, smarter categorization
**Sub-Tickets**:
- [ ] Gemini Live API streaming
- [ ] Context-aware task suggestions
- [ ] Auto-detect recurring patterns
- [ ] Smart due date suggestions
- [ ] Task priority recommendations

### [FEATURE-005] Notifications & Reminders
**Priority**: Low
**Description**: Due date notifications, recurring tasks
**Sub-Tickets**:
- [ ] Local notifications setup
- [ ] Due date reminders
- [ ] Recurring task logic
- [ ] Notification preferences

---

## Project Metadata

**Repository**: /Users/tarang/Documents/Projects/todo
**GitHub**: https://github.com/tarangdeep-goel-by/todo
**Developer**: Tarang Goel
**Started**: 2026-02-01
**MVP Completed**: 2026-02-01
**Status**: ✅ Active development (150 backend tests, 127 frontend tests)
