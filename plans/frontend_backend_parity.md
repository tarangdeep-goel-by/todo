# Frontend ← Backend Parity Plan

Backend features that are implemented, tested, and returning data — but the frontend doesn't expose yet.

## 1. AI Placement Transparency

**Backend**: Every voice-created task stores `ai_placement_json` with `{ suggested_parent, confidence, reasoning }`. Returned in every `TaskResponse`.

**Frontend gap**: Field is parsed into `Task` model but never displayed.

**UI ideas**:
- "Why here?" tooltip/chip in task detail overlay showing `reasoning`
- Low-confidence indicator (< 0.7) so users can review questionable placements
- "AI placed this under X" subtitle when viewing a task

**Effort**: Small — data already flows to client.

---

## 2. Voice Transcription Display

**Backend**: `transcription` field stores the original voice command that created the task.

**Frontend gap**: Parsed but never shown.

**UI ideas**:
- "Created from voice: ..." in task detail overlay (collapsed by default)
- Useful for debugging when AI misinterprets a command

**Effort**: Small — single text widget in detail overlay.

---

## 3. Tags

**Backend**: `tags` column (ARRAY[String]) supported in DB, create/update APIs, and QueryBuilder filtering.

**Frontend gap**: `tags` field is **missing from the frontend Task model entirely**. Also missing from `CreateTaskRequest`.

**UI ideas**:
- Tag chips in task detail overlay (add/remove)
- Tag filter in list views (cross-category search)
- AI could auto-suggest tags from voice input

**Effort**: Medium — needs model update, UI for add/remove, filter integration.

---

## 4. Date Range Filtering

**Backend**: `GET /api/tasks` accepts 8 date-range query params:
- `created_at_gte/lte`
- `updated_at_gte/lte`
- `due_date_gte/lte`
- `completed_at_gte/lte`

All wired through QueryBuilder with tests passing.

**Frontend gap**: Never sends any of these. All filtering is client-side in `TaskStoreNotifier._filterAndSort()`.

**UI ideas**:
- "Due this week" / "Due today" quick filters
- "Completed last week" review view
- Date range picker for advanced filtering
- Could replace some client-side filtering with server-side for performance

**Effort**: Medium — API service needs params added, UI needs filter controls.

---

## 5. Server-Side Filtering & Sorting

**Backend**: `TaskFilterParams` supports server-side `category`, `priority`, `status`, `parent_id`, `tags`, and multi-field `sort`.

**Frontend gap**: Fetches all tasks with just `userId` + pagination, then filters/sorts client-side.

**UI ideas**:
- Not urgent — client-side works fine for current data volumes
- Becomes important if task count grows past hundreds
- Could enable "search across all tasks" without loading everything

**Effort**: Low priority until scale requires it.

---

## Priority Order

| # | Feature | Effort | User Value |
|---|---------|--------|------------|
| 1 | AI placement transparency | Small | Medium — builds trust in AI |
| 2 | Voice transcription display | Small | Low — debugging aid |
| 3 | Tags | Medium | High — cross-category organization |
| 4 | Date range filters | Medium | High — "what's due this week" |
| 5 | Server-side filtering | Low priority | Future scalability |

Pick up #1 and #2 as quick wins. #3 and #4 are good feature tickets.
