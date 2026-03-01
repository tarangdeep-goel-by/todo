# Voice V2 — Next Steps

**Date**: 2026-02-28
**Branch**: `feature/voice-v2-braindump`
**Current state**: Phases 1-3 complete, brain dump eval 33/40 (82.5%)

---

## Step 1: Brain Dump Eval → 90%+

**Goal**: Fix the 7 failing cases. Target 36/40+.

### Failing cases analysis

| Case | Root Cause | Fix |
|------|-----------|-----|
| bd_add_01 | "finish the report" → complete, but no matching task in tree. Should be ADD. | Prompt: if completion verb but no tree match → ADD |
| bd_add_06 | Eval expects `content_contains("branding")` but LLM returns "design a logo" | **Eval config bug** — change to `content_contains("logo")` |
| bd_move_01 | "put X to top level" → edit instead of move | Prompt: "top level"/"root" → move with targetParentQuery=null |
| bd_mixed_05 | "add X under idea validation" → parentQuery=null | Prompt: strengthen "under Y" → must set parentQuery |
| bd_mixed_06 | "buy running shoes with high priority" → add instead of edit (task exists) | Prompt: existing task + field changes → edit not add |
| bd_mixed_07 | "finished X, schedule Y, set Z priority" → merged into 2 actions instead of 3 | Prompt: distinct tree-matched tasks → separate actions |
| bd_edge_05 | "show me all work tasks" → 3 complete actions instead of [] | Prompt: move query-skip rule higher, add examples |

### Tasks

1. Fix eval config: `bd_add_06` check → `content_contains("logo")`
2. Add 6 prompt rules to `detect_brain_dump()`:
   - Completion verb + no tree match → ADD
   - Query/list requests → return [] (move rule higher, add examples)
   - "top level"/"root" → move with null target
   - "under Y" → always set parentQuery
   - Existing task + field changes → edit not add
   - Distinct tree-matched tasks → separate actions
3. Run eval, iterate until 36/40+

**Files**: `gemini_service.py`, `brain_dump_eval_config.json`
**Dependencies**: None

---

## Step 2: Session Polish (Phase 4)

### 2a. Pause/Resume Controls

**Goal**: User can pause mid-speech, resume, get coherent combined transcript.

- Add `paused` state to `_RamblePhase` (or `_isPaused` bool)
- Pause: cancel audio stream sub, stop streaming, keep WebSocket open
- Resume: restart audio stream, re-subscribe
- UI: swap icon/color to paused state, show "Paused" header
- No backend changes — WebSocket stays open, just no audio chunks sent

**Files**: `ramble_screen.dart`, `audio_service.dart`
**Dependencies**: None

### 2b. Session Timeout & Timer

**Goal**: Auto-end at 5 min. Timer visible in last 2 min.

- Backend: track `start_time` in `ramble.py`, send `{"type": "status", "status": "time_remaining", "seconds": N}` every 30s, auto-close at 0
- Frontend: parse `time_remaining` status, show timer when < 120s, auto-transition to editing phase
- Default 5 min, expose as constant

**Files**: `ramble.py`, `ramble_screen.dart`, `ramble_websocket_service.dart`
**Dependencies**: None

### 2c. Connection State Handling

**Goal**: Network drop doesn't lose transcript. User sees clear connection state.

- WebSocket service: connection state enum (`connecting`/`connected`/`reconnecting`/`disconnected`)
- Reconnect: on unexpected disconnect, 1 retry with 2s delay, send new `start` + resume
- If reconnect fails → transition to editing phase with accumulated transcript
- UI: connection indicator in top bar, "Reconnecting..." banner
- Fallback: if initial connect fails, show snackbar + fall back to single-command flow

**Files**: `ramble_websocket_service.dart`, `ramble_screen.dart`
**Dependencies**: Do after 2a (reuses start/stop patterns)

### 2d. Exit Confirmation — ALREADY DONE

`_onWillPop()` already shows "You have unsaved tasks" dialog. No work needed.

---

## Step 3: Context & Intelligence (Phase 5)

### 3a. Context-Aware Launch

**Goal**: Ramble from a task → all new tasks become subtasks. Ramble from category → pre-fill category.

- `prefilledCategory` already works (passes to `processBrainDump`)
- Add `prefilledParentId` to `RambleScreen` — pass to backend via new field on `BrainDumpRequest`
- Backend: `process_brain_dump()` sets `parent_id` on all ADD proposals when present
- WebSocket: add optional `category`/`parent_task_context` to `start` message for Gemini Live context
- Frontend: add "Ramble subtasks" to task action menu → `RambleScreen(prefilledParentId: task.id)`

**Files**: `ramble_screen.dart`, `api_response.dart`, `schemas.py`, `agent_service.py`, `ramble.py`, `ramble_service.py`
**Dependencies**: Step 1 (stable prompt before adding context)

### 3b. Edit/Delete in Review Phase

**Goal**: User can correct misinterpretations without starting over.

Skip real-time tool calls (requires architecture overhaul). Instead:
- Add action type picker to proposal card (switch add↔complete↔edit via dropdown)
- Add "Record more" button in reviewing phase — appends to transcript, re-extracts
- Add "Re-extract" button — goes back to editing phase, user modifies transcript, re-submits

**Files**: `ramble_screen.dart`, `api_response.dart`
**Dependencies**: Step 2a (pause/resume infrastructure for "Record more")

---

## Step 4: Migrate Legacy SDK

**Goal**: Single `google-genai` SDK for all LLM calls. Schema-enforced output everywhere.

### Tasks

1. Create `IntentResponse` + `IntentParameters` Pydantic models (mirror current JSON structure)
2. Migrate `detect_intent()` → `self.client.aio.models.generate_content()` with `response_schema=list[IntentResponse]`
3. Create subtask response schema, migrate `generate_subtasks()` similarly
4. Remove `google.generativeai` import, `self._legacy_model`, `_extract_json()`
5. Remove `google-generativeai` from `requirements.txt` if unused elsewhere
6. Run both evals — verify no regression (intent: 58/65, brain dump: 36/40+)

**Files**: `gemini_service.py`, `requirements.txt`
**Dependencies**: Step 1 (stable prompt first)

---

## Execution Order

```
Step 1 (Eval → 90%)           ← do first, highest leverage
  │
  ├─ Step 4 (SDK migration)   ← can parallelize with Step 2
  │
  ├─ Step 2a (Pause/Resume)
  ├─ Step 2b (Timer/Timeout)
  ├─ Step 2c (Connection)     ← after 2a
  │
  ├─ Step 3a (Context launch) ← after Step 1
  └─ Step 3b (Edit in review) ← after 2a
```
