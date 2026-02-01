# TODO - Development Planner

**Last Updated**: 2026-02-01

---

## Backlog


- initialize git version history for this - P0
- Add push to talk instead of start and stop - P0
- Move from LLM to AI Agent - We want the interaction of this app to be voice first. The agent will do the functions - add, complete, delete, edit are the ones that I can think of right now. add, complete, delete, edit are basically the user key words that we'll use. - P0
- Implemenet Sub categories / projects
- Advanced Task Management - Voice driven + UI driven
- Maximalist UI - Crazy animation design

---

## In Progress

(Empty)

---

## Done

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
**GitHub**: (To be created)
**Developer**: Tarang Goel
**Started**: 2026-02-01
**MVP Completed**: 2026-02-01
**Status**: ✅ Production-ready MVP
