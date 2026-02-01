#!/bin/bash

USER_ID="limit-test-final"
BASE_URL="http://localhost:8001/api/agent/process"

echo "Testing 5-category limit feature"
echo "=================================="
echo ""

# Create 5 categories
echo "Step 1: Creating 5 categories..."
curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add backend project to Work", "user_id": "'"$USER_ID"'"}' > /dev/null
echo "  ✓ Work"

curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add groceries to Personal", "user_id": "'"$USER_ID"'"}' > /dev/null
echo "  ✓ Personal"

curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add piano practice to Hobbies", "user_id": "'"$USER_ID"'"}' > /dev/null
echo "  ✓ Hobbies"

curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add dentist appointment to Health", "user_id": "'"$USER_ID"'"}' > /dev/null
echo "  ✓ Health"

curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add Spanish lessons to Learning", "user_id": "'"$USER_ID"'"}' > /dev/null
echo "  ✓ Learning"

echo ""
echo "Step 2: Checking categories created..."
curl -s "http://localhost:8001/api/tasks?user_id=$USER_ID" | jq -r '.[].category' | sort -u
echo ""

echo "Step 3: Trying to add 6th category (should be blocked)..."
curl -s -X POST "$BASE_URL" -H "Content-Type: application/json" -d '{"transcription": "Add volunteer at food bank", "user_id": "'"$USER_ID"'"}' | jq '.'
