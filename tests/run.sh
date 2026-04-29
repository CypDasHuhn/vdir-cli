#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

# Build first
echo "Building vdir-cli..."
cd "$REPO_ROOT"
zig build 2>&1
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

run_suite() {
    local file="$1"
    local name
    name=$(basename "$file" .sh)

    # Run in a subshell so each suite's PASS/FAIL are isolated
    OUTPUT=$(bash "$file" 2>&1)
    EXIT=$?

    echo "$OUTPUT"

    # Extract counts from summary line "  N/T passed"
    SUMMARY_LINE=$(echo "$OUTPUT" | grep -E '^\s+[0-9]+/[0-9]+ passed' | tail -1)
    SUITE_PASS=$(echo "$SUMMARY_LINE" | grep -oP '[0-9]+(?=/)' || echo 0)
    SUITE_TOTAL=$(echo "$SUMMARY_LINE" | grep -oP '(?<=/)[0-9]+' || echo 0)
    SUITE_FAIL=$((SUITE_TOTAL - SUITE_PASS))

    TOTAL_PASS=$((TOTAL_PASS + SUITE_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + SUITE_FAIL))
}

# Run all test suites
for suite in \
    test_init \
    test_cd \
    test_ls \
    test_mkdir \
    test_ln \
    test_rm \
    test_mv \
    test_info \
    test_set \
    test_mkq \
    test_query \
    test_compiler \
    test_data_format \
; do
    run_suite "$TESTS_DIR/${suite}.sh"
    echo ""
done

TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOTAL: ${TOTAL_PASS}/${TOTAL} passed"
if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo "  ${TOTAL_FAIL} FAILED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
