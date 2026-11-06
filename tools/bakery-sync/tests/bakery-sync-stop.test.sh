#!/usr/bin/env bash
# Tests for bakery-sync-stop.sh: the update -> commit -> push lifecycle, the
# 2026-09-05 active-work-window + rewake-cooldown fix, the ack escape hatch,
# and (v2) the agent-neutral rewake shape (claude/codex/cursor), the
# is_enabled() switch (CLAUDE.md, AGENTS.md, and the per-clone marker), and
# the 2026-10-02 .synced record (a completed sync survives /compact).
# Uses a temp STATE_DIR and a temp fake wiki git repo — never touches the
# real ~/.claude/state/bakery-sync or bakery-wiki.
#
# Run: bash tools/bakery-sync/tests/bakery-sync-stop.test.sh
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STOP_HOOK="$HOOKS_DIR/bakery-sync-stop.sh"
ACK_SCRIPT="$HOOKS_DIR/bakery-sync-ack.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

STATE_DIR="$TMPROOT/state"
WIKI_DIR="$TMPROOT/wiki"
REPO_DIR="$TMPROOT/repo"
mkdir -p "$STATE_DIR" "$WIKI_DIR" "$REPO_DIR/.git"
# Resolve away macOS's /var -> /private/var symlink so paths compared inside
# the hooks (which git resolves physically) match what we put in state files.
STATE_DIR="$(cd "$STATE_DIR" && pwd -P)"
WIKI_DIR="$(cd "$WIKI_DIR" && pwd -P)"
REPO_DIR="$(cd "$(dirname "$REPO_DIR")" && pwd -P)/$(basename "$REPO_DIR")"

export BAKERY_SYNC_STATE_DIR="$STATE_DIR"
export BAKERY_SYNC_WIKI_DIR="$WIKI_DIR"
export BAKERY_SYNC_ACTIVE_WINDOW=600
export BAKERY_SYNC_COOLDOWN=300

# --- fake wiki repo (real git, no remote needed: `@{u}` fails -> `|| echo 0`,
# so wiki_ahead is always 0 here regardless of push state) ------------------
git -C "$WIKI_DIR" init -q
git -C "$WIKI_DIR" config user.email test@example.com
git -C "$WIKI_DIR" config user.name "Test"
echo "# wiki" > "$WIKI_DIR/README.md"
mkdir -p "$WIKI_DIR/pages"
touch "$WIKI_DIR/pages/.gitkeep"   # tracks pages/ so a later new file inside
                                   # shows as "?? pages/foo.md", not "?? pages/"
                                   # (git status --porcelain collapses an
                                   # untracked dir to its own path otherwise)
git -C "$WIKI_DIR" add README.md pages/.gitkeep
git -C "$WIKI_DIR" commit -q -m "init wiki"

# --- fake source repo with the bakery-sync rule -------------------------------
cat > "$REPO_DIR/CLAUDE.md" <<'EOF'
## Bakery Wiki sync (blocking rule)
test fixture
EOF
git -C "$REPO_DIR" init -q >/dev/null 2>&1 || true
git -C "$REPO_DIR" config user.email test@example.com 2>/dev/null || true
git -C "$REPO_DIR" config user.name "Test" 2>/dev/null || true

PASS=0
FAIL=0

check() {
    # check <label> <expected_exit> <actual_exit> [<actual_stdout>] [<grep_pattern>]
    local label="$1" expected="$2" actual="$3" stdout="${4:-}" pattern="${5:-}"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $label — expected exit $expected, got $actual"
        FAIL=$((FAIL+1))
        return
    fi
    if [ -n "$pattern" ] && ! printf '%s' "$stdout" | grep -q "$pattern"; then
        echo "FAIL: $label — exit code ok ($actual) but stdout missing pattern: $pattern"
        FAIL=$((FAIL+1))
        return
    fi
    echo "PASS: $label (exit $actual)"
    PASS=$((PASS+1))
}

run_hook() {
    # run_hook <session_id> [--agent X]  -> sets RC and OUT
    local sid="$1"; shift
    OUT=$(printf '{"session_id":"%s"}' "$sid" | "$STOP_HOOK" "$@" 2>/tmp/bakery-sync-test-stderr)
    RC=$?
}

ago() {
    # ago <minutes> -> touch -t timestamp that many minutes in the past
    date -v-"$1"M +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$1 minutes" +%Y%m%d%H%M.%S
}

lastfire_rewind() {
    # lastfire_rewind <session_id> <seconds> — push .lastfire's epoch back
    local sid="$1"
    local secs="$2"
    local f="$STATE_DIR/$sid.lastfire"
    [ -f "$f" ] || { echo "  (no .lastfire for $sid to rewind)"; return; }
    read -r lf_sig lf_stage lf_ts < "$f"
    printf '%s %s %s\n' "$lf_sig" "$lf_stage" "$((lf_ts - secs))" > "$f"
}

echo "=== session t1: update -> commit -> done ==="

# state_file: repo \t start_head \t start_ts (session started "now", after
# the wiki's init commit above, so that commit alone doesn't satisfy "wiki
# touched" — matches how bakery-sync-session-start.sh records it).
start_ts=$(date +%s)
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts" > "$STATE_DIR/t1"
echo "src/foo.go" > "$STATE_DIR/t1.touched"

# 1. .touched non-empty, no .wikitouched -> stage update -> exit 2 (first fire)
run_hook t1
check "1: first fire, stage=update" 2 "$RC" "$OUT" "bakery-wiki"

# 2. immediately again -> exit 0 (cooldown)
run_hook t1
check "2: immediate repeat -> cooldown silences" 0 "$RC" "$OUT"

# 3. rewind .lastfire epoch by 400s (> COOLDOWN=300) -> cooldown expired -> exit 2
lastfire_rewind t1 400
run_hook t1
check "3: cooldown expired -> fires again" 2 "$RC" "$OUT" "bakery-wiki"

lastfire_after_3=$(cat "$STATE_DIR/t1.lastfire" 2>/dev/null || echo "")

# 4. create .wikitouched for a file we actually dirty in the fake wiki repo,
#    fresh mtime -> active-work window -> exit 0, and no new .lastfire write
#    for stage=commit (guard 1 short-circuits before guard 2 even runs).
echo "draft content" > "$WIKI_DIR/pages/foo.md"
echo "pages/foo.md" > "$STATE_DIR/t1.wikitouched"   # fresh mtime (just written)
run_hook t1
check "4: active wiki-work window -> silent" 0 "$RC" "$OUT"

lastfire_after_4=$(cat "$STATE_DIR/t1.lastfire" 2>/dev/null || echo "")
if [ "$lastfire_after_4" = "$lastfire_after_3" ]; then
    echo "PASS: 4b: no new .lastfire written for stage=commit while active window holds"
    PASS=$((PASS+1))
else
    echo "FAIL: 4b: .lastfire changed during the active window (expected untouched)"
    echo "  before: $lastfire_after_3"
    echo "  after:  $lastfire_after_4"
    FAIL=$((FAIL+1))
fi

# 5. age .wikitouched past the active window (20 min ago) -> window expired ->
#    falls through to real staging -> stage=commit -> exit 2
touch -t "$(date -v-20M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-20 minutes' +%Y%m%d%H%M.%S)" "$STATE_DIR/t1.wikitouched"
run_hook t1
check "5: active window expired -> stage=commit fires" 2 "$RC" "$OUT" "neuncommitted"

# 6. commit the wiki change -> porcelain clean, no upstream so wiki_ahead=0
#    -> stage="" -> exit 0, .wikitouched removed. The source edit happened
#    before the wiki work (backdated), which is what makes the commit count
#    (2026-09-25: wiki work is judged against the last source edit).
touch -t "$(ago 25)" "$STATE_DIR/t1.touched"
git -C "$WIKI_DIR" add pages/foo.md
git -C "$WIKI_DIR" commit -q -m "add foo page"
run_hook t1
check "6: fully synced -> done" 0 "$RC" "$OUT"
if [ -f "$STATE_DIR/t1.wikitouched" ]; then
    echo "FAIL: 6b: .wikitouched should have been removed on completion"
    FAIL=$((FAIL+1))
else
    echo "PASS: 6b: .wikitouched removed on completion"
    PASS=$((PASS+1))
fi

echo "=== session t2: ack path ==="

# Fresh session, started after all commits above so the prior wiki commits
# don't retroactively count as "touched" for t2.
start_ts2=$(date +%s)
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts2" > "$STATE_DIR/t2"
echo "src/bar.go" > "$STATE_DIR/t2.touched"

# 7a. first fire, stage=update
run_hook t2
check "7a: t2 first fire, stage=update" 2 "$RC" "$OUT" "bakery-wiki"

# Roll back cooldown so the post-ack check below is attributable to the ack,
# not to the cooldown guard (both would otherwise return exit 0).
lastfire_rewind t2 400

# 7b. ack this exact state
ack_out=$("$ACK_SCRIPT" t2 2>&1)
ack_rc=$?
if [ "$ack_rc" -eq 0 ]; then
    echo "PASS: 7b: bakery-sync-ack.sh succeeded ($ack_out)"
    PASS=$((PASS+1))
else
    echo "FAIL: 7b: bakery-sync-ack.sh failed: $ack_out"
    FAIL=$((FAIL+1))
fi

# 7c. same state, cooldown already expired -> ack alone silences -> exit 0
run_hook t2
check "7c: acked state -> silent despite expired cooldown" 0 "$RC" "$OUT"

# 7d. new source edit -> new signature -> bypasses ack -> exit 2
echo "src/baz.go" >> "$STATE_DIR/t2.touched"
run_hook t2
check "7d: new signature after ack -> fires again" 2 "$RC" "$OUT" "bakery-wiki"

echo "=== session t3: codex agent rewake shape ==="

start_ts3=$(date +%s)
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts3" > "$STATE_DIR/t3"
echo "src/codex.go" > "$STATE_DIR/t3.touched"

run_hook t3 --agent codex
check "8a: codex firing state -> exit 0" 0 "$RC" "$OUT"
decision=$(printf '%s' "$OUT" | jq -r '.decision // empty' 2>/dev/null)
reason=$(printf '%s' "$OUT" | jq -r '.reason // empty' 2>/dev/null)
if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q "bakery-wiki"; then
    echo "PASS: 8b: codex JSON has decision=block and reason contains bakery-wiki"
    PASS=$((PASS+1))
else
    echo "FAIL: 8b: codex JSON malformed — decision='$decision' reason snippet='${reason:0:60}'"
    FAIL=$((FAIL+1))
fi

echo "=== session t4: cursor agent rewake shape ==="

start_ts4=$(date +%s)
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts4" > "$STATE_DIR/t4"
echo "src/cursor.go" > "$STATE_DIR/t4.touched"

run_hook t4 --agent cursor
check "9a: cursor firing state -> exit 0" 0 "$RC" "$OUT"
followup=$(printf '%s' "$OUT" | jq -r '.followup_message // empty' 2>/dev/null)
if [ -n "$followup" ]; then
    echo "PASS: 9b: cursor JSON has a non-empty followup_message"
    PASS=$((PASS+1))
else
    echo "FAIL: 9b: cursor JSON missing/empty followup_message: $OUT"
    FAIL=$((FAIL+1))
fi

echo "=== session t5: AGENTS.md-only repo (no CLAUDE.md) still fires ==="

AGENTS_REPO_DIR="$TMPROOT/agents-repo"
mkdir -p "$AGENTS_REPO_DIR"
git -C "$AGENTS_REPO_DIR" init -q
cat > "$AGENTS_REPO_DIR/AGENTS.md" <<'EOF'
## Bakery Wiki sync (blocking rule)
test fixture (AGENTS.md, no CLAUDE.md)
EOF

start_ts5=$(date +%s)
printf '%s\t%s\t%s\n' "$AGENTS_REPO_DIR" "deadbeef" "$start_ts5" > "$STATE_DIR/t5"
echo "src/agents.go" > "$STATE_DIR/t5.touched"

run_hook t5
check "10: AGENTS.md-only repo fires" 2 "$RC" "$OUT" "bakery-wiki"

echo "=== session t6: marker off silences a CLAUDE.md-enabled repo ==="

MARKER_OFF_REPO="$TMPROOT/marker-off-repo"
mkdir -p "$MARKER_OFF_REPO"
git -C "$MARKER_OFF_REPO" init -q
cat > "$MARKER_OFF_REPO/CLAUDE.md" <<'EOF'
## Bakery Wiki sync (blocking rule)
test fixture (should be silenced by marker off)
EOF
gcd=$(git -C "$MARKER_OFF_REPO" rev-parse --git-common-dir)
case "$gcd" in /*) : ;; *) gcd="$MARKER_OFF_REPO/$gcd" ;; esac
mkdir -p "$gcd/info"
printf 'off\n' > "$gcd/info/bakery-sync"

start_ts6=$(date +%s)
printf '%s\t%s\t%s\n' "$MARKER_OFF_REPO" "deadbeef" "$start_ts6" > "$STATE_DIR/t6"
echo "src/off.go" > "$STATE_DIR/t6.touched"

run_hook t6
check "11: marker off silences a CLAUDE.md-enabled repo" 0 "$RC" "$OUT"

echo "=== session t7: marker on enables a repo with no instruction file ==="

MARKER_ON_REPO="$TMPROOT/marker-on-repo"
mkdir -p "$MARKER_ON_REPO"
git -C "$MARKER_ON_REPO" init -q
gcd7=$(git -C "$MARKER_ON_REPO" rev-parse --git-common-dir)
case "$gcd7" in /*) : ;; *) gcd7="$MARKER_ON_REPO/$gcd7" ;; esac
mkdir -p "$gcd7/info"
printf 'on\n' > "$gcd7/info/bakery-sync"

start_ts7=$(date +%s)
printf '%s\t%s\t%s\n' "$MARKER_ON_REPO" "deadbeef" "$start_ts7" > "$STATE_DIR/t7"
echo "src/on.go" > "$STATE_DIR/t7.touched"

run_hook t7
check "12: marker on enables a repo without any instruction file" 2 "$RC" "$OUT" "bakery-wiki"

echo "=== session t8-t10: wiki work is judged against the LAST source edit (2026-09-25) ==="

# t8: session started 30 min ago, wrote + committed the wiki 20 min ago
# (own author), then edited source again just now -> the old wiki commit
# must NOT silence the new change (before the fix it did: commit > start_ts).
start_ts8=$(( $(date +%s) - 1800 ))
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts8" > "$STATE_DIR/t8"
echo "old t8" > "$WIKI_DIR/pages/t8.md"
git -C "$WIKI_DIR" add pages/t8.md
GIT_COMMITTER_DATE="@$(( $(date +%s) - 1200 ))" git -C "$WIKI_DIR" commit -q -m "t8 wiki earlier"
echo "src/later.go" > "$STATE_DIR/t8.touched"   # fresh mtime = last source edit now
run_hook t8
check "13: own wiki commit BEFORE the last source edit -> still stage=update" 2 "$RC" "$OUT" "bakery-wiki"

# t9: a teammate's wiki commit after the source edit must not count either
start_ts9=$(( $(date +%s) - 1800 ))
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts9" > "$STATE_DIR/t9"
echo "src/t9.go" > "$STATE_DIR/t9.touched"
touch -t "$(ago 10)" "$STATE_DIR/t9.touched"
echo "foreign" > "$WIKI_DIR/pages/t9.md"
git -C "$WIKI_DIR" add pages/t9.md
git -C "$WIKI_DIR" -c user.email=someone.else@example.com -c user.name=Other commit -q -m "foreign wiki commit"
run_hook t9
check "14: foreign author's wiki commit after the edit -> still stage=update" 2 "$RC" "$OUT" "bakery-wiki"

# t10: own wiki commit AFTER the last source edit (e.g. written through a
# shell, so no .wikitouched) -> synced, silent
start_ts10=$(( $(date +%s) - 1800 ))
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts10" > "$STATE_DIR/t10"
echo "src/t10.go" > "$STATE_DIR/t10.touched"
touch -t "$(ago 10)" "$STATE_DIR/t10.touched"
echo "own" > "$WIKI_DIR/pages/t10.md"
git -C "$WIKI_DIR" add pages/t10.md
git -C "$WIKI_DIR" commit -q -m "own wiki commit after the edit"
run_hook t10
check "15: own wiki commit after the last source edit -> silent" 0 "$RC" "$OUT"

# t10b: another source edit after that commit -> fires again
sleep 1
echo "src/t10b.go" >> "$STATE_DIR/t10.touched"
run_hook t10
check "16: new source edit after the wiki commit -> fires again" 2 "$RC" "$OUT" "bakery-wiki"

echo "=== session t11: completed sync survives /compact (2026-10-02) ==="

# Regression for cms-web-react-nodejs 2. 10. (session ecdea2b1): wiki edited
# via tools, committed and pushed, Stop said "done" and cleared .wikitouched;
# a /compact re-fired SessionStart; the next Stop re-listed every touched
# file as "wiki not updated". Here the commit carries another identity (a
# subagent / other clone), so own_wiki_commit can't vouch for it either —
# after .wikitouched is gone, only the .synced record can.
SESSION_START_HOOK="$HOOKS_DIR/bakery-sync-session-start.sh"
start_ts11=$(( $(date +%s) - 1800 ))
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts11" > "$STATE_DIR/t11"
sleep 1   # own-author wiki commits of t8/t10 must predate this source edit
echo "src/t11.go" > "$STATE_DIR/t11.touched"
echo "t11" > "$WIKI_DIR/pages/t11.md"
echo "pages/t11.md" > "$STATE_DIR/t11.wikitouched"
git -C "$WIKI_DIR" add pages/t11.md
git -C "$WIKI_DIR" -c user.email=subagent@example.com commit -q -m "t11 wiki"
run_hook t11
check "17a: wiki edited + committed -> done" 0 "$RC" "$OUT"
if [ -f "$STATE_DIR/t11.synced" ] && [ ! -f "$STATE_DIR/t11.wikitouched" ]; then
    echo "PASS: 17b: completion recorded in .synced, .wikitouched cleared"
    PASS=$((PASS+1))
else
    echo "FAIL: 17b: expected .synced present and .wikitouched gone"
    FAIL=$((FAIL+1))
fi

printf '{"session_id":"t11","cwd":"%s","source":"compact"}' "$REPO_DIR" | "$SESSION_START_HOOK" >/dev/null 2>&1
run_hook t11
check "17c: after /compact, unchanged footprint -> still done" 0 "$RC" "$OUT"

# Re-editing a file already in the footprint is a new change (sort -u'd
# signature would not move; the footprint version must).
sleep 1
echo "src/t11.go" >> "$STATE_DIR/t11.touched"
run_hook t11
check "17d: re-edit of an already-synced file -> fires again" 2 "$RC" "$OUT" "src/t11.go"

# Draft specs stay ignored: a spec-only edit after a sync keeps it done.
start_ts12=$(( $(date +%s) - 1800 ))
printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$start_ts12" > "$STATE_DIR/t12"
echo "src/t12.go" > "$STATE_DIR/t12.touched"
touch -t "$(ago 25)" "$STATE_DIR/t12.touched"
echo "t12" > "$WIKI_DIR/pages/t12.md"
echo "pages/t12.md" > "$STATE_DIR/t12.wikitouched"
touch -t "$(ago 20)" "$STATE_DIR/t12.wikitouched"
git -C "$WIKI_DIR" add pages/t12.md
git -C "$WIKI_DIR" -c user.email=subagent@example.com commit -q -m "t12 wiki"
run_hook t12
check "18a: t12 synced -> done" 0 "$RC" "$OUT"
echo "docs/superpowers/specs/draft.md" >> "$STATE_DIR/t12.touched"
run_hook t12
check "18b: draft-spec edit after a completed sync -> still done" 0 "$RC" "$OUT"

echo "=== delegation + Codex (2026-10-19) ==="

DELEGATED_SCRIPT="$HOOKS_DIR/bakery-sync-delegated.sh"
# Other wiki commits/edits earlier in this file must predate the source edits
# below (own_wiki_commit needs a commit strictly newer than .touched).
sleep 1

run_hook_json() {
    # run_hook_json <session_id> <extra-json-fields-or-""> [--agent X]
    local sid="$1" extra="$2"; shift 2
    OUT=$(printf '{"session_id":"%s"%s}' "$sid" "$extra" | "$STOP_HOOK" "$@" 2>/dev/null)
    RC=$?
}

new_session() {
    # new_session <id> <file> — a session that edited <file>, wiki untouched
    printf '%s\t%s\t%s\n' "$REPO_DIR" "deadbeef" "$(date +%s)" > "$STATE_DIR/$1"
    echo "$2" > "$STATE_DIR/$1.touched"
}

# Codex: dedicated update message — spawn_agent + delegated.sh, correct log
# path, and wait_agent only as the "don't".
new_session t20 src/t20.go
run_hook_json t20 "" --agent codex
reason=$(printf '%s' "$OUT" | jq -r '.reason // empty')
check "20a: codex update -> block JSON" 0 "$RC" "$OUT" '"decision"'
check "20b: codex message tells to spawn_agent" 0 0 "$reason" "spawn_agent"
check "20c: codex message gives bakery-sync-delegated.sh t20" 0 0 "$reason" "bakery-sync-delegated.sh t20"
check "20d: codex message tells to append at the END of wiki/log.md" 0 0 "$reason" "KONEC wiki/log.md"
if printf '%s' "$reason" | grep -qF "wiki/log/"; then
    echo "FAIL: 20e: message still mentions monthly wiki/log/ archives"; FAIL=$((FAIL+1))
else
    echo "PASS: 20e: message does not mention monthly wiki/log/ archives"; PASS=$((PASS+1))
fi
check "20f: wait_agent only appears as the prohibition" 0 0 "$reason" "NEvolej wait_agent"
if [ "$(printf '%s' "$reason" | grep -o 'wait_agent' | wc -l | tr -d ' ')" = "1" ]; then
    echo "PASS: 20g: wait_agent mentioned exactly once"; PASS=$((PASS+1))
else
    echo "FAIL: 20g: wait_agent mentioned more than once"; FAIL=$((FAIL+1))
fi

new_session t20b src/t20b.go
run_hook_json t20b ""
check "20h: claude message mentions delegated.sh too" 2 "$RC" "$OUT" "bakery-sync-delegated.sh t20b"
check "20i: claude message tells to append at the END of wiki/log.md" 2 "$RC" "$OUT" "KONEC wiki/log.md"

# stop_hook_active (Codex): already continuing after a block -> never chain.
new_session t21 src/t21.go
run_hook_json t21 ',"stop_hook_active":true' --agent codex
check "21a: codex stop_hook_active=true -> exit 0" 0 "$RC"
check "21b: ... and prints nothing" 0 "${#OUT}"
run_hook_json t21 ',"stop_hook_active":false' --agent codex
check "21c: codex stop_hook_active=false -> still blocks" 0 "$RC" "$OUT" '"decision"'
new_session t21b src/t21b.go
run_hook_json t21b ',"stop_hook_active":true'
check "21d: claude is not affected by stop_hook_active" 2 "$RC" "$OUT" "bakery-wiki"

# Delegation guard.
new_session t22 src/t22.go
"$DELEGATED_SCRIPT" t22 >/dev/null
check "22a: .delegated written" 0 "$([ -f "$STATE_DIR/t22.delegated" ] && echo 0 || echo 1)"
run_hook_json t22 "" --agent codex
check "22b: delegated + same footprint -> silent" 0 "$RC"
check "22c: ... no output" 0 "${#OUT}"
run_hook_json t22 ""
check "22d: ... also for claude (exit 0)" 0 "$RC"

read -r dg_fp dg_ts < "$STATE_DIR/t22.delegated"
printf '%s %s\n' "$dg_fp" "$(( dg_ts - 2000 ))" > "$STATE_DIR/t22.delegated"
run_hook_json t22 "" --agent codex
check "22e: window expired -> reminder returns" 0 "$RC" "$OUT" "spawn_agent"

new_session t23 src/t23.go
"$DELEGATED_SCRIPT" t23 >/dev/null
echo "src/t23.go" >> "$STATE_DIR/t23.touched"
run_hook_json t23 ""
check "23: new source edit invalidates the delegation" 2 "$RC" "$OUT" "bakery-wiki"

# BAKERY_SYNC_DELEGATE_WINDOW is honoured (window 1 s, declaration 5 s old).
new_session t24 src/t24.go
"$DELEGATED_SCRIPT" t24 >/dev/null
read -r dg_fp dg_ts < "$STATE_DIR/t24.delegated"
printf '%s %s\n' "$dg_fp" "$(( dg_ts - 5 ))" > "$STATE_DIR/t24.delegated"
OUT=$(printf '{"session_id":"t24"}' | BAKERY_SYNC_DELEGATE_WINDOW=1 "$STOP_HOOK" 2>/dev/null); RC=$?
check "24: BAKERY_SYNC_DELEGATE_WINDOW=1 -> 5 s old declaration expired" 2 "$RC" "$OUT" "bakery-wiki"

# delegated.sh refuses a session without a tracked footprint.
"$DELEGATED_SCRIPT" t-nope >/dev/null 2>&1
check "25: delegated.sh without .touched -> exit 1" 1 "$?"

# Completion removes .delegated.
new_session t26 src/t26.go
"$DELEGATED_SCRIPT" t26 >/dev/null
echo "t26" > "$WIKI_DIR/pages/t26.md"
echo "pages/t26.md" > "$STATE_DIR/t26.wikitouched"
git -C "$WIKI_DIR" add pages/t26.md
git -C "$WIKI_DIR" -c user.email=subagent@example.com commit -q -m "t26 wiki"
touch -t "$(ago 5)" "$STATE_DIR/t26.touched"   # wiki work is newer than the last source edit
run_hook_json t26 ""
check "26a: wiki committed -> done" 0 "$RC"
check "26b: completion removed .delegated" 1 "$([ -f "$STATE_DIR/t26.delegated" ] && echo 0 || echo 1)"
if [ -f "$STATE_DIR/t26.synced" ]; then echo "PASS: 26c: .synced recorded"; PASS=$((PASS+1)); else echo "FAIL: 26c: .synced missing"; FAIL=$((FAIL+1)); fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
