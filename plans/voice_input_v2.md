# Voice Input V2 — "Ramble Mode"

> Historical plan, as of 2026-02-25. Current state: see [README.md](../README.md) and [docs/NOTES.md](../docs/NOTES.md).

## Current State vs Target

| Aspect | Current | Target (V2) |
|--------|---------|-------------|
| Recognition | On-device STT (`speech_to_text`) | Server-side via WebSocket streaming |
| Transport | Text-only POST to `/api/agent/process` | WebSocket: stream PCM audio in real-time |
| Multi-task | One command per recording | Multiple tasks from one continuous session |
| Execution | Auto-executes immediately | Tasks appear as cards, user reviews & submits |
| Session | One-shot (60s max) | Pause/resume, 5min inactivity timeout |
| Feedback | Basic waveform + snackbar | Sound effects, amplitude viz, live task cards |
| UI | PushToTalkButton inline | Full-screen Ramble overlay |

## Architecture Target

```
┌──────────────────────────────────────────────────────┐
│  Flutter Frontend                                    │
│                                                      │
│  RambleOverlay (full-screen)                         │
│  ├── AmplitudeVisualizer (real-time)                 │
│  ├── TranscriptionText (live partial text)           │
│  ├── TaskCardList (scroll, edit, delete before save) │
│  ├── Controls (pause/resume/done)                    │
│  └── StatusBar (timer, connection state)             │
│                                                      │
│  RambleService                                       │
│  ├── AudioRecorder (16kHz PCM via `record` package)  │
│  ├── WebSocketClient (stream audio chunks)           │
│  └── SoundPool (start/stop/add/edit/delete/error)    │
│                                                      │
│  RambleNotifier (Riverpod state machine)             │
│  ├── sessionState: connecting/recording/paused/done  │
│  ├── pendingTasks: List<RambleTask>                  │
│  ├── transcription: String (live)                    │
│  └── amplitude: double (0-1)                         │
└──────────────────────┬───────────────────────────────┘
                       │ WebSocket (wss://)
                       │ audio chunks (base64 PCM) ↑
                       │ transcription + tool calls ↓
┌──────────────────────┴───────────────────────────────┐
│  FastAPI Backend                                     │
│                                                      │
│  /ws/ramble WebSocket endpoint                       │
│  ├── Receives: start, audio, stop messages           │
│  ├── Pipes audio → Gemini Multimodal Live API        │
│  ├── Sends back: transcription, tool_call, status    │
│  └── Session management (timeout, rate limit)        │
│                                                      │
│  RambleSessionManager                                │
│  ├── Audio buffer → Gemini streaming                 │
│  ├── Tool call schema (addTask, editTask, deleteTask)│
│  └── Context injection (user's task tree)            │
└──────────────────────────────────────────────────────┘
```

## Phased Implementation

### Phase 1: Multi-Task Voice (Backend) — Foundation
**Goal**: Backend can receive text and return multiple structured tasks (no streaming yet)

**Tickets**:

#### 1.1 New "brain dump" Gemini prompt
- New method `gemini_service.detect_brain_dump(transcription, task_context)`
- Prompt returns JSON array of tool calls: `[{name: "addTask", args: {content, dueDate, priority, projectId, labels}}]`
- Reuse existing task tree context builder
- Unlike current `detect_intent()` which auto-executes, this returns structured proposals
- Fields: content (required), description, dueDate, priority, category, parentQuery, labels

#### 1.2 New `/api/agent/braindump` REST endpoint
- Accepts `{transcription: str, user_id: str, project_id?: str}`
- Calls `detect_brain_dump()` → returns list of proposed tasks
- Does NOT create tasks yet — just returns proposals
- Response: `{tasks: [{id, content, description, dueDate, priority, category}], transcription: str}`

#### 1.3 New `/api/agent/braindump/submit` REST endpoint
- Accepts `{tasks: [{content, dueDate, priority, category, ...}], user_id: str}`
- Creates all tasks in batch (single transaction)
- Returns created task IDs
- User can edit/remove tasks on frontend before calling this

#### 1.4 Tests for brain dump pipeline
- Test prompt with multi-task inputs: "Buy milk, call dentist tomorrow, finish report by Friday"
- Test single task input still works
- Test empty/garbage input handling
- Add eval cases to `evaluation/run_eval.py`

---

### Phase 2: Ramble UI (Frontend) — Review Before Submit
**Goal**: Full-screen voice overlay with task cards the user reviews before committing

**Tickets**:

#### 2.1 RambleTask model + RambleNotifier (state management)
- `RambleTask`: id, content, description, dueDate, priority, category, labels, isEdited
- `RambleNotifier` (StateNotifier):
  - States: `idle → recording → processing → reviewing → submitting → done`
  - `pendingTasks`: list of RambleTask (mutable — user can edit/delete)
  - `transcription`: live text
  - `amplitude`: double for visualizer
  - Actions: `startRecording()`, `stopRecording()`, `removeTask(id)`, `editTask(id, changes)`, `submitAll()`, `discard()`

#### 2.2 RambleOverlay (full-screen UI)
- Launched from existing PushToTalkButton (long-press or dedicated button)
- **Recording state**: amplitude visualizer + live transcription text + "Listening..." title
- **Processing state**: loading indicator while backend processes
- **Review state**: scrollable task cards with:
  - Task content (editable inline)
  - Category chip
  - Due date chip
  - Priority indicator
  - Delete (X) button per card
  - "Add All" / "Discard" buttons at bottom
- **Submitting state**: progress indicator
- Back press → confirmation dialog if tasks exist ("You have unsaved tasks")

#### 2.3 Task card component
- Compact card showing: content, category pill, due date, priority dot
- Swipe-to-delete or X button
- Tap to expand/edit fields
- Matches existing app design system (AppColors tokens)

#### 2.4 Sound effects
- Add 4 sound files to assets: `session_start.wav`, `task_added.wav`, `task_removed.wav`, `session_end.wav`
- `RambleSoundService` with `AudioPlayer` — play on state transitions
- Keep sounds short (~200ms) and subtle

#### 2.5 Wire up to Phase 1 backend
- Recording → on-device STT → stop → POST `/api/agent/braindump` → show task cards
- User reviews → edits/deletes → taps "Add All" → POST `/api/agent/braindump/submit`
- Refresh task store on success

---

### Phase 3: WebSocket Streaming (Backend) — Real-Time
**Goal**: Stream audio to backend, get transcription + tasks in real-time

**Tickets**:

#### 3.1 WebSocket endpoint `/ws/ramble`
- FastAPI WebSocket route
- Client message types: `start` (with user context), `audio` (base64 PCM chunk), `stop`
- Server message types: `transcription` (live text), `tool_call` (task action), `status` (session state), `error`
- Session management: track active sessions, 5min inactivity timeout

#### 3.2 Gemini streaming integration
- Use Gemini's streaming/multimodal API to process audio chunks
- System prompt includes user's task tree context
- Configure function calling with `addTask`, `editTask`, `deleteTask` tool definitions
- Stream transcription text back as it arrives
- Stream tool calls back as Gemini emits them

#### 3.3 Audio recording service (frontend)
- Use `record` package (already in project, currently unused)
- Configure: 16kHz sample rate, PCM 16-bit, mono
- Chunk audio into ~4096-byte buffers
- Base64 encode → send via WebSocket as JSON: `{type: "audio", data: "<base64>", sampleRate: 16000}`

#### 3.4 WebSocket client (frontend)
- `RambleWebSocketService`: connect, send audio chunks, receive events
- Parse incoming: `transcription` → update live text, `tool_call` → add task card, `status` → update session state
- Handle reconnection on disconnect
- Close cleanly on session end

#### 3.5 Update RambleNotifier for streaming
- Tasks appear as cards in real-time while user speaks (not after stopping)
- Transcription updates live
- Session states: connecting → recording → paused → reviewing
- Pause/resume: stop sending audio chunks, maintain WebSocket connection

---

### Phase 4: Session Polish — Pause/Resume/Timeout
**Goal**: Production-quality session management

**Tickets**:

#### 4.1 Pause/resume controls
- Pause button: stop recording + stop sending audio, show "Paused" state
- Resume button: restart recording + streaming
- Visual state change (icon, colors, title text)

#### 4.2 Session timeout & timer
- Backend tracks session duration, sends `secondsRemaining` in status messages
- Frontend shows countdown timer when < 2 minutes remaining
- Auto-transition to review state on timeout
- Configurable max session: 5 minutes (free) / 15 minutes (future premium)

#### 4.3 Connection state handling
- Show "Connecting..." overlay on WebSocket init
- Show "Reconnecting..." on unexpected disconnect
- Show "Offline" state if no network
- Graceful degradation: fall back to Phase 2 (on-device STT + REST) if WebSocket fails

#### 4.4 Confirmation dialog on exit
- If pendingTasks.isNotEmpty and user presses back
- "You have unsaved tasks" → "Keep going" / "Discard & exit"
- Prevent accidental loss

---

### Phase 5: Context & Intelligence
**Goal**: Smarter task extraction leveraging existing task tree

**Tickets**:

#### 5.1 Context-aware launch
- Launch Ramble from a specific category → pre-fill category for all tasks
- Launch from a specific task → all new tasks become subtasks
- Launch from a section/filter → pre-fill relevant context
- Pass context in WebSocket `start` message

#### 5.2 Smart field extraction
- Improve Gemini prompt to extract: due dates ("tomorrow", "next Friday"), priority ("urgent", "important"), category (infer from content), parent task (if user says "under project X")
- Date parsing aligned with backend QueryBuilder semantics
- Priority mapping: "urgent"→high, "important"→medium, default→none

#### 5.3 Edit/delete during session
- User can say "actually remove that last one" → `deleteTask` tool call
- User can say "change the deadline to Friday" → `editTask` tool call
- Backend returns edit/delete tool calls that modify the pending task list

---

## Recommended Execution Order

```
Phase 1 (1.1→1.2→1.3→1.4)  ← Backend foundation, can test independently
    ↓
Phase 2 (2.1→2.2→2.3→2.5→2.4)  ← Frontend overlay, wired to Phase 1
    ↓
    ★ SHIPPABLE V1: Multi-task voice with review ★
    ↓
Phase 3 (3.1→3.2→3.3→3.4→3.5)  ← Real-time streaming upgrade
    ↓
Phase 4 (4.1→4.2→4.3→4.4)  ← Session polish
    ↓
    ★ SHIPPABLE V2: Full streaming Ramble experience ★
    ↓
Phase 5 (5.1→5.2→5.3)  ← Intelligence layer
```

## Key Decisions to Make

1. **Keep existing single-command voice?** — Recommend yes, as a "quick command" mode alongside Ramble
2. **Gemini model for streaming?** — Need to verify Gemini's real-time audio streaming API availability and pricing
3. **On-device STT as fallback?** — Phase 2 uses on-device STT, Phase 3 moves to server-side. Keep both?
4. **Session limits?** — Implement rate limiting from the start or defer?
5. **Sound effects licensing** — Use royalty-free sounds or generate custom ones?

## Non-Goals (for now)
- TTS responses (server speaking back to user)
- Multi-language support
- Audio file storage/playback
- Freemium/upsell flows
- Widget/shortcut entry points
