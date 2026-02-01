#!/bin/bash

USER_ID="cat-limit-test"
BASE_URL="http://localhost:8001/api/agent/process"

echo "Creating 5 categories explicitly..."

curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add project alpha to Work\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'

curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add buy milk to Personal\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'

curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add guitar to Hobbies\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'

curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add workout to Health\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'

curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add course to Learning\", \"user_id\": \"$USER_ID\"}" | jq -r '.message'

echo ""
echo "Categories created:"
curl -s "http://localhost:8001/api/tasks?user_id=$USER_ID" | jq -r '.[].category' | sort -u

echo ""
echo "======================================"
echo "Now trying to add 6th category..."
echo "======================================"
curl -s -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -d "{\"transcription\": \"Add volunteer at food bank\", \"user_id\": \"$USER_ID\"}" | jq .
