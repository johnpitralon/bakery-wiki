#!/usr/bin/env bash
# SessionStart hook: snapshot repo state when an agent session starts, so
# bakery-sync-stop.sh can later detect whether source changes happened during
# the session. Agent-neutral (Claude Code / Codex CLI / Cursor — see lib.sh).
# On a fresh ("startup") session in an enabled repo it also asks the agent
# to tell the user when the installed hooks lag behind the wiki clone (see
# warn_stale_install).
#
# If the repo has NOT opted into bakery-sync at all (no marker, no "LLM Wiki
# sync" instruction-file switch), but its origin remote is in the johnpitralon org
# and this is a fresh ("startup") session, ask the agent to ask the user
# once whether to turn bakery-sync on for this clone — throttled to at most
# once per 24h per repo so it doesn't nag every session.
#
# 2026-10-02 fix — false "wiki not updated" after /compact. SessionStart
# fires again on resume/compact (and clear) under the SAME session_id, and
# this hook used to overwrite the snapshot unconditionally: the footprint
# (.touched) survived, but start_ts jumped to the compaction time. The
# installed Stop hook of that day counted a wiki commit only if it was newer
# than start_ts, and .wikitouched was already gone (cleared on completion),
# so a wiki written, committed and pushed at 10:07 looked missing after a
# compact at 10:08 and the session re-listed every file it ever touched
# (cms-web-react-nodejs, session ecdea2b1). An existing snapshot is now
# kept: start_ts always, repo/HEAD too unless the session moved to another
# repo (in that incident cwd went from the main checkout to a worktree, so
# "rewrite when the repo differs" alone would not have helped). The source
# field is deliberately not consulted: Claude's "startup" always carries a
# fresh session_id, Cursor reports every sessionStart as "startup", and a
# context wipe (clear) does not discharge edits already in .touched.
#
# 2026-10-19 — self-update. On EVERY fire (any repo) the hook first calls
# self_update_hooks (lib.sh): stale scripts are copied from the wiki clone
# into the running hooks dir when the clone's tools/bakery-sync equals
# origin/dev, so fixes reach everyone without a manual install.sh re-run
# (the owner's hooks sat 5 weeks behind). The note it prints is emitted
# exactly once, merged with whatever else this fire says (see emit_hint).
# Registration changes in the agent configs still need install.sh.
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

parse_agent "$@"

mkdir -p "$STATE_DIR"

input=$(cat)
sid="$(session_id_of "$input")"
[ -z "$sid" ] && exit 0

# Auto-update the installed scripts (before the enabled/ask-once logic, so it
# also works from repos that haven't opted in). NOTE is printed by the EXIT
# trap unless a hint below already carried it — Cursor needs ONE JSON
# document on stdout, so the note must never be emitted separately from it.
NOTE="$(self_update_hooks 2>/dev/null || true)"
emit_hint() {
    # emit_hint <text> -> emit_context with the pending note prefixed (once).
    # Called directly, never inside $(...): a subshell could not clear NOTE.
    local t="$1"
    [ -n "$NOTE" ] && t="$NOTE"$'\n'"$t"
    NOTE=""
    emit_context "$t"
}
flush_note() { [ -z "$NOTE" ] || emit_context "$NOTE"; }
trap flush_note EXIT

cwd="$(hook_cwd "$input")"
repo="$(repo_of "$cwd" 2>/dev/null)" || exit 0
[ -z "$repo" ] && exit 0

snapshot_session() {
    # snapshot_session <state_file> <repo> — keep an existing snapshot of
    # this session (2026-10-02 fix, see header), else write a fresh one.
    local state_file="$1" repo="$2" ts head prev_repo _prev_head prev_ts
    ts=$(date +%s)
    if [ -f "$state_file" ]; then
        IFS=$'\t' read -r prev_repo _prev_head prev_ts < "$state_file"
        case "${prev_ts:-}" in
            '' | *[!0-9]*) ;;   # unreadable snapshot -> take a fresh one
            *)
                [ "$(norm_path "${prev_repo:-}")" = "$repo" ] && return 0
                ts="$prev_ts"
                ;;
        esac
    fi
    head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo "")
    printf '%s\t%s\t%s\n' "$repo" "$head" "$ts" > "$state_file"
}

warn_stale_install() {
    # Stale-install hint (2026-10-02). A fix in tools/bakery-sync/ does nothing
    # until install.sh copies it into the hooks dir, and nothing used to say
    # so: on 2. 10. the installed Stop hook was a week behind the repo
    # (fb71275 never installed) and produced a false rewake. Compares the
    # scripts actually running (LIB_DIR) with the wiki clone the hooks check
    # against — which the bakery-sync flow keeps pulling, so a hooks change
    # landing on dev shows up here at the next startup. Throttled per drift
    # state: the same drift at most once per 24h, a different drift (another
    # file, or the same file changed again) immediately.
    [ -n "$WIKI_DIR" ] || return 0
    local src="$WIKI_DIR/tools/bakery-sync" stale sig throttle last_sig
    [ -f "$src/install.sh" ] || return 0
    stale=$(stale_hook_scripts "$LIB_DIR" "$src")
    [ -n "$stale" ] || return 0

    # shellcheck disable=SC2086  # basenames, no spaces
    sig=$(bakery_sync_hash "$(cd "$src" && cksum $stale 2>/dev/null)")
    throttle="$STATE_DIR/stale-install"
    if [ -f "$throttle" ]; then
        last_sig=$(cat "$throttle" 2>/dev/null)
        if [ "$last_sig" = "$sig" ] && [ $(( $(date +%s) - $(file_mtime "$throttle") )) -lt 86400 ]; then
            return 0
        fi
    fi
    printf '%s' "$sig" > "$throttle"

    # Reached only when self_update_hooks could not refresh the scripts (clone
    # differs from origin/dev, hooks not under $BAKERY_SYNC_HOME/hooks, ...).
    emit_hint "[bakery-sync] Nainstalované hooky v $LIB_DIR se liší od $src ($(printf '%s' "$stale" | tr '\n' ' ' | sed 's/ $//')) — opravy z repa se projeví až po reinstalaci (automatická aktualizace běží jen z čistého klonu shodného s origin/dev). V první odpovědi na to uživatele JEDNOU upozorni a nabídni spuštění (z hlavního klonu, ne z worktree):
  $(user_cmd "$src/install.sh")"
}

if is_enabled "$repo"; then
    snapshot_session "$STATE_DIR/$sid" "$repo"
    [ "$(session_source_of "$input")" = "startup" ] && warn_stale_install
    exit 0
fi

# --- ask-once: repo not enabled, no marker either way, org repo, fresh ------
src="$(session_source_of "$input")"
[ "$src" = "startup" ] || exit 0

mp="$(marker_path "$repo" 2>/dev/null || true)"
[ -n "$mp" ] && [ -f "$mp" ] && exit 0   # marker (on or off) already decided this

is_org_repo "$repo" || exit 0

asked_dir="$STATE_DIR/asked"
mkdir -p "$asked_dir"
asked_file="$asked_dir/$(bakery_sync_hash "$repo")"
if [ -f "$asked_file" ]; then
    asked_mtime=$(file_mtime "$asked_file")
    now_ts=$(date +%s)
    if [ $(( now_ts - asked_mtime )) -lt 86400 ]; then
        exit 0
    fi
fi
: > "$asked_file"

repo_name="$(basename "$repo")"
text=$(cat <<EOF
[bakery-sync] Repo $repo_name zatím nemá rozhodnutí, jestli dokumentovat změny do bakery-wiki. Hned v první odpovědi se uživatele JEDNOU zeptej: „Zapnout bakery-sync pro tento klon ($repo_name)? ano/ne“. Podle odpovědi spusť v adresáři repa:
  $(user_cmd "$BAKERY_SYNC_HOME/hooks/bakery-sync-optin.sh" on)    # nebo: off
Volba se uloží do .git/info/bakery-sync (jen tento klon, bez commitu) a příště se už neptej.
EOF
)
emit_hint "$text"
exit 0
