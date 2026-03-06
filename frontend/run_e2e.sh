#!/bin/bash
# Frontend E2E integration test runner
# Usage: ./run_e2e.sh [test_file]
#
# Prerequisites:
#   - Android emulator running (adb devices)
#   - Docker backend on port 8001 (or override with BACKEND_PORT)
#
# Examples:
#   ./run_e2e.sh                                              # All flows
#   ./run_e2e.sh integration_test/flows/create_task_test.dart  # Single flow

set -e

BACKEND_PORT="${BACKEND_PORT:-8001}"
API_BASE_URL="${API_BASE_URL:-http://10.0.2.2:${BACKEND_PORT}/api}"

cd "$(dirname "$0")"

# Check backend health
echo "Checking backend on :${BACKEND_PORT}..."
if ! curl -sf "http://localhost:${BACKEND_PORT}/health" > /dev/null 2>&1; then
  echo "ERROR: Backend not running on :${BACKEND_PORT}"
  echo "  Start with: cd backend && docker-compose up --build -d"
  exit 1
fi
echo "Backend healthy."

# Check emulator
echo "Checking Android emulator..."
if ! adb devices 2>/dev/null | grep -q "emulator"; then
  echo "ERROR: No Android emulator running"
  echo "  Start with: emulator -avd <name> &"
  exit 1
fi
echo "Emulator detected."

TEST_FILE="${1:-integration_test/}"

echo ""
echo "Running frontend E2E: $TEST_FILE"
echo "  API_BASE_URL=$API_BASE_URL"
echo "  TEST_MODE=true"
echo ""

flutter test "$TEST_FILE" -d emulator \
  --dart-define=TEST_MODE=true \
  --dart-define="API_BASE_URL=$API_BASE_URL"
