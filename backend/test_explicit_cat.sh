#!/bin/bash

echo "Test 1: Add to Work (explicit)"
curl -s -X POST http://localhost:8001/api/agent/process \
  -H "Content-Type: application/json" \
  -d '{"transcription": "Add API project to Work category", "user_id": "explicit-test"}' | jq '{success, message, category: .data.category}'

echo ""
echo "Test 2: Add to Learning (explicit)"
curl -s -X POST http://localhost:8001/api/agent/process \
  -H "Content-Type: application/json" \
  -d '{"transcription": "Add Python course to Learning category", "user_id": "explicit-test"}' | jq '{success, message, category: .data.category}'
