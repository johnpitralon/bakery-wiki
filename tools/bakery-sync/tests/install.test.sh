#!/usr/bin/env bash
# Tests for install.sh: fresh install with auto-detected agents (claude,
# codex, cursor), foreign-entry preservation, idempotent re-run, --uninstall, and --dry-run writing
# nothing; plus (2026-10-02) the stale-install hint end to end and the
# refusal to install from a linked git worktree. Everything runs under a
# fake HOME in a temp dir — never touches the real ~/.claude, ~/.codex,
# ~/.cursor of this machine.
#
# Run: bash tools/bakery-sync/tests/install.test.sh
set -u
unset BAKERY_SYNC_WIKI_DIR BAKERY_SYNC_STATE_DIR

SCRIPT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# install.sh refuses to run from a linked git worktree, and this suite may
# itself be run from one (agent worktrees) — so install from a throwaway
# main clone holding a copy of the shipped scripts. That also pins the
# expected BAKERY_SYNC_WIKI_DIR regardless of where the repo is checked out.
CLONE_TMP=$(mktemp -d)
CLONE_TMP="$(cd "$CLONE_TMP" && pwd -P)"
CLONE="$CLONE_TMP/clone"
mkdir -p "$CLONE/tools/bakery-sync" "$CLONE/wiki"
cp "$SCRIPT_SRC_DIR"/*.sh "$CLONE/tools/bakery-sync/"
echo "# index" > "$CLONE/wiki/index.md"
git -C "$CLONE" init -q
git -C "$CLONE" config user.email test@example.com
git -C "$CLONE" config user.name Test
git -C "$CLONE" add tools wiki
git -C "$CLONE" commit -q -m "fake wiki clone"
INSTALL_SH="$CLONE/tools/bakery-sync/install.sh"

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
    if [ "$cond" = "true" ] || [ "$cond" = "0" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label (got [$cond])"
        FAIL=$((FAIL+1))
    fi
}

check_contains() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected to find: $needle"
        FAIL=$((FAIL+1))
    fi
}

check_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        echo "FAIL: $label — should NOT contain: $needle"
        FAIL=$((FAIL+1))
    else
        echo "PASS: $label"
        PASS=$((PASS+1))
    fi
}

# =============================================================================
echo "=== fresh install: auto-detected agents, foreign entries ==="

TMPROOT=$(mktemp -d)
HOME_DIR="$(cd "$TMPROOT" && pwd -P)/home"
mkdir -p "$HOME_DIR/.claude/hooks" "$HOME_DIR/.codex" "$HOME_DIR/.cursor"

# Foreign hook only (Kytary-style legacy migration was not ported).
cat > "$HOME_DIR/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Notification": [
      {"hooks": [{"type": "command", "command": "echo foreign-notification"}]}
    ]
  }
}
EOF

cat > "$HOME_DIR/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "echo foreign-codex-ss"}]}
    ]
  }
}
EOF

cat > "$HOME_DIR/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "stop": [
      {"command": "echo foreign-cursor-stop"}
    ]
  }
}
EOF

BAKERY_SYNC_HOME="$HOME_DIR/.bakery-sync"

install_out=$(HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$INSTALL_SH" 2>&1)
install_rc=$?
check_true "install exits 0" "$install_rc"
check_contains "install auto-detects all three agents" "$install_out" "selected agents: claude codex cursor"

for f in lib.sh bakery-sync-session-start.sh bakery-sync-touched.sh bakery-sync-stop.sh bakery-sync-ack.sh bakery-sync-delegated.sh bakery-sync-optin.sh; do
    if [ -f "$BAKERY_SYNC_HOME/hooks/$f" ]; then
        echo "PASS: hooks/$f installed"
        PASS=$((PASS+1))
    else
        echo "FAIL: hooks/$f missing"
        FAIL=$((FAIL+1))
    fi
done

# the config value must equal the clone root (two levels above tools/bakery-sync)
check_eq "config BAKERY_SYNC_WIKI_DIR points at this clone" \
    "BAKERY_SYNC_WIKI_DIR=$CLONE" "$(cat "$BAKERY_SYNC_HOME/config")"

claude_settings=$(cat "$HOME_DIR/.claude/settings.json")
echo "$claude_settings" | jq -e . >/dev/null 2>&1
check_true "claude settings.json still valid JSON" "$?"
check_contains "claude: foreign Notification hook preserved" "$claude_settings" "foreign-notification"
check_contains "claude: new registration present" "$claude_settings" "bakery-sync-stop.sh --agent claude"


codex_hooks=$(cat "$HOME_DIR/.codex/hooks.json")
echo "$codex_hooks" | jq -e . >/dev/null 2>&1
check_true "codex hooks.json still valid JSON" "$?"
check_contains "codex: foreign SessionStart hook preserved" "$codex_hooks" "foreign-codex-ss"
check_contains "codex: new registration present" "$codex_hooks" "bakery-sync-stop.sh --agent codex"

cursor_hooks=$(cat "$HOME_DIR/.cursor/hooks.json")
echo "$cursor_hooks" | jq -e . >/dev/null 2>&1
check_true "cursor hooks.json still valid JSON" "$?"
check_contains "cursor: foreign stop hook preserved" "$cursor_hooks" "foreign-cursor-stop"
check_contains "cursor: new registration present" "$cursor_hooks" "bakery-sync-stop.sh --agent cursor"
cursor_version=$(printf '%s' "$cursor_hooks" | jq -r '.version')
check_eq "cursor hooks.json has version 1" "1" "$cursor_version"

# =============================================================================
echo "=== re-run: idempotent, no duplicates ==="

reinstall_out=$(HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$INSTALL_SH" 2>&1)
check_contains "re-run: claude says nothing to do" "$reinstall_out" "nothing to do"
check_contains "re-run: codex says nothing to do" "$reinstall_out" "nothing to do"
check_contains "re-run: cursor says nothing to do" "$reinstall_out" "nothing to do"

claude_ss_count=$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | test("bakery-sync-session-start"))] | length' "$HOME_DIR/.claude/settings.json")
check_eq "re-run does not duplicate claude SessionStart registration" "1" "$claude_ss_count"

codex_ss_count=$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | test("bakery-sync-session-start"))] | length' "$HOME_DIR/.codex/hooks.json")
check_eq "re-run does not duplicate codex SessionStart registration" "1" "$codex_ss_count"

cursor_ss_count=$(jq '[.hooks.sessionStart[] | select(.command | test("bakery-sync-session-start"))] | length' "$HOME_DIR/.cursor/hooks.json")
check_eq "re-run does not duplicate cursor sessionStart registration" "1" "$cursor_ss_count"

# Idempotency must be byte- and mtime-exact: Codex pins a trust hash per
# hooks.json entry, so a pointless rewrite (reformatting, reordering) would
# put the hooks back to "new or changed" until the user reviews them again.
cfg_files="$HOME_DIR/.claude/settings.json $HOME_DIR/.codex/hooks.json $HOME_DIR/.cursor/hooks.json $BAKERY_SYNC_HOME/config"
before_sums=$(cd / && cksum $cfg_files)
before_listing=$(ls -A "$HOME_DIR/.claude" "$HOME_DIR/.codex" "$HOME_DIR/.cursor" "$BAKERY_SYNC_HOME" "$BAKERY_SYNC_HOME/hooks")
ref="$TMPROOT/idempotency-ref"
touch "$ref"
sleep 1
HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$INSTALL_SH" >/dev/null 2>&1
check_eq "re-run: agent configs + config byte-identical" "$before_sums" "$(cd / && cksum $cfg_files)"
check_eq "re-run: no backup/temp files created" "$before_listing" \
    "$(ls -A "$HOME_DIR/.claude" "$HOME_DIR/.codex" "$HOME_DIR/.cursor" "$BAKERY_SYNC_HOME" "$BAKERY_SYNC_HOME/hooks")"
rewritten=$(find $cfg_files "$BAKERY_SYNC_HOME/hooks" -type f -newer "$ref" 2>/dev/null)
check_eq "re-run: nothing rewritten (mtime unchanged)" "" "$rewritten"

# =============================================================================
echo "=== stale-install hint: silent after install, reported after a pull, gone after re-install ==="

# A repo with the bakery-sync switch, for the installed session-start to fire in.
ENABLED_REPO="$CLONE_TMP/enabled"
mkdir -p "$ENABLED_REPO"
git -C "$ENABLED_REPO" init -q
printf '## Bakery Wiki sync (blocking rule)\n' > "$ENABLED_REPO/CLAUDE.md"

start_installed() {
    # start_installed <session_id> -> context printed by the INSTALLED hook
    printf '{"session_id":"%s","cwd":"%s","source":"startup"}' "$1" "$ENABLED_REPO" \
        | HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$BAKERY_SYNC_HOME/hooks/bakery-sync-session-start.sh" 2>/dev/null
}

# Also guards LIB_AND_SCRIPTS: a script shipped in tools/bakery-sync/ but not
# installed would show up here as drift right after a fresh install.
check_eq "fresh install -> no stale-install hint" "" "$(start_installed d1)"

echo "# pulled fix" >> "$CLONE/tools/bakery-sync/bakery-sync-stop.sh"
check_contains "clone moved on -> hint names the stale script" "$(start_installed d2)" "bakery-sync-stop.sh"

HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$INSTALL_SH" >/dev/null 2>&1
rm -f "$BAKERY_SYNC_HOME/state/stale-install"
check_eq "re-install -> hint gone" "" "$(start_installed d3)"

# =============================================================================
echo "=== --uninstall: entries gone, foreign entries intact ==="

uninstall_out=$(HOME="$HOME_DIR" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME" "$INSTALL_SH" --uninstall 2>&1)
check_true "uninstall exits 0" "$?"

claude_after=$(cat "$HOME_DIR/.claude/settings.json")
check_contains "uninstall: foreign claude Notification hook still present" "$claude_after" "foreign-notification"
check_not_contains "uninstall: claude bakery-sync entries gone" "$claude_after" "bakery-sync-"

codex_after=$(cat "$HOME_DIR/.codex/hooks.json")
check_contains "uninstall: foreign codex SessionStart hook still present" "$codex_after" "foreign-codex-ss"
check_not_contains "uninstall: codex bakery-sync entries gone" "$codex_after" "bakery-sync-"

cursor_after=$(cat "$HOME_DIR/.cursor/hooks.json")
check_contains "uninstall: foreign cursor stop hook still present" "$cursor_after" "foreign-cursor-stop"
check_not_contains "uninstall: cursor bakery-sync entries gone" "$cursor_after" "bakery-sync-"

if ls "$BAKERY_SYNC_HOME/hooks/"*.sh >/dev/null 2>&1; then
    echo "FAIL: uninstall should have removed the installed scripts"
    FAIL=$((FAIL+1))
else
    echo "PASS: uninstall removed the installed scripts"
    PASS=$((PASS+1))
fi
if [ -f "$BAKERY_SYNC_HOME/config" ] && [ -d "$BAKERY_SYNC_HOME/state" ]; then
    echo "PASS: uninstall left config and state in place"
    PASS=$((PASS+1))
else
    echo "FAIL: uninstall should leave config and state in place"
    FAIL=$((FAIL+1))
fi

# =============================================================================
echo "=== --dry-run writes nothing ==="

TMPROOT2=$(mktemp -d)
HOME_DIR2="$(cd "$TMPROOT2" && pwd -P)/home"
mkdir -p "$HOME_DIR2/.claude"
BAKERY_SYNC_HOME2="$HOME_DIR2/.bakery-sync"

dry_out=$(HOME="$HOME_DIR2" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME2" "$INSTALL_SH" --dry-run 2>&1)
check_true "dry-run exits 0" "$?"
check_contains "dry-run output is marked [dry-run]" "$dry_out" "[dry-run]"

if [ -e "$BAKERY_SYNC_HOME2" ]; then
    echo "FAIL: --dry-run created $BAKERY_SYNC_HOME2"
    FAIL=$((FAIL+1))
else
    echo "PASS: --dry-run created nothing under BAKERY_SYNC_HOME"
    PASS=$((PASS+1))
fi
if [ -f "$HOME_DIR2/.claude/settings.json" ]; then
    echo "FAIL: --dry-run created a settings.json"
    FAIL=$((FAIL+1))
else
    echo "PASS: --dry-run did not create settings.json"
    PASS=$((PASS+1))
fi

# =============================================================================
echo "=== linked worktree: install refused, uninstall allowed, bare layout ok ==="

TMPROOT3=$(mktemp -d)
HOME_DIR3="$(cd "$TMPROOT3" && pwd -P)/home"
mkdir -p "$HOME_DIR3/.claude"
BAKERY_SYNC_HOME3="$HOME_DIR3/.bakery-sync"

git -C "$CLONE" worktree add -q --detach "$CLONE_TMP/wt" 2>/dev/null
wt_out=$(HOME="$HOME_DIR3" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME3" "$CLONE_TMP/wt/tools/bakery-sync/install.sh" 2>&1)
wt_rc=$?
check_eq "install from a linked worktree exits 1" "1" "$wt_rc"
check_contains "refusal points at the main clone's installer" "$wt_out" "$CLONE/tools/bakery-sync/install.sh"
if [ -e "$BAKERY_SYNC_HOME3" ]; then
    echo "FAIL: refused install still created $BAKERY_SYNC_HOME3"
    FAIL=$((FAIL+1))
else
    echo "PASS: refused install wrote nothing"
    PASS=$((PASS+1))
fi

HOME="$HOME_DIR3" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME3" "$CLONE_TMP/wt/tools/bakery-sync/install.sh" --uninstall >/dev/null 2>&1
check_true "uninstall from a linked worktree is allowed" "$?"

# Bare-repo layout: the main "worktree" has no files, a linked worktree is
# the long-lived checkout — install must go through and point at it.
git clone -q --bare "$CLONE" "$CLONE_TMP/bare.git"
git -C "$CLONE_TMP/bare.git" worktree add -q --detach "$CLONE_TMP/bare-wt" 2>/dev/null
HOME="$HOME_DIR3" BAKERY_SYNC_HOME="$BAKERY_SYNC_HOME3" "$CLONE_TMP/bare-wt/tools/bakery-sync/install.sh" >/dev/null 2>&1
check_true "install from a bare repo's worktree exits 0" "$?"
check_eq "bare layout: config points at that worktree" \
    "BAKERY_SYNC_WIKI_DIR=$CLONE_TMP/bare-wt" "$(cat "$BAKERY_SYNC_HOME3/config" 2>/dev/null)"

rm -rf "$TMPROOT" "$TMPROOT2" "$TMPROOT3" "$CLONE_TMP"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
