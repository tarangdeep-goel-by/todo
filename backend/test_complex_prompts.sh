#!/bin/bash

# Test complex prompts with natural language
USER_ID="complex-test-user"
API_URL="http://localhost:8001/api/agent/process"

send_and_show() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 Prompt: $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    result=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"transcription\": \"$1\", \"user_id\": \"$USER_ID\"}")

    echo "$result" | jq '{
        success,
        message,
        type,
        data: {
            intent: .data.intent,
            title: .data.title,
            parent_id: .data.parent_id,
            new_parent_id: .data.new_parent_id,
            reasoning: .data.reasoning,
            matches: .data.matches
        }
    }'
    echo ""
}

echo ""
echo "🧪 TESTING COMPLEX PROMPTS"
echo "======================================================"
echo ""

echo "🎯 TEST 1: Complex ADD with lots of context"
send_and_show "I need to add a really urgent task about fixing that weird bug in the authentication system where users can't log in sometimes, it's been happening since yesterday and it should probably take me around 5 hours to debug and fix"

echo "🎯 TEST 2: ADD with implied parent from context"
send_and_show "Add a new task for writing unit tests for all those API endpoints we just created"

echo "🎯 TEST 3: ADD with time estimates and priority keywords"
send_and_show "Can you please add implement caching layer for database queries under backend development, it's super important and might take about 8 hours"

echo "🎯 TEST 4: Ambiguous MOVE with partial name matching"
send_and_show "Move that JWT validation thing to the authentication system where it belongs"

echo "🎯 TEST 5: MOVE with casual language"
send_and_show "Actually the password hashing task should be under API endpoints not authentication"

echo "🎯 TEST 6: COMPLETE with partial matching"
send_and_show "Mark the backend development stuff as done"

echo "🎯 TEST 7: COMPLETE with fuzzy matching"
send_and_show "I finished working on that redux thing"

echo "🎯 TEST 8: DELETE with context"
send_and_show "Delete all those contractor quote tasks, we decided not to renovate"

echo "🎯 TEST 9: EDIT with natural language"
send_and_show "Change the gym routine task to be due this Friday"

echo "🎯 TEST 10: QUERY with complex filters"
send_and_show "Show me all my work tasks"

echo "🎯 TEST 11: Complex nested ADD"
send_and_show "Add a new subtask under the iOS UI components for building a custom navigation bar with animated transitions"

echo "🎯 TEST 12: MOVE to top-level with casual phrasing"
send_and_show "Move grocery shopping to the main level, it shouldn't be under errands"

echo "🎯 TEST 13: ADD with multiple metadata"
send_and_show "Add a high priority task for client demo preparation due next Monday tagged with presentation and demo, estimated 6 hours of work"

echo "🎯 TEST 14: Ambiguous reference"
send_and_show "Complete the API task"

echo "🎯 TEST 15: Very casual language"
send_and_show "Yo add something about deploying to production under that DevOps CI/CD thing"

echo ""
echo "======================================================"
echo "✅ Complex prompt testing complete!"
echo ""
