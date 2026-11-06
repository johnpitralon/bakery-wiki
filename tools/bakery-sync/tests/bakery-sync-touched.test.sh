#!/usr/bin/env bash
# Tests for bakery-sync-touched.sh: recording the source/wiki files a session
# edits, agent-neutrally (claude file_path, cursor file_path, codex
# apply_patch parsing), attribution (repo vs wiki dir), and path
# normalisation (trailing slash / doubled slash / outside-repo). Uses a
# temp STATE_DIR — never touches the real ~/.claude/state/bakery-sync.
#
# Run: bash tools/bakery-sync/tests/bakery-sync-touched.test.sh
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOUCHED_HOOK="$HOOKS_DIR/bakery-sync-touched.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mkdir -p "$TMPROOT/state" "$TMPROOT/wiki" "$TMPROOT/repo"
STATE_DIR="$(cd "$TMPROOT/state" && pwd -P)"
WIKI_DIR="$(cd "$TMPROOT/wiki" && pwd -P)"
REPO_DIR="$(cd "$TMPROOT/repo" && pwd -P)"

export BAKERY_SYNC_STATE_DIR="$STATE_DIR"
export BAKERY_SYNC_WIKI_DIR="$WIKI_DIR"

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

check_absent() {
    local label="$1" file="$2"
    if [ ! -f "$file" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — $file should not exist, contains: $(cat "$file")"
        FAIL=$((FAIL+1))
    fi
}

new_state() {
    # new_state <sid> -> creates a bare state snapshot line for REPO_DIR
    printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$(date +%s)" > "$STATE_DIR/$1"
}

run_touched() {
    # run_touched <json> <agent...>
    local json="$1"; shift
    printf '%s' "$json" | "$TOUCHED_HOOK" "$@"
}

echo "=== claude: file_path inside repo -> .touched (repo-relative) ==="
new_state c1
run_touched "$(printf '{"session_id":"c1","tool_input":{"file_path":"%s/src/foo.go"}}' "$REPO_DIR")" --agent claude
check_eq "claude: repo-relative path recorded" "src/foo.go" "$(cat "$STATE_DIR/c1.touched" 2>/dev/null)"

echo "=== cursor: file_path -> .touched (same shape, own session id field) ==="
new_state cu1
run_touched "$(printf '{"conversation_id":"cu1","file_path":"%s/src/bar.go"}' "$REPO_DIR")" --agent cursor
check_eq "cursor: repo-relative path recorded" "src/bar.go" "$(cat "$STATE_DIR/cu1.touched" 2>/dev/null)"

echo "=== codex: apply_patch with Add/Update/Move lines (relative, cwd-prefixed) ==="
new_state cx1
patch=$'*** Add File: src/added.go\ncontent A\n*** Update File: src/updated.go\ncontent B\n*** Move to: src/moved.go\ncontent C'
run_touched "$(jq -n --arg cwd "$REPO_DIR" --arg patch "$patch" '{session_id:"cx1", tool_name:"apply_patch", tool_input:{input:$patch}, cwd:$cwd}')" --agent codex
sorted=$(sort "$STATE_DIR/cx1.touched" 2>/dev/null | tr '\n' ',')
check_eq "codex: Add/Update/Move all recorded" "src/added.go,src/moved.go,src/updated.go," "$sorted"

echo "=== codex: Bash tool -> nothing recorded ==="
new_state cx2
run_touched "$(jq -n --arg cwd "$REPO_DIR" '{session_id:"cx2", tool_name:"Bash", tool_input:{command:"echo hi"}, cwd:$cwd}')" --agent codex
check_absent "codex: Bash tool produces no .touched file" "$STATE_DIR/cx2.touched"

echo "=== path outside repo -> nothing recorded ==="
new_state c2
run_touched "$(printf '{"session_id":"c2","tool_input":{"file_path":"/tmp/outside-%s/nope.go"}}' "$$")" --agent claude
check_absent "outside-repo path recorded nothing" "$STATE_DIR/c2.touched"

echo "=== path inside BAKERY_SYNC_WIKI_DIR -> .wikitouched (wiki-relative) ==="
new_state c3
mkdir -p "$WIKI_DIR/wiki"
run_touched "$(printf '{"session_id":"c3","tool_input":{"file_path":"%s/wiki/index.md"}}' "$WIKI_DIR")" --agent claude
check_eq "wiki-dir path recorded into .wikitouched" "wiki/index.md" "$(cat "$STATE_DIR/c3.wikitouched" 2>/dev/null)"
check_absent "wiki-dir path NOT recorded into .touched" "$STATE_DIR/c3.touched"

echo "=== trailing-slash / doubled-slash variants normalise ==="
new_state c4
run_touched "$(printf '{"session_id":"c4","tool_input":{"file_path":"%s//src//dupslash.go"}}' "$REPO_DIR")" --agent claude
check_eq "doubled-slash path normalises to a clean repo-relative path" "src/dupslash.go" "$(cat "$STATE_DIR/c4.touched" 2>/dev/null)"

new_state c5
run_touched "$(printf '{"session_id":"c5","tool_input":{"file_path":"%s/src/trailing.go/"}}' "$REPO_DIR")" --agent claude
check_eq "trailing-slash path normalises" "src/trailing.go" "$(cat "$STATE_DIR/c5.touched" 2>/dev/null)"

echo "=== no state file for session -> exit 0, no crash ==="
OUT=$(printf '{"session_id":"nope","tool_input":{"file_path":"%s/src/x.go"}}' "$REPO_DIR" | "$TOUCHED_HOOK" --agent claude 2>&1)
RC=$?
check_eq "missing state file -> exit 0" "0" "$RC"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
