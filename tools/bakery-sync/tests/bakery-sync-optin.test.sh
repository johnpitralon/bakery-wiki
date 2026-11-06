#!/usr/bin/env bash
# Tests for bakery-sync-optin.sh (the per-clone on/off/status marker) and the
# session-start "ask-once" flow it feeds into (org-repo detection, 24h
# throttle, source=startup gating, agent-neutral context emission). Uses a
# temp STATE_DIR and disposable git repos — never touches real ~/.claude
# state or any real repo.
#
# Run: bash tools/bakery-sync/tests/bakery-sync-optin.test.sh
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIN_SCRIPT="$HOOKS_DIR/bakery-sync-optin.sh"
SESSION_START_HOOK="$HOOKS_DIR/bakery-sync-session-start.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mkdir -p "$TMPROOT/state"
STATE_DIR="$(cd "$TMPROOT/state" && pwd -P)"
export BAKERY_SYNC_STATE_DIR="$STATE_DIR"
# No config, no wiki dir: keeps the real ~/.bakery-sync/config (and with it
# the stale-install hint against the real wiki clone) out of these tests.
export BAKERY_SYNC_HOME="$TMPROOT/home"
unset BAKERY_SYNC_WIKI_DIR

PASS=0
FAIL=0

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected [$expected], got [$actual]"
        FAIL=$((FAIL+1))
    fi
}

check_true() {
    local label="$1" cond="$2"
    if [ "$cond" = "true" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label"
        FAIL=$((FAIL+1))
    fi
}

mk_repo() {
    # mk_repo <name> -> prints resolved absolute path of a fresh git repo
    local name="$1"
    local dir="$TMPROOT/$name"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name Test
    git -C "$dir" commit -q --allow-empty -m init
    (cd "$dir" && pwd -P)
}

# =============================================================================
echo "=== bakery-sync-optin.sh: status / on / off ==="

R1="$(mk_repo repo1)"
cat > "$R1/CLAUDE.md" <<'EOF'
## Bakery Wiki sync (blocking rule)
EOF

check_eq "status on repo with CLAUDE.md switch = 'on instructions'" \
    "on instructions" "$("$OPTIN_SCRIPT" status --repo "$R1")"

check_eq "off -> 'off marker' (overrides instructions)" \
    "off marker" "$("$OPTIN_SCRIPT" off --repo "$R1")"

check_eq "status still reports 'off marker' after off" \
    "off marker" "$("$OPTIN_SCRIPT" status --repo "$R1")"

R2="$(mk_repo repo2)"   # no CLAUDE.md, no AGENTS.md
check_eq "status on bare repo (no switch, no marker) = 'off none'" \
    "off none" "$("$OPTIN_SCRIPT" status --repo "$R2")"

check_eq "on -> 'on marker' on a repo with no instruction file" \
    "on marker" "$("$OPTIN_SCRIPT" on --repo "$R2")"

check_eq "status confirms 'on marker'" \
    "on marker" "$("$OPTIN_SCRIPT" status --repo "$R2")"

echo "=== bakery-sync-optin.sh: bad usage ==="
"$OPTIN_SCRIPT" bogus >/dev/null 2>&1
check_eq "unknown subcommand exits 1" "1" "$?"

"$OPTIN_SCRIPT" status --repo /nonexistent-not-a-repo-xyz >/dev/null 2>&1
check_eq "non-repo path exits 1" "1" "$?"

# =============================================================================
echo "=== session-start: off marker means no snapshot even after off ==="

start_out=$(printf '{"session_id":"opt1","cwd":"%s","source":"startup"}' "$R1" | "$SESSION_START_HOOK" --agent claude)
check_eq "session-start silent (no context) when marker is off" "" "$start_out"
if [ -f "$STATE_DIR/opt1" ]; then
    echo "FAIL: session-start snapshotted a marker-off repo"
    FAIL=$((FAIL+1))
else
    echo "PASS: session-start did not snapshot a marker-off repo"
    PASS=$((PASS+1))
fi

echo "=== session-start: on marker (bare repo) -> snapshot taken ==="
start_out2=$(printf '{"session_id":"opt2","cwd":"%s","source":"startup"}' "$R2" | "$SESSION_START_HOOK" --agent claude)
if [ -f "$STATE_DIR/opt2" ]; then
    echo "PASS: session-start snapshotted a marker-on repo"
    PASS=$((PASS+1))
else
    echo "FAIL: session-start did not snapshot a marker-on repo: $(cat "$STATE_DIR/opt2" 2>&1)"
    FAIL=$((FAIL+1))
fi

# =============================================================================
echo "=== session-start: ask-once flow ==="

R3="$(mk_repo repo3)"   # no switch, no marker
git -C "$R3" remote add origin git@github.com:johnpitralon/AskOnceRepo.git

ask_out1=$(printf '{"session_id":"ask1","cwd":"%s","source":"startup"}' "$R3" | "$SESSION_START_HOOK" --agent claude)
if printf '%s' "$ask_out1" | grep -q '\[bakery-sync\]'; then
    echo "PASS: org repo, no marker, source=startup -> ask-once context emitted (claude)"
    PASS=$((PASS+1))
else
    echo "FAIL: expected [bakery-sync] context, got: $ask_out1"
    FAIL=$((FAIL+1))
fi

ask_out2=$(printf '{"session_id":"ask2","cwd":"%s","source":"startup"}' "$R3" | "$SESSION_START_HOOK" --agent claude)
check_eq "second run within 24h throttle -> silent" "" "$ask_out2"

ask_out3=$(printf '{"session_id":"ask3","cwd":"%s","source":"resume"}' "$R3" | "$SESSION_START_HOOK" --agent claude)
check_eq "source=resume -> silent (ask-once only fires on startup)" "" "$ask_out3"

R4="$(mk_repo repo4)"
git -C "$R4" remote add origin git@github.com:someoneelse/NotKytary.git
ask_out4=$(printf '{"session_id":"ask4","cwd":"%s","source":"startup"}' "$R4" | "$SESSION_START_HOOK" --agent claude)
check_eq "non-org remote -> silent" "" "$ask_out4"

echo "=== session-start: ask-once, cursor emits additional_context JSON ==="
R5="$(mk_repo repo5)"
git -C "$R5" remote add origin git@github.com:johnpitralon/AskOnceCursor.git
ask_out5=$(printf '{"conversation_id":"ask5","cwd":"%s","source":"startup"}' "$R5" | "$SESSION_START_HOOK" --agent cursor)
ctx=$(printf '%s' "$ask_out5" | jq -r '.additional_context // empty' 2>/dev/null)
if printf '%s' "$ctx" | grep -q '\[bakery-sync\]'; then
    echo "PASS: cursor ask-once emits valid JSON with additional_context"
    PASS=$((PASS+1))
else
    echo "FAIL: cursor ask-once JSON malformed or missing context: $ask_out5"
    FAIL=$((FAIL+1))
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
