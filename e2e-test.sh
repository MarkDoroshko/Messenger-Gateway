#!/bin/bash
set -e

BASE_URL="http://localhost:80/api/v1"
PASS=0
FAIL=0

print_result() {
    local test_name="$1"
    local expected_status="$2"
    local actual_status="$3"
    local body="$4"

    if [ "$actual_status" -eq "$expected_status" ]; then
        echo "[PASS] $test_name (HTTP $actual_status)"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $test_name — expected $expected_status, got $actual_status"
        echo "       Body: $body"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================"
echo "E2E Tests for Messenger"
echo "========================================"
echo ""

# --- Test 1: Gateway health ---
echo "--- Gateway ---"
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:80/health)
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "Gateway health" 200 "$STATUS" "$BODY"

# --- Test 2: Internal endpoints blocked ---
echo ""
echo "--- Internal endpoints blocked ---"
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:80/internal/users)
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "GET /internal/users blocked" 403 "$STATUS" "$BODY"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:80/internal/users)
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "POST /internal/users blocked" 403 "$STATUS" "$BODY"

# --- Test 3: Register ---
echo ""
echo "--- Auth: Register ---"
TIMESTAMP=$(date +%s)
EMAIL="test_${TIMESTAMP}@example.com"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$EMAIL\", \"password\": \"password123\", \"display_name\": \"Test User\", \"phone\": \"+7900${TIMESTAMP: -7}\", \"bio\": \"Hello world\"}")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "POST /api/v1/auth/register" 200 "$STATUS" "$BODY"

ACCESS_TOKEN=$(echo "$BODY" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
REFRESH_TOKEN=$(echo "$BODY" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

if [ -n "$ACCESS_TOKEN" ]; then
    echo "       access_token received: ${ACCESS_TOKEN:0:20}..."
else
    echo "       [WARN] No access_token in response"
fi

# --- Test 4: Register duplicate ---
echo ""
echo "--- Auth: Register duplicate ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$EMAIL\", \"password\": \"password123\", \"display_name\": \"Test User\", \"phone\": \"+79001234567\", \"bio\": \"Hello\"}")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "POST /api/v1/auth/register (duplicate)" 409 "$STATUS" "$BODY"

# --- Test 5: Login ---
echo ""
echo "--- Auth: Login ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$EMAIL\", \"password\": \"password123\"}")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "POST /api/v1/auth/login" 200 "$STATUS" "$BODY"

ACCESS_TOKEN=$(echo "$BODY" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
REFRESH_TOKEN=$(echo "$BODY" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

# --- Test 6: Login wrong password ---
echo ""
echo "--- Auth: Login wrong password ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$EMAIL\", \"password\": \"wrong\"}")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "POST /api/v1/auth/login (wrong password)" 401 "$STATUS" "$BODY"

# --- Test 7: Refresh token ---
echo ""
echo "--- Auth: Refresh ---"
if [ -n "$REFRESH_TOKEN" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/auth/refresh" \
        -H "Content-Type: application/json" \
        -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")
    BODY=$(echo "$RESPONSE" | head -n -1)
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    print_result "POST /api/v1/auth/refresh" 200 "$STATUS" "$BODY"

    ACCESS_TOKEN=$(echo "$BODY" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
else
    echo "[SKIP] No refresh token available"
fi

# --- Test 8: Get profile ---
echo ""
echo "--- User: Get Profile ---"
if [ -n "$ACCESS_TOKEN" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/profile" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    BODY=$(echo "$RESPONSE" | head -n -1)
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    print_result "GET /api/v1/profile" 200 "$STATUS" "$BODY"
else
    echo "[SKIP] No access token available"
fi

# --- Test 9: Get profile without token ---
echo ""
echo "--- User: Get Profile (no auth) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/profile")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
print_result "GET /api/v1/profile (no auth)" 401 "$STATUS" "$BODY"

# --- Test 10: Update profile ---
echo ""
echo "--- User: Update Profile ---"
if [ -n "$ACCESS_TOKEN" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "$BASE_URL/profile" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -d '{"display_name": "Updated Name", "bio": "Updated bio"}')
    BODY=$(echo "$RESPONSE" | head -n -1)
    STATUS=$(echo "$RESPONSE" | tail -n 1)
    print_result "PATCH /api/v1/profile" 200 "$STATUS" "$BODY"
else
    echo "[SKIP] No access token available"
fi

# --- Summary ---
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
