#!/usr/bin/env bash
# Isolation tests: bakery-sync must coexist with Kytary's wiki-sync install on
# the same machine without touching, duplicating or removing any of it, and
# without sharing a switch/marker with it. Everything runs under a temp HOME
# pre-seeded with a fake Kytary install — never touches the real ~/.claude,
# ~/.codex, ~/.cursor, ~/.wiki-sync or ~/.bakery-sync.
#
# Run: bash tools/bakery-sync/tests/isolation.test.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$HOOKS_SRC/../.." && pwd)"
INSTALL_SH="$HOOKS_SRC/install.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required for isolation.test.sh"
    echo "=== Results: 0 passed, 1 failed ==="
    exit 1
fi

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT
H="$(cd "$TMPROOT" && pwd -P)/home"
mkdir -p "$H"
# Hard guard: every step below must run against the temp HOME.
case "$H" in
    "$HOME"/*|"") echo "FAIL: temp HOME is not isolated: $H"; exit 1 ;;
esac

PASS=0
FAIL=0

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"; PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected [$expected], got [$actual]"; FAIL=$((FAIL+1))
    fi
}

# --- seed Kytary's install in the temp HOME --------------------------------
K_SS_CLAUDE='~/.wiki-sync/hooks/wiki-sync-session-start.sh --agent claude'
K_PT_CLAUDE='~/.wiki-sync/hooks/wiki-sync-touched.sh --agent claude'
K_ST_CLAUDE='~/.wiki-sync/hooks/wiki-sync-stop.sh --agent claude'
K_SS_CODEX="$H/.wiki-sync/hooks/wiki-sync-session-start.sh --agent codex"
K_PT_CODEX="$H/.wiki-sync/hooks/wiki-sync-touched.sh --agent codex"
K_ST_CODEX="$H/.wiki-sync/hooks/wiki-sync-stop.sh --agent codex"
K_SS_CURSOR="$H/.wiki-sync/hooks/wiki-sync-session-start.sh --agent cursor"
K_PT_CURSOR="$H/.wiki-sync/hooks/wiki-sync-touched.sh --agent cursor"
K_ST_CURSOR="$H/.wiki-sync/hooks/wiki-sync-stop.sh --agent cursor"

mkdir -p "$H/.wiki-sync/hooks" "$H/.claude/hooks" "$H/.claude/state/wiki-sync" "$H/.codex" "$H/.cursor"
echo "WIKI_SYNC_WIKI_DIR=/kytary/clone" > "$H/.wiki-sync/config"
echo "# kytary lib" > "$H/.wiki-sync/hooks/lib.sh"
echo "# kytary legacy hook" > "$H/.claude/hooks/wiki-sync-legacy.sh"
echo "kytary-state" > "$H/.claude/state/wiki-sync/x"

cat > "$H/.claude/settings.json" <<SEED
{"hooks":{
 "Notification":[{"hooks":[{"type":"command","command":"echo unrelated-hook"}]}],
 "SessionStart":[{"hooks":[{"type":"command","command":"$K_SS_CLAUDE","timeout":5}]}],
 "PostToolUse":[{"matcher":"Write|Edit|NotebookEdit","hooks":[{"type":"command","command":"$K_PT_CLAUDE","timeout":5}]}],
 "Stop":[{"hooks":[{"type":"command","command":"$K_ST_CLAUDE","timeout":15,"asyncRewake":true,"rewakeSummary":"Wiki sync reminder"}]}]
}}
SEED
cat > "$H/.codex/hooks.json" <<SEED
{"hooks":{
 "Notification":[{"hooks":[{"type":"command","command":"echo unrelated-hook"}]}],
 "SessionStart":[{"hooks":[{"type":"command","command":"$K_SS_CODEX","timeout":5}]}],
 "PostToolUse":[{"matcher":"apply_patch|Edit|Write","hooks":[{"type":"command","command":"$K_PT_CODEX","timeout":5}]}],
 "Stop":[{"hooks":[{"type":"command","command":"$K_ST_CODEX","timeout":15}]}]
}}
SEED
cat > "$H/.cursor/hooks.json" <<SEED
{"version":1,"hooks":{
 "sessionStart":[{"command":"$K_SS_CURSOR"}],
 "afterFileEdit":[{"command":"$K_PT_CURSOR"}],
 "stop":[{"command":"$K_ST_CURSOR"},{"command":"echo unrelated-hook"}]
}}
SEED

sum_kytary_files() {
    (cd "$H" && cksum .wiki-sync/config .wiki-sync/hooks/lib.sh .claude/hooks/wiki-sync-legacy.sh .claude/state/wiki-sync/x 2>&1)
}
KYTARY_SUM_BEFORE="$(sum_kytary_files)"

# all hook commands of one agent config, one per line, sorted
cmds_claude_codex() { jq -r '[.hooks[][]?.hooks[]?.command] | .[]' "$1" | sort; }
cmds_cursor()       { jq -r '[.hooks[][]?.command] | .[]' "$1" | sort; }
all_cmds() {
    cmds_claude_codex "$H/.claude/settings.json"
    cmds_claude_codex "$H/.codex/hooks.json"
    cmds_cursor "$H/.cursor/hooks.json"
}
count_matching() { grep -c "$1" || true; }

run_install() {
    HOME="$H" BAKERY_SYNC_HOME="$H/.bakery-sync" bash "$INSTALL_SH" "$@" 2>&1
}

# =============================================================================
echo "=== a: install next to Kytary's registrations ==="
out=$(run_install); rc=$?
check_eq "install exits 0" "0" "$rc"

for c in "$K_SS_CLAUDE" "$K_PT_CLAUDE" "$K_ST_CLAUDE"; do
    check_eq "claude: kytary registration kept: ${c%% --*}" "1" "$(cmds_claude_codex "$H/.claude/settings.json" | grep -cxF "$c")"
done
for c in "$K_SS_CODEX" "$K_PT_CODEX" "$K_ST_CODEX"; do
    check_eq "codex: kytary registration kept: ${c##*/}" "1" "$(cmds_claude_codex "$H/.codex/hooks.json" | grep -cxF "$c")"
done
for c in "$K_SS_CURSOR" "$K_PT_CURSOR" "$K_ST_CURSOR"; do
    check_eq "cursor: kytary registration kept: ${c##*/}" "1" "$(cmds_cursor "$H/.cursor/hooks.json" | grep -cxF "$c")"
done
check_eq "claude: unrelated hook kept" "1" "$(cmds_claude_codex "$H/.claude/settings.json" | grep -cxF 'echo unrelated-hook')"
check_eq "codex: unrelated hook kept" "1" "$(cmds_claude_codex "$H/.codex/hooks.json" | grep -cxF 'echo unrelated-hook')"
check_eq "cursor: unrelated hook kept" "1" "$(cmds_cursor "$H/.cursor/hooks.json" | grep -cxF 'echo unrelated-hook')"

check_eq "claude: 3 bakery registrations added" "3" "$(cmds_claude_codex "$H/.claude/settings.json" | count_matching 'bakery-sync-')"
check_eq "codex: 3 bakery registrations added" "3" "$(cmds_claude_codex "$H/.codex/hooks.json" | count_matching 'bakery-sync-')"
check_eq "cursor: 3 bakery registrations added" "3" "$(cmds_cursor "$H/.cursor/hooks.json" | count_matching 'bakery-sync-')"

check_eq "kytary files byte-identical and in place after install" "$KYTARY_SUM_BEFORE" "$(sum_kytary_files)"
check_eq "bakery scripts live under ~/.bakery-sync/hooks" "1" "$([ -x "$H/.bakery-sync/hooks/bakery-sync-stop.sh" ] && echo 1 || echo 0)"
check_eq "install added nothing under ~/.wiki-sync (only the 2 seeded files)" "2" "$(find "$H/.wiki-sync" -type f | wc -l | tr -d ' ')"

# =============================================================================
echo "=== b: second install adds no duplicates ==="
BEFORE_ALL="$(all_cmds)"
run_install >/dev/null 2>&1
check_eq "re-install leaves the command set unchanged (no duplicates)" "$BEFORE_ALL" "$(all_cmds)"
check_eq "claude: still exactly 3 bakery registrations" "3" "$(cmds_claude_codex "$H/.claude/settings.json" | count_matching 'bakery-sync-')"
check_eq "kytary files still byte-identical after re-install" "$KYTARY_SUM_BEFORE" "$(sum_kytary_files)"

# =============================================================================
echo "=== d: no bakery command can be matched by Kytary's uninstall regex ==="
BAKERY_CMDS="$(all_cmds | grep 'bakery-sync-' || true)"
check_eq "9 bakery commands registered in total" "9" "$(printf '%s\n' "$BAKERY_CMDS" | grep -c .)"
check_eq "no bakery command matches wiki-sync-" "0" "$(printf '%s\n' "$BAKERY_CMDS" | grep -c 'wiki-sync-' || true)"
check_eq "no bakery command points into ~/.wiki-sync" "0" "$(printf '%s\n' "$BAKERY_CMDS" | grep -c '\.wiki-sync' || true)"

# =============================================================================
echo "=== c: --uninstall removes only bakery's entries ==="
out=$(run_install --uninstall); rc=$?
check_eq "uninstall exits 0" "0" "$rc"
check_eq "no bakery registration left" "0" "$(all_cmds | count_matching 'bakery-sync-')"
check_eq "all 9 kytary registrations survive" "9" "$(all_cmds | count_matching 'wiki-sync-')"
check_eq "all 3 unrelated hooks survive" "3" "$(all_cmds | grep -cxF 'echo unrelated-hook')"
check_eq "kytary files byte-identical after uninstall" "$KYTARY_SUM_BEFORE" "$(sum_kytary_files)"
for f in "$H/.claude/settings.json" "$H/.codex/hooks.json" "$H/.cursor/hooks.json"; do
    if jq -e . "$f" >/dev/null 2>&1; then r=0; else r=1; fi
    check_eq "valid JSON after uninstall: $(basename "$f")" "0" "$r"
done

# =============================================================================
echo "=== e: opt-in writes the bakery marker, never Kytary's ==="
OPTIN="$HOOKS_SRC/bakery-sync-optin.sh"
optin() { HOME="$H" BAKERY_SYNC_HOME="$TMPROOT/bhome" BAKERY_SYNC_STATE_DIR="$TMPROOT/bstate" bash "$OPTIN" "$@" 2>&1; }
R="$TMPROOT/repo"
git init -q "$R"
optin on --repo "$R" >/dev/null
check_eq "optin on creates .git/info/bakery-sync" "1" "$([ -f "$R/.git/info/bakery-sync" ] && echo 1 || echo 0)"
check_eq "optin on does NOT create .git/info/wiki-sync" "0" "$([ -e "$R/.git/info/wiki-sync" ] && echo 1 || echo 0)"
# a Kytary marker set to "on" must not turn bakery on
R2="$TMPROOT/repo2"; git init -q "$R2"; mkdir -p "$R2/.git/info"; echo on > "$R2/.git/info/wiki-sync"
check_eq "kytary marker 'on' reads as off for bakery" "off none" "$(optin status --repo "$R2")"

# =============================================================================
echo "=== f: instruction-file switch strings ==="
R3="$TMPROOT/repo3"; git init -q "$R3"
echo "## LLM Wiki sync (blocking rule)" > "$R3/CLAUDE.md"
check_eq "CLAUDE.md with only 'LLM Wiki sync' reads as off" "off none" "$(optin status --repo "$R3")"
R4="$TMPROOT/repo4"; git init -q "$R4"
echo "## Bakery Wiki sync (blocking rule)" > "$R4/CLAUDE.md"
check_eq "CLAUDE.md with 'Bakery Wiki sync' reads as on" "on instructions" "$(optin status --repo "$R4")"

# =============================================================================
echo "=== g: org regex ==="
org_match() {
    # org_match <remote-url> -> "yes"/"no" via lib.sh is_org_repo
    local r="$TMPROOT/orgrepo"
    rm -rf "$r"; git init -q "$r"; git -C "$r" remote add origin "$1"
    ( export HOME="$H" BAKERY_SYNC_HOME="$TMPROOT/bhome"; unset BAKERY_SYNC_ORG_RE BAKERY_SYNC_WIKI_DIR
      . "$HOOKS_SRC/lib.sh"; if is_org_repo "$r"; then echo yes; else echo no; fi )
}
check_eq "git@github-johnpitralon:johnpitralon/x.git is an org repo" "yes" "$(org_match 'git@github-johnpitralon:johnpitralon/x.git')"
check_eq "https://github.com/johnpitralon/x.git is an org repo" "yes" "$(org_match 'https://github.com/johnpitralon/x.git')"
check_eq "git@github.com:ITKytaryDevTeam/x.git is NOT an org repo" "no" "$(org_match 'git@github.com:ITKytaryDevTeam/x.git')"

# =============================================================================
echo "=== h: this repo's own instruction files ==="
check_eq "CLAUDE.md does not contain 'LLM Wiki sync'" "0" "$(grep -c 'LLM Wiki sync' "$REPO_ROOT/CLAUDE.md" || true)"
check_eq "AGENTS.md does not contain 'LLM Wiki sync'" "0" "$(grep -c 'LLM Wiki sync' "$REPO_ROOT/AGENTS.md" || true)"
check_eq "CLAUDE.md contains 'Bakery Wiki sync'" "1" "$(if grep -q 'Bakery Wiki sync' "$REPO_ROOT/CLAUDE.md"; then echo 1; else echo 0; fi)"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
