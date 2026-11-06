#!/usr/bin/env bash
# Tests for bakery-sync-session-start.sh's snapshot of an enabled repo: a
# fresh session gets "repo\thead\tts", and a re-fire under the SAME session
# id (resume / compact / clear, or Cursor's always-"startup") keeps the
# original start_ts (2026-10-02 fix — a /compact used to move it forward and
# the Stop hook then re-reported an already synced wiki). Also the
# stale-install hint (2026-10-02): installed hooks that differ from the wiki
# clone's tools/bakery-sync/ are reported once per drift state. The ask-once
# flow is covered by bakery-sync-optin.test.sh. Uses a temp STATE_DIR and
# disposable git repos — never touches real ~/.bakery-sync state or any real
# repo.
#
# Run: bash tools/bakery-sync/tests/bakery-sync-session-start.test.sh
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_START_HOOK="$HOOKS_DIR/bakery-sync-session-start.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mkdir -p "$TMPROOT/state"
STATE_DIR="$(cd "$TMPROOT/state" && pwd -P)"
export BAKERY_SYNC_STATE_DIR="$STATE_DIR"
# No config, no wiki dir unless a test sets one: keeps the real
# ~/.bakery-sync/config (and the real wiki clone) out of these tests.
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

mk_enabled_repo() {
    # mk_enabled_repo <name> -> prints resolved absolute path of a fresh git
    # repo whose CLAUDE.md carries the "Bakery Wiki sync" switch
    local name="$1"
    local dir="$TMPROOT/$name"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name Test
    printf '## Bakery Wiki sync (blocking rule)\ntest fixture\n' > "$dir/CLAUDE.md"
    git -C "$dir" add CLAUDE.md
    git -C "$dir" commit -q -m init
    (cd "$dir" && pwd -P)
}

fire() {
    # fire <session_id> <cwd> <source|-> [--agent X] — "-" omits the field
    local sid="$1" cwd="$2" src="$3"; shift 3
    if [ "$src" = "-" ]; then
        printf '{"session_id":"%s","conversation_id":"%s","cwd":"%s"}' "$sid" "$sid" "$cwd" \
            | "$SESSION_START_HOOK" "$@" >/dev/null 2>&1
    else
        printf '{"session_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$cwd" "$src" \
            | "$SESSION_START_HOOK" "$@" >/dev/null 2>&1
    fi
}

field() {
    # field <session_id> <1|2|3> -> repo | head | ts from the snapshot line
    cut -f"$2" "$STATE_DIR/$1" 2>/dev/null
}

R1=$(mk_enabled_repo r1)
R2=$(mk_enabled_repo r2)
HEAD1=$(git -C "$R1" rev-parse HEAD)
OLD_TS=$(( $(date +%s) - 3600 ))

echo "=== fresh session: snapshot taken ==="

fire s1 "$R1" startup
check_eq "1a: startup writes repo" "$R1" "$(field s1 1)"
check_eq "1b: startup writes HEAD" "$HEAD1" "$(field s1 2)"
ts1=$(field s1 3)
case "$ts1" in
    '' | *[!0-9]*) check_eq "1c: startup writes a numeric ts" "number" "$ts1" ;;
    *)             check_eq "1c: startup writes a numeric ts" "number" "number" ;;
esac

echo "=== same session re-fires: original snapshot kept ==="

for src in compact resume clear startup; do
    printf '%s\t%s\t%s\n' "$R1" "$HEAD1" "$OLD_TS" > "$STATE_DIR/s-$src"
    git -C "$R1" commit -q --allow-empty -m "work before $src"
    fire "s-$src" "$R1" "$src"
    check_eq "2 ($src): start_ts kept" "$OLD_TS" "$(field "s-$src" 3)"
    check_eq "2 ($src): start_head kept" "$HEAD1" "$(field "s-$src" 2)"
done

# Cursor sends no "source" field (reads as startup) and calls the id
# conversation_id — a re-fired sessionStart must not reset it either.
printf '%s\t%s\t%s\n' "$R1" "$HEAD1" "$OLD_TS" > "$STATE_DIR/s-cursor"
fire s-cursor "$R1" - --agent cursor
check_eq "3: cursor re-fire (no source field) keeps start_ts" "$OLD_TS" "$(field s-cursor 3)"

echo "=== same session, different repo (e.g. moved into a worktree) ==="

# cms-web-react-nodejs 2. 10.: started in the main checkout, compacted with
# cwd in .worktrees/banners. Track the repo the session is in now, but the
# session start stays where it was.
printf '%s\t%s\t%s\n' "$R1" "$HEAD1" "$OLD_TS" > "$STATE_DIR/s-move"
fire s-move "$R2" compact
check_eq "4a: repo follows the session" "$R2" "$(field s-move 1)"
check_eq "4b: HEAD of the new repo" "$(git -C "$R2" rev-parse HEAD)" "$(field s-move 2)"
check_eq "4c: start_ts kept across the move" "$OLD_TS" "$(field s-move 3)"

echo "=== unreadable snapshot is replaced ==="

printf 'garbage\n' > "$STATE_DIR/s-bad"
fire s-bad "$R1" compact
check_eq "5a: repo rewritten" "$R1" "$(field s-bad 1)"
ts_bad=$(field s-bad 3)
case "$ts_bad" in
    '' | *[!0-9]*) check_eq "5b: fresh numeric ts" "number" "$ts_bad" ;;
    *)             check_eq "5b: fresh numeric ts" "number" "number" ;;
esac

echo "=== footprint files are never touched ==="

printf '%s\t%s\t%s\n' "$R1" "$HEAD1" "$OLD_TS" > "$STATE_DIR/s-fp"
echo "src/a.go" > "$STATE_DIR/s-fp.touched"
echo "deadbeef" > "$STATE_DIR/s-fp.synced"
fire s-fp "$R1" compact
check_eq "6a: .touched intact" "src/a.go" "$(cat "$STATE_DIR/s-fp.touched")"
check_eq "6b: .synced intact" "deadbeef" "$(cat "$STATE_DIR/s-fp.synced")"

echo "=== stale-install hint: installed hooks vs the wiki clone ==="

# Mirror install.sh: an "installed" dir with every shipped script (all *.sh
# but install.sh), and a fake wiki clone carrying the full tools/bakery-sync/.
INST="$TMPROOT/installed"
FAKE_WIKI="$TMPROOT/wiki"
mkdir -p "$INST" "$FAKE_WIKI/tools/bakery-sync"
cp "$HOOKS_DIR"/*.sh "$FAKE_WIKI/tools/bakery-sync/"
cp "$HOOKS_DIR"/*.sh "$INST/"
rm -f "$INST/install.sh"
SRC="$FAKE_WIKI/tools/bakery-sync"
THROTTLE="$STATE_DIR/stale-install"

hint() {
    # hint <session_id> <cwd> <source> [--agent X] -> stdout of the INSTALLED hook
    local sid="$1" cwd="$2" src="$3"; shift 3
    printf '{"session_id":"%s","conversation_id":"%s","cwd":"%s","source":"%s"}' "$sid" "$sid" "$cwd" "$src" \
        | BAKERY_SYNC_WIKI_DIR="$FAKE_WIKI" "$INST/bakery-sync-session-start.sh" "$@" 2>/dev/null
}

has() {
    # has <label> <haystack> <needle>
    if printf '%s' "$2" | grep -qF -- "$3"; then
        check_eq "$1" "found" "found"
    else
        check_eq "$1" "found: $3" "$2"
    fi
}

check_eq "7a: installed == clone -> silent" "" "$(hint h1 "$R1" startup)"

echo "# fixed upstream" >> "$SRC/bakery-sync-stop.sh"
out=$(hint h2 "$R1" startup)
has "7b: drift -> hint names the stale script" "$out" "bakery-sync-stop.sh"
has "7b: drift -> hint gives the installer to run" "$out" "$SRC/install.sh"
check_eq "7b: snapshot still written" "$R1" "$(field h2 1)"

check_eq "7c: same drift again -> throttled" "" "$(hint h3 "$R1" startup)"

echo "# fixed again" >> "$SRC/lib.sh"
out=$(hint h4 "$R1" startup)
has "7d: different drift -> hint again at once (lib.sh)" "$out" "lib.sh"
has "7d: ... still listing bakery-sync-stop.sh" "$out" "bakery-sync-stop.sh"

touch -t "$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || date -d '-25 hours' +%Y%m%d%H%M.%S)" "$THROTTLE"
has "7e: same drift after 24h -> hint again" "$(hint h5 "$R1" startup)" "lib.sh"

rm -f "$THROTTLE"
check_eq "7f: resume -> silent (startup only)" "" "$(hint h6 "$R1" resume)"
check_eq "7f: compact -> silent (startup only)" "" "$(hint h7 "$R1" compact)"

PLAIN=$(cd "$(mktemp -d "$TMPROOT/plain.XXXXXX")" && git init -q && pwd -P)
check_eq "7g: repo without bakery-sync -> silent" "" "$(hint h8 "$PLAIN" startup)"

out=$(hint h9 "$R1" startup --agent cursor)
ctx=$(printf '%s' "$out" | jq -r '.additional_context // empty' 2>/dev/null)
has "7h: cursor gets the hint as additional_context" "$ctx" "install.sh"

rm -f "$THROTTLE"
printf '#!/usr/bin/env bash\n' > "$SRC/bakery-sync-new.sh"
has "7i: newly shipped script not installed yet -> listed" "$(hint h10 "$R1" startup)" "bakery-sync-new.sh"

rm -f "$THROTTLE"
check_eq "7j: wiki dir without tools/bakery-sync -> silent" "" \
    "$(printf '{"session_id":"h11","cwd":"%s","source":"startup"}' "$R1" \
        | BAKERY_SYNC_WIKI_DIR="$TMPROOT" "$INST/bakery-sync-session-start.sh" 2>/dev/null)"

echo "=== self-update of the installed hooks (2026-10-19) ==="

mk_su_env() {
    # mk_su_env <name> -> sets SU_HOME / SU_CLONE / SU_HOOKS: a bare origin,
    # a clone whose tools/bakery-sync is pushed to origin/dev, and a hooks dir
    # under $SU_HOME/hooks holding the PREVIOUS version of bakery-sync-stop.sh
    # (so exactly that script is stale against the clone).
    local n="$1" root
    root="$TMPROOT/su-$n"
    mkdir -p "$root/home/hooks" "$root/clone/tools/bakery-sync" "$root/clone/wiki"
    root="$(cd "$root" && pwd -P)"
    git init -q --bare "$root/origin.git"
    git -C "$root/clone" init -q
    git -C "$root/clone" config user.email test@example.com
    git -C "$root/clone" config user.name Test
    git -C "$root/clone" checkout -q -b dev
    cp "$HOOKS_DIR"/*.sh "$root/clone/tools/bakery-sync/"
    echo "# index" > "$root/clone/wiki/index.md"
    git -C "$root/clone" add tools wiki
    git -C "$root/clone" commit -q -m base
    git -C "$root/clone" remote add origin "$root/origin.git"
    git -C "$root/clone" push -q origin dev 2>/dev/null
    cp "$HOOKS_DIR"/*.sh "$root/home/hooks/"
    rm -f "$root/home/hooks/install.sh"
    # upstream moves on: a fix to the Stop hook lands on origin/dev
    echo "# upstream fix" >> "$root/clone/tools/bakery-sync/bakery-sync-stop.sh"
    git -C "$root/clone" commit -q -am "fix stop"
    git -C "$root/clone" push -q origin dev 2>/dev/null
    SU_HOME="$root/home"; SU_CLONE="$root/clone"; SU_HOOKS="$root/home/hooks"
}

su_fire() {
    # su_fire <session_id> [hooks_dir] [--agent X] -> stdout of the hook
    local sid="$1" dir="${2:-$SU_HOOKS}"; shift; [ $# -gt 0 ] && shift
    rm -f "$THROTTLE"
    printf '{"session_id":"%s","conversation_id":"%s","cwd":"%s","source":"startup"}' "$sid" "$sid" "$R1" \
        | BAKERY_SYNC_HOME="$SU_HOME" BAKERY_SYNC_WIKI_DIR="$SU_CLONE" "$dir/bakery-sync-session-start.sh" "$@" 2>/dev/null
}

same_as_clone() { cmp -s "$SU_CLONE/tools/bakery-sync/$1" "$SU_HOOKS/$1" && echo same || echo differs; }

mk_su_env a
out=$(su_fire u1)
has "8a: clean clone == origin/dev -> note names the updated script" "$out" "automaticky aktualizovány"
has "8a: ... and the file" "$out" "bakery-sync-stop.sh"
check_eq "8a: installed script now equals the clone's" "same" "$(same_as_clone bakery-sync-stop.sh)"
check_eq "8a: installed script executable" "yes" "$([ -x "$SU_HOOKS/bakery-sync-stop.sh" ] && echo yes || echo no)"
check_eq "8a: no temp files left in hooks dir" "0" "$(ls -A "$SU_HOOKS" | grep -c '\.upd\.')"
check_eq "8a: no stale-install hint after the update" "" "$(printf '%s' "$out" | grep -F 'install.sh')"
check_eq "8b: second fire -> silent (nothing stale)" "" "$(su_fire u2)"

# a script the clone ships but the hooks dir lacks gets installed too
mk_su_env a2
rm -f "$SU_HOOKS/bakery-sync-delegated.sh"
has "8c: missing script is installed" "$(su_fire u3)" "bakery-sync-delegated.sh"
check_eq "8c: ... and present afterwards" "same" "$(same_as_clone bakery-sync-delegated.sh)"

# Cursor: one JSON document carrying the note
mk_su_env a3
out=$(su_fire u4 "$SU_HOOKS" --agent cursor)
ctx=$(printf '%s' "$out" | jq -r '.additional_context // empty' 2>/dev/null)
has "8d: cursor gets the note as additional_context" "$ctx" "automaticky aktualizovány"

# refuse: tracked file dirty in the clone
mk_su_env b
echo "# local WIP" >> "$SU_CLONE/tools/bakery-sync/lib.sh"
out=$(su_fire v1)
check_eq "8e: dirty tools/bakery-sync -> hooks untouched" "differs" "$(same_as_clone bakery-sync-stop.sh)"
has "8e: ... falls back to the install hint" "$out" "install.sh"

# refuse: untracked file there
mk_su_env c
echo "#!/usr/bin/env bash" > "$SU_CLONE/tools/bakery-sync/bakery-sync-wip.sh"
out=$(su_fire w1)
check_eq "8f: untracked file in tools/bakery-sync -> hooks untouched" "differs" "$(same_as_clone bakery-sync-stop.sh)"
check_eq "8f: ... WIP script not installed" "no" "$([ -f "$SU_HOOKS/bakery-sync-wip.sh" ] && echo yes || echo no)"
has "8f: ... falls back to the install hint" "$out" "install.sh"

# refuse: unpushed commit in tools/bakery-sync
mk_su_env d
echo "# unpushed" >> "$SU_CLONE/tools/bakery-sync/bakery-sync-stop.sh"
git -C "$SU_CLONE" commit -q -am "local only"
out=$(su_fire x1)
check_eq "8g: unpushed commit -> hooks untouched" "differs" "$(cmp -s "$SU_CLONE/tools/bakery-sync/bakery-sync-stop.sh" "$SU_HOOKS/bakery-sync-stop.sh" && echo same || echo differs)"
has "8g: ... falls back to the install hint" "$out" "install.sh"

# refuse: no origin/dev at all (never pushed)
mk_su_env e
git -C "$SU_CLONE" update-ref -d refs/remotes/origin/dev
su_fire y1 >/dev/null
check_eq "8h: no origin/dev ref -> hooks untouched" "differs" "$(same_as_clone bakery-sync-stop.sh)"

# refuse: scripts not running from $BAKERY_SYNC_HOME/hooks (repo checkout, tests dir)
mk_su_env f
OTHER="$TMPROOT/su-f/other"
mkdir -p "$OTHER"
cp "$SU_HOOKS"/*.sh "$OTHER/"
out=$(su_fire z1 "$OTHER")
check_eq "8i: LIB_DIR != BAKERY_SYNC_HOME/hooks -> scripts untouched" "differs" \
    "$(cmp -s "$SU_CLONE/tools/bakery-sync/bakery-sync-stop.sh" "$OTHER/bakery-sync-stop.sh" && echo same || echo differs)"
check_eq "8i: ... the real hooks dir untouched too" "differs" "$(same_as_clone bakery-sync-stop.sh)"
has "8i: ... falls back to the install hint" "$out" "install.sh"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
