# QA Checklist — Pre-Launch

Manual test pass on physical device. Check each item, note any bugs.
Backend must be running: `docker compose up -d`

## 1. Auth Flow

- [ ] Fresh install → lands on login screen
- [ ] Google Sign-In → lands on home screen with tasks loaded
- [ ] Sign out → lands on login screen, no "session expired" popup
- [ ] Sign back in (same account) → tasks visible immediately
- [ ] Sign out + sign in (different account) → old account's tasks NOT visible
- [ ] Kill app while signed in → reopen → auto-authenticated, tasks load
- [ ] Force-expire token (wait 1hr or clear app data) → app refreshes token silently

## 2. Task CRUD (Node View)

- [ ] Tap domain card → expands with liquid focus animation
- [ ] Swipe task right → completes (strikethrough + haptic)
- [ ] Swipe task left → deletes (confirmation dialog)
- [ ] Tap task → opens detail overlay
- [ ] Edit title in detail overlay → saves on dismiss
- [ ] Edit priority → reflected immediately
- [ ] Edit due date → reflected immediately
- [ ] Add subtask via detail overlay → appears under parent
- [ ] Complete parent with active children → children also complete

## 3. Task CRUD (Flat View)

- [ ] Toggle to flat view → all active tasks listed
- [ ] Complete task via checkbox toggle → moves to completed section
- [ ] Undo complete → task returns to active
- [ ] Pull to refresh → syncs with backend
- [ ] Search (type in search bar) → results filter in real-time
- [ ] Search with no results → "No tasks found" message

## 4. Task CRUD (Calendar View)

- [ ] Toggle to calendar view → tasks grouped by due date sections
- [ ] Overdue section shows past-due tasks in red
- [ ] Today/Tomorrow sections correct
- [ ] Tasks with no due date in "No Date" section
- [ ] Tap task → opens detail overlay

## 5. Filters (Flat View)

- [ ] Open filter sheet → all options visible
- [ ] Filter by category → only matching tasks shown
- [ ] Filter by priority → correct filtering
- [ ] Filter by status (active/completed) → works
- [ ] Multiple filters → AND logic (intersection)
- [ ] Active filter chips shown below top bar
- [ ] Tap chip X → removes that filter
- [ ] "Clear all" removes all filters

## 6. Voice Input (Ramble)

- [ ] Long-press pill → ramble screen opens, recording starts
- [ ] Waveform animates during recording
- [ ] Release → recording stops, transcript appears
- [ ] Edit transcript → changes reflected
- [ ] Send transcript → processing spinner → proposal cards appear
- [ ] Stop recording early (< 2s) → "Recording too short" message
- [ ] Timer shows time remaining (5-minute cap); warning colour at ≤60 s
- [ ] Microphone permission denied → graceful error message

## 7. Keyboard Input

- [ ] Tap pill (short tap) → `AddTaskSheet` opens
- [ ] Enter title (+ domain, priority, date, parent) → submit → task appears (works offline too)
- [ ] Typed brain dump: in the Ramble transcript editor, type or edit text → send → proposal cards appear

## 8. Proposal Review (Brain Dump)

- [ ] ADD proposal → shows title, category, priority chips
- [ ] COMPLETE proposal → shows matched task name + confidence %
- [ ] EDIT proposal → before/after cards with arrow between
- [ ] EDIT with parent change → BEFORE shows old parent, AFTER shows new parent (highlighted)
- [ ] EDIT with category change → domain color changes between cards
- [ ] Reparent (EDIT with `parent_id`; MOVE is folded into EDIT) → parent context prominent in before/after
- [ ] DELETE proposal → shows matched task
- [ ] Deselect proposal (long-press) → dims card, excluded from submit
- [ ] Tap proposal → edit dialog opens
- [ ] Multiple proposals → scroll, all visible
- [ ] Disambiguation (multiple matches) → "Which task?" picker with context
- [ ] Submit → tasks created/modified → navigate back to home
- [ ] Success snackbar shown after submit

## 9. Offline Behavior

- [ ] Enable airplane mode → "Offline" indicator appears
- [ ] Create task offline → task appears locally
- [ ] Complete task offline → completed locally
- [ ] Disable airplane mode → tasks sync to backend
- [ ] Check backend has the offline-created tasks

## 10. Sync

- [ ] Create task on one session → appears on fresh app launch
- [ ] Sync pulls delta (check logcat: `sync.pull.delta.done`)
- [ ] Periodic sync fires every 30s (check logcat: `sync.periodic`)
- [ ] App backgrounded → sync stops
- [ ] App resumed → sync triggers immediately

## 11. Notifications

- [ ] FCM token registered on login (check backend logs)
- [ ] Task with due date → notification fires at due time
- [ ] Tap notification → opens app to task detail
- [ ] Sign out → FCM token unregistered

## 12. Profile Screen

- [ ] Shows avatar (Google photo or initials)
- [ ] Shows display name + email
- [ ] Shows "Member since" date
- [ ] Archive link → opens archive screen
- [ ] Sign out → confirmation dialog → signs out

## 13. Archive

- [ ] Archived tasks listed
- [ ] Restore task → returns to active tasks
- [ ] Permanent delete → confirmation → task gone
- [ ] Empty archive → "No archived tasks" message

## 14. App Lifecycle

- [ ] Background app (home button) → no crash
- [ ] Resume app → sync triggers, UI updates
- [ ] Kill app → reopen → authenticated, tasks load from cache then sync
- [ ] Switch to another app and back → no stale state

## 15. Error Handling

- [ ] Stop backend → use app → error snackbar (not crash)
- [ ] Check Firebase DebugView → `api_error` outcome event appears
- [ ] Check Crashlytics → non-fatal error recorded (if server error)
- [ ] Start backend again → app recovers, sync resumes
- [ ] Invalid voice input (gibberish) → "No tasks detected" message
- [ ] Rate limit exceeded (spam requests) → 429 error handled gracefully

## 16. Analytics Verification

- [ ] Firebase DebugView shows `app_screen_view` events (not `screen_view`)
- [ ] Tap events have `element`, `screen` params
- [ ] Outcome events have typed params (not all strings)
- [ ] `task_completed` outcome tracked on toggle
- [ ] `ramble_started` / `ramble_completed` tracked for voice sessions
- [ ] User ID set in Firebase (matches Firebase Auth UID)

## 17. Edge Cases

- [ ] Very long task title (200+ chars) → truncated in UI, saved in full
- [ ] Special characters in task title (emoji, unicode) → handled
- [ ] Rapid tap on complete/uncomplete → no duplicate mutations
- [ ] Create 50+ tasks → scroll performance acceptable
- [ ] Deep nesting (5+ levels) → node view handles gracefully
- [ ] All 8 domain categories → each has distinct color palette

## 18. Performance

- [ ] App launch to tasks visible: < 3s (cached) / < 5s (cold)
- [ ] Task complete toggle: < 200ms visual feedback
- [ ] Voice recording start: < 500ms from long-press
- [ ] Proposal generation: < 5s from submit
- [ ] No jank during scroll (60fps)
- [ ] Memory: no leak after extended use (check via `adb shell dumpsys meminfo com.amble.app`)

---

## Bug Log

| # | Screen | Issue | Severity | Status |
|---|--------|-------|----------|--------|
| | | | | |
