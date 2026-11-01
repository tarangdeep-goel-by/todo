# Complex Prompt Testing Results

> Historical, as of 2026-02-01. Current state: see [README.md](../README.md) and [docs/NOTES.md](../docs/NOTES.md). Current backend suite: ~415 `def test_` functions excluding `tests/performance`, run with `docker exec todo-backend python -m pytest tests/ --ignore=tests/performance`.

## Tree Structure Created
- **Total tasks**: 62 tasks
- **Depth**: 4 levels
- **Categories**: Work (43 tasks) + Personal (19 tasks)

### Sample Hierarchy (4 levels deep):
```
Work
└── Project Alpha
    └── Backend Development
        └── API Endpoints
            └── User Login Endpoint ← Level 4
```

---

## Test Results Summary

### ✅ WORKING WELL (11/15 tests passed)

#### 1. Complex ADD with Context Extraction ✅
**Prompt**: "I need to add a really urgent task about fixing that weird bug in the authentication system where users can't log in sometimes, it's been happening since yesterday and it should probably take me around 5 hours to debug and fix"

**Result**: ✅ Success
- Extracted title: "Fix authentication system bug"
- Found correct parent: Authentication System (3 levels deep)
- Extracted priority: urgent → high
- Extracted estimated_hours: 5

---

#### 2. Implied Parent from Context ✅
**Prompt**: "Add a new task for writing unit tests for all those API endpoints we just created"

**Result**: ✅ Success
- Correctly inferred "API endpoints" as parent
- Placed under correct backend development branch

---

#### 3. Priority & Time Estimates ✅
**Prompt**: "Can you please add implement caching layer for database queries under backend development, it's super important and might take about 8 hours"

**Result**: ✅ Success
- Extracted: priority="high" from "super important"
- Extracted: estimated_hours=8
- Correctly placed under backend development

---

#### 4. Ambiguous MOVE - Asks for Clarification ✅
**Prompt**: "Move that JWT validation thing to the authentication system where it belongs"

**Result**: ✅ Correctly asked for clarification
- Found 2 possible parent tasks:
  1. "Fix authentication system bug"
  2. "Authentication System"
- Returned question type response

---

#### 5. Partial Matching for COMPLETE ✅
**Prompt**: "Mark the backend development stuff as done"

**Result**: ✅ Success
- Found and completed "backend development" task

---

#### 6. Natural Language EDIT ✅
**Prompt**: "Change the gym routine task to be due this Friday"

**Result**: ✅ Success
- Updated gym routine task with new due date

---

#### 7. QUERY with Filters ✅
**Prompt**: "Show me all my work tasks"

**Result**: ✅ Success
- Found 43 work tasks
- Correctly filtered by category

---

#### 8. Complex Nested ADD (4 levels deep) ✅
**Prompt**: "Add a new subtask under the iOS UI components for building a custom navigation bar with animated transitions"

**Result**: ✅ Success
- Correctly placed 4 levels deep:
  - Work → Project Beta → iOS Development → UI Components → Navigation Bar

---

#### 9. Very Casual Language ✅
**Prompt**: "Yo add something about deploying to production under that DevOps CI/CD thing"

**Result**: ✅ Success
- Understood casual language
- Correctly placed under CI/CD pipeline

---

#### 10. Multiple Ambiguous Matches - Disambiguation ✅
**Prompt**: "Complete the API task"

**Result**: ✅ Correctly asked for clarification
- Found 4 matching tasks:
  1. "write unit tests for all the API endpoints..."
  2. "API integration"
  3. "API endpoints"
  4. "backend API"
- Returned question with all options

---

#### 11. Move with Target Disambiguation ✅
**Prompt**: "Actually the password hashing task should be under API endpoints not authentication"

**Result**: ✅ Correctly asked for clarification
- Found 2 possible targets for "API endpoints"
- Proper disambiguation flow

---

### ❌ ISSUES FOUND (4/15 tests failed)

#### 1. Fuzzy Matching Failure ❌
**Prompt**: "I finished working on that redux thing"

**Expected**: Should find "setup for Redux store"
**Actual**: "No tasks found matching 'Redux thing'"

**Issue**: Search query extraction not fuzzy enough ("Redux thing" vs "Redux store")

---

#### 2. Missing Task Search ❌
**Prompt**: "Delete all those contractor quote tasks, we decided not to renovate"

**Expected**: Should find "Get quotes from three contractors"
**Actual**: "No tasks found matching 'contractor quote'"

**Issue**: Search term mismatch ("contractor quote" vs "Get quotes from three contractors")

---

#### 3. Move to Top-Level Failure ❌
**Prompt**: "Move grocery shopping to the main level, it shouldn't be under errands"

**Expected**: Should move task to parent_id=null
**Actual**: "No parent task found matching 'null'"

**Issue**: Agent not interpreting "main level" as top-level (null parent)

---

#### 4. Relative Date Parsing Crash ❌
**Prompt**: "Add a high priority task for client demo preparation due next Monday tagged with presentation and demo, estimated 6 hours of work"

**Expected**: Should parse "next Monday" to ISO datetime
**Actual**: Database error - got string 'next monday' instead of datetime

**Issue**: Gemini returning relative date strings instead of ISO format
**Error**: `invalid input for query argument $12: 'next monday' (expected a datetime.date or datetime.datetime instance, got 'str')`

---

## Key Findings

### Strengths 💪
1. **Deep hierarchy understanding** - Correctly places tasks 4 levels deep
2. **Context extraction** - Extracts priority, tags, estimates from natural language
3. **Disambiguation** - Properly asks for clarification when ambiguous
4. **Casual language** - Handles informal phrasing well
5. **Intent detection** - 11/15 correct intent classifications

### Weaknesses 🐛
1. **Fuzzy search** - Needs better partial matching ("redux thing" → "redux store")
2. **Synonym matching** - "contractor quote" should match "quotes from contractors"
3. **Top-level movement** - Can't interpret "main level" / "root" as null parent
4. **Date parsing** - Returns string "next monday" instead of ISO datetime

---

## Recommendations

### High Priority Fixes
1. **Add date parsing layer** - Convert relative dates to ISO before DB insert
2. **Improve search matching** - Use fuzzy string matching (Levenshtein distance)
3. **Handle top-level moves** - Teach AI that "main level"/"root" means parent_id=null

### Medium Priority Improvements
1. **Better task search** - Support synonym matching for search queries
2. **Confidence tuning** - Lower threshold for fuzzy matches
3. **Error messages** - Better user guidance when search fails

### Nice to Have
1. **Multi-task operations** - "Delete all contractor tasks" should archive multiple
2. **Batch completions** - Handle completing multiple related tasks
3. **Smart suggestions** - When search fails, suggest similar tasks

---

## Performance Metrics

- **Intent Detection Accuracy**: 11/15 = 73%
- **Successful Operations**: 11/15 = 73%
- **Ambiguity Handling**: 3/3 = 100% ✅
- **Deep Hierarchy Placement**: 4/4 = 100% ✅
- **Context Extraction**: 3/3 = 100% ✅
- **Search/Matching**: 1/4 = 25% ❌ ← Main weakness

---

## Conclusion

The system handles **complex hierarchies and natural language very well**, but **search/matching needs improvement**. The AI correctly:
- Places tasks 4 levels deep
- Extracts metadata from conversational prompts
- Asks for clarification when needed

Main gaps are fuzzy search and date parsing.
