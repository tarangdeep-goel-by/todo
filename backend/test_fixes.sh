#!/bin/bash

# Quick test to verify the 4 critical fixes

BASE_URL="http://localhost:8000"
USER_ID="test-fixes-$(date +%s)"

echo "Testing 4 critical fixes..."
echo "=============================="

# Test 1: Date parsing (next monday)
echo ""
echo "Test 1: Date parsing with 'next monday'"
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Add task due next monday\",
    \"user_id\": \"$USER_ID\"
  }" | jq -r '.message'

# Test 2: Fuzzy search for "redux thing"
echo ""
echo "Test 2: Fuzzy search (redux thing → Redux store)"
# First add the task
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Add setup for Redux store under work\",
    \"user_id\": \"$USER_ID\"
  }" > /dev/null

# Then try to complete it with fuzzy match
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"I finished working on that redux thing\",
    \"user_id\": \"$USER_ID\"
  }" | jq -r '.message'

# Test 3: Fuzzy search for "contractor quote"
echo ""
echo "Test 3: Fuzzy search (contractor quote → Get quotes from...)"
# First add the task
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Add Get quotes from three contractors\",
    \"user_id\": \"$USER_ID\"
  }" > /dev/null

# Then try to delete it with fuzzy match
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Delete all those contractor quote tasks\",
    \"user_id\": \"$USER_ID\"
  }" | jq -r '.message'

# Test 4: Move to main level
echo ""
echo "Test 4: Move to main level"
# First add tasks
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Add errands under personal\",
    \"user_id\": \"$USER_ID\"
  }" > /dev/null

curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Add grocery shopping under errands\",
    \"user_id\": \"$USER_ID\"
  }" > /dev/null

# Then move to top level
curl -s -X POST "$BASE_URL/agent/process" \
  -H "Content-Type: application/json" \
  -d "{
    \"transcription\": \"Move grocery shopping to the main level\",
    \"user_id\": \"$USER_ID\"
  }" | jq -r '.message'

echo ""
echo "=============================="
echo "Tests complete!"
