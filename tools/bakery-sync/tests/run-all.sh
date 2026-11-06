#!/usr/bin/env bash
# Runs every bakery-sync test file and summarises. Exits non-zero if any file
# fails. Each test file builds and cleans up its own temp HOME/state dirs —
# none of them touch the real ~/.claude, ~/.codex, ~/.cursor, or bakery-wiki.
#
# Run: bash tools/bakery-sync/tests/run-all.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_FILES="lib.test.sh bakery-sync-session-start.test.sh bakery-sync-stop.test.sh bakery-sync-touched.test.sh bakery-sync-optin.test.sh install.test.sh isolation.test.sh"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=""

for f in $TEST_FILES; do
    path="$TESTS_DIR/$f"
    echo "############################################################"
    echo "# $f"
    echo "############################################################"
    if [ ! -f "$path" ]; then
        echo "FAIL: missing test file: $path"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
        FAILED_FILES="$FAILED_FILES $f"
        continue
    fi

    out=$(bash "$path" 2>&1)
    rc=$?
    printf '%s\n' "$out"

    # Pull "N passed, M failed" out of this file's own summary line and fold
    # it into the totals, so the final line reflects every individual check
    # across all files (not just per-file pass/fail).
    counts=$(printf '%s\n' "$out" | grep -Eo '[0-9]+ passed, [0-9]+ failed' | tail -n1)
    if [ -n "$counts" ]; then
        file_pass=$(printf '%s' "$counts" | grep -Eo '^[0-9]+')
        file_fail=$(printf '%s' "$counts" | grep -Eo '[0-9]+ failed' | grep -Eo '^[0-9]+')
        TOTAL_PASS=$((TOTAL_PASS + file_pass))
        TOTAL_FAIL=$((TOTAL_FAIL + file_fail))
    fi

    if [ "$rc" -ne 0 ]; then
        FAILED_FILES="$FAILED_FILES $f"
    fi
    echo
done

echo "############################################################"
echo "=== run-all: $TOTAL_PASS passed, $TOTAL_FAIL failed ==="
if [ -n "$FAILED_FILES" ]; then
    echo "=== FAILED FILES:$FAILED_FILES"
else
    echo "=== all test files green"
fi

[ "$TOTAL_FAIL" -eq 0 ] && [ -z "$FAILED_FILES" ]
