#!/usr/bin/env bash
# Tests for lib.sh helpers that have to straddle the BSD/GNU userland split.
#
# Currently: file_mtime(). The two stat dialects are emulated by stubs on
# PATH, so both branches are exercised on every platform — the 2026-09-14
# Windows bug (see file_mtime's comment in lib.sh) was invisible on macOS
# because only the BSD branch ever ran there.
#
# Run: bash tools/bakery-sync/tests/lib.test.sh
set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

export BAKERY_SYNC_HOME="$TMPROOT/home"
export BAKERY_SYNC_STATE_DIR="$TMPROOT/home/state"
export BAKERY_SYNC_WIKI_DIR="$TMPROOT/wiki"
mkdir -p "$BAKERY_SYNC_STATE_DIR" "$BAKERY_SYNC_WIKI_DIR"

TARGET="$TMPROOT/target.txt"
echo "x" > "$TARGET"
FAKE_EPOCH=1700000000

PASS=0
FAIL=0

check() {
    # check <label> <expected> <actual>
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $label"
        PASS=$((PASS+1))
    else
        echo "FAIL: $label — expected [$expected], got [$actual]"
        FAIL=$((FAIL+1))
    fi
}

# --- stat stubs -------------------------------------------------------------
# Each stub reproduces the behaviour observed from the real tool, including
# the part that made this bug: GNU `stat -f` does NOT reject the BSD "%m"
# format outright — it treats it as another FILE operand, fails on that one,
# and still writes a filesystem block for the real file to STDOUT.

mk_gnu_stub() {
    local d="$1"
    mkdir -p "$d"
    cat > "$d/stat" <<EOF
#!/usr/bin/env bash
# emulates GNU coreutils stat
if [ "\$1" = "-f" ]; then
    shift
    rc=0
    for arg in "\$@"; do
        if [ -e "\$arg" ]; then
            printf '  File: "%s"\n    ID: a0e4 Namelen: 255     Type: UNKNOWN\n' "\$arg"
        else
            echo "stat: cannot read file system information for '\$arg'" >&2
            rc=1
        fi
    done
    exit \$rc
fi
if [ "\$1" = "-c" ] && [ "\$2" = "%Y" ]; then
    [ -e "\$3" ] || { echo "stat: cannot stat '\$3'" >&2; exit 1; }
    echo $FAKE_EPOCH
    exit 0
fi
exit 1
EOF
    chmod 0755 "$d/stat"
}

mk_bsd_stub() {
    local d="$1"
    mkdir -p "$d"
    cat > "$d/stat" <<EOF
#!/usr/bin/env bash
# emulates BSD/macOS stat: no -c, and -f takes a format argument
if [ "\$1" = "-f" ] && [ "\$2" = "%m" ]; then
    [ -e "\$3" ] || { echo "stat: \$3: stat: No such file or directory" >&2; exit 1; }
    echo $FAKE_EPOCH
    exit 0
fi
echo "usage: stat [-FLnq] [-f format] [file ...]" >&2
exit 1
EOF
    chmod 0755 "$d/stat"
}

mk_gnu_stub "$TMPROOT/bin-gnu"
mk_bsd_stub "$TMPROOT/bin-bsd"

# file_mtime is run in a subshell with the stub first on PATH, so the two
# dialects can be tested in one process without leaking into each other.
mtime_under() {
    # mtime_under <stubdir> <file>
    ( PATH="$1:$PATH"; . "$HOOKS_DIR/lib.sh"; file_mtime "$2" )
}

echo "=== file_mtime: GNU stat ==="
out=$(mtime_under "$TMPROOT/bin-gnu" "$TARGET")
check "GNU: returns the bare epoch" "$FAKE_EPOCH" "$out"
check "GNU: missing file -> 0" "0" "$(mtime_under "$TMPROOT/bin-gnu" "$TMPROOT/nope.txt")"

echo "=== file_mtime: BSD stat ==="
out=$(mtime_under "$TMPROOT/bin-bsd" "$TARGET")
check "BSD: returns the bare epoch" "$FAKE_EPOCH" "$out"
check "BSD: missing file -> 0" "0" "$(mtime_under "$TMPROOT/bin-bsd" "$TMPROOT/nope.txt")"

# The regression itself: callers feed the result straight into $(( )) under
# `set -u`. Anything but a bare integer aborts the hook with exit 1 (on
# Windows it was: "File: unbound variable"), which silently disables the
# active-work window and the ask-once throttle.
echo "=== file_mtime: result is usable in arithmetic under set -u ==="
for dialect in gnu bsd; do
    if ( set -u
         PATH="$TMPROOT/bin-$dialect:$PATH"
         . "$HOOKS_DIR/lib.sh"
         now=1700000600
         age=$(( now - $(file_mtime "$TARGET") ))
         [ "$age" = "600" ] ) 2>/dev/null
    then
        echo "PASS: $dialect: \$(( now - file_mtime )) evaluates to the real age"
        PASS=$((PASS+1))
    else
        echo "FAIL: $dialect: arithmetic on file_mtime output failed"
        FAIL=$((FAIL+1))
    fi
done

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
