#!/usr/bin/env bash
# Installer for the agent-neutral bakery-sync hooks (Claude Code, Codex CLI,
# Cursor).
#
# Copies lib.sh + the six bakery-sync-*.sh scripts into $BAKERY_SYNC_HOME/hooks/
# (default ~/.bakery-sync/hooks/), writes $BAKERY_SYNC_HOME/config with this
# clone's absolute path, and registers the hooks in each selected agent's
# own config file — without disturbing any other hooks, permissions, or
# settings already there.
#
# Usage:
#   ./install.sh                        install (or update) the hooks,
#                                        auto-detecting installed agents
#   ./install.sh --agent claude,codex    install only for the given agents
#   ./install.sh --agent all             install for all three agents
#   ./install.sh --dry-run               print what would be done, change nothing
#   ./install.sh --uninstall             remove the hook registrations and scripts
#   ./install.sh --uninstall --dry-run   preview the uninstall
#
# Run it from the MAIN clone: the clone it runs from becomes the hooks'
# BAKERY_SYNC_WIKI_DIR, so installing from a linked git worktree is refused
# whenever the main worktree carries the installer (uninstall is allowed).
#
# Safe by construction:
#   - every file write that would overwrite a *different* existing file is
#     preceded by a timestamped backup (<name>.bak-<YYYYMMDD-HHMMSS>)
#   - agent config files are patched with jq, atomically (tmp file + mv), and
#     only after their own timestamped backup; all existing hooks/keys are
#     preserved
#   - re-running is idempotent: identical files are left alone, identical
#     hook registrations are not duplicated
#
# Only touches, per selected agent: ~/.claude/settings.json, ~/.codex/hooks.json,
# ~/.cursor/hooks.json,
# and always $BAKERY_SYNC_HOME/{hooks,config} (uninstall does not remove
# $BAKERY_SYNC_HOME/state — that's session history, not installed files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BAKERY_SYNC_HOME="${BAKERY_SYNC_HOME:-$HOME/.bakery-sync}"
HOOKS_DIR="$BAKERY_SYNC_HOME/hooks"
STATE_DIR_DEFAULT="$BAKERY_SYNC_HOME/state"
CONFIG_FILE="$BAKERY_SYNC_HOME/config"

CLAUDE_DIR="${HOME}/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
CODEX_DIR="${HOME}/.codex"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
CURSOR_DIR="${HOME}/.cursor"
CURSOR_HOOKS="$CURSOR_DIR/hooks.json"

# Scripts Codex (hook runner) or the model invokes on Windows: each gets a
# <name>.cmd wrapper next to it (see write_win_wrappers).
WIN_WRAPPED="bakery-sync-session-start bakery-sync-touched bakery-sync-stop bakery-sync-delegated bakery-sync-ack bakery-sync-optin"

LIB_AND_SCRIPTS="lib.sh bakery-sync-session-start.sh bakery-sync-touched.sh bakery-sync-stop.sh bakery-sync-ack.sh bakery-sync-delegated.sh bakery-sync-optin.sh"

DRY_RUN=0
UNINSTALL=0
AGENTS_ARG=""

print_help() {
    # the whole leading comment block, minus the shebang
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --agent)
            shift
            AGENTS_ARG="${1:-}"
            ;;
        --agent=*)
            AGENTS_ARG="${1#--agent=}"
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift
done

log() { printf '%s\n' "$*"; }
would() { if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] $*"; else log "$*"; fi }

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required to safely edit agent config files but is not installed." >&2
        echo "Install it first, e.g.: brew install jq" >&2
        exit 1
    fi
}

timestamp() { date +%Y%m%d-%H%M%S; }

# Same checks as lib.sh's is_windows_shell / win_bash_exe — duplicated on
# purpose: the installer must not source lib.sh (it would clobber the
# installer's own BAKERY_SYNC_HOME/STATE_DIR and run its PATH side effects).
is_windows_shell() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}
win_bash_exe() { cygpath -w "$(command -v bash)"; }

# ---------------------------------------------------------------------------
# agent selection
# ---------------------------------------------------------------------------

detect_agents() {
    local list=""
    [ -d "$CLAUDE_DIR" ] && list="$list claude"
    [ -d "$CODEX_DIR" ] && list="$list codex"
    [ -d "$CURSOR_DIR" ] && list="$list cursor"
    printf '%s' "${list# }"
}

resolve_agents() {
    local spec="$1" out=""
    if [ -z "$spec" ]; then
        detect_agents
        return
    fi
    if [ "$spec" = "all" ]; then
        printf 'claude codex cursor'
        return
    fi
    local a
    local IFS=,
    for a in $spec; do
        case "$a" in
            claude|codex|cursor) out="$out $a" ;;
            *)
                echo "ERROR: unknown agent '$a' in --agent (expected claude,codex,cursor or all)" >&2
                exit 1
                ;;
        esac
    done
    printf '%s' "${out# }"
}

SELECTED_AGENTS="$(resolve_agents "$AGENTS_ARG")"
if [ -z "$SELECTED_AGENTS" ]; then
    echo "ERROR: no agent directories found (~/.claude, ~/.codex, ~/.cursor) and no --agent given." >&2
    exit 1
fi

has_agent() {
    case " $SELECTED_AGENTS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# shared: copy lib.sh + scripts, write config
# ---------------------------------------------------------------------------

install_scripts() {
    if [ "$DRY_RUN" -eq 1 ]; then
        would "mkdir -p $HOOKS_DIR"
    else
        mkdir -p "$HOOKS_DIR"
    fi

    for name in $LIB_AND_SCRIPTS; do
        src="$SCRIPT_DIR/$name"
        dst="$HOOKS_DIR/$name"

        if [ ! -f "$src" ]; then
            echo "ERROR: missing source file: $src" >&2
            exit 1
        fi

        if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
            bak="$dst.bak-$(timestamp)"
            would "backing up existing $dst -> $bak"
            [ "$DRY_RUN" -eq 1 ] || cp "$dst" "$bak"
        fi

        if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
            log "unchanged: $dst"
        else
            would "installing $dst (mode 0755)"
            if [ "$DRY_RUN" -eq 0 ]; then
                cp "$src" "$dst"
                chmod 0755 "$dst"
            fi
        fi
    done
}

main_worktree_of() {
    # main_worktree_of <dir> -> path of the main worktree when <dir> is a
    # LINKED git worktree; nothing for a main checkout or a non-git dir.
    local dir="$1" git_dir common_dir
    git_dir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || return 0
    common_dir=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 0
    [ -n "$git_dir" ] && [ -n "$common_dir" ] || return 0
    git_dir=$(cd "$dir" && cd "$git_dir" && pwd -P) || return 0
    common_dir=$(cd "$dir" && cd "$common_dir" && pwd -P) || return 0
    [ "$git_dir" = "$common_dir" ] && return 0
    git -C "$dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'
}

refuse_linked_worktree() {
    # 2026-10-02: write_config makes CLONE_ROOT the hooks' BAKERY_SYNC_WIKI_DIR.
    # Run from a linked worktree (e.g. an agent worktree under
    # .claude/worktrees/, deleted when the session ends) the hooks would
    # follow a temporary path, and the stale-install hint would compare
    # against a branch nobody pulls. Refuse only when the main worktree has
    # the installer — in a bare-repo layout the main "worktree" has no files
    # and a linked worktree IS the long-lived checkout.
    local main
    main=$(main_worktree_of "$CLONE_ROOT")
    [ -n "$main" ] || return 0
    [ -f "$main/tools/bakery-sync/install.sh" ] || return 0
    echo "ERROR: $CLONE_ROOT is a linked git worktree — the hooks would point at it (BAKERY_SYNC_WIKI_DIR) and break once it is removed." >&2
    echo "Run the installer from the main clone instead:" >&2
    echo "  $main/tools/bakery-sync/install.sh" >&2
    exit 1
}

write_config() {
    if [ ! -f "$CLONE_ROOT/wiki/index.md" ]; then
        echo "ERROR: $CLONE_ROOT does not look like the bakery-wiki clone (wiki/index.md missing) — refusing to write config." >&2
        exit 1
    fi
    local desired="BAKERY_SYNC_WIKI_DIR=$CLONE_ROOT"

    if [ -f "$CONFIG_FILE" ] && [ "$(cat "$CONFIG_FILE")" = "$desired" ]; then
        log "unchanged: $CONFIG_FILE"
        return
    fi

    if [ -f "$CONFIG_FILE" ]; then
        would "config differs from this clone — backing up $CONFIG_FILE and rewriting with: $desired"
    else
        would "writing $CONFIG_FILE ($desired)"
    fi

    [ "$DRY_RUN" -eq 1 ] && return

    mkdir -p "$BAKERY_SYNC_HOME"
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak-$(timestamp)"
    fi
    printf '%s\n' "$desired" > "$CONFIG_FILE"
    log "wrote $CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# hook-entry builders
# ---------------------------------------------------------------------------

already_present() {
    # already_present <json> <dotted-path> <entry_json> -> "true"/"false"
    local json="$1" path="$2" entry="$3"
    printf '%s' "$json" | jq -e --argjson e "$entry" --arg path "$path" '
        (getpath($path | split(".")) // []) as $a
        | any($a[]; . == $e)
    ' >/dev/null 2>&1 && echo true || echo false
}

needs_upgrade() {
    # needs_upgrade <json> <dotted-path> <entry_json> -> "true" when an entry
    # with the same command exists but differs from <entry_json> (e.g. a
    # Codex registration from before `commandWindows`): update it in place.
    local json="$1" path="$2" entry="$3"
    printf '%s' "$json" | jq -e --argjson e "$entry" --arg path "$path" '
        (getpath($path | split(".")) // []) as $a
        | any($a[]; .hooks[0].command? == $e.hooks[0].command and . != $e)
    ' >/dev/null 2>&1 && echo true || echo false
}

json_entry_hooks() {
    # json_entry_hooks <matcher-or-empty> <cmd> <timeout>
    local matcher="$1" cmd="$2" timeout="$3"
    if [ -n "$matcher" ]; then
        jq -n --arg matcher "$matcher" --arg cmd "$cmd" --argjson timeout "$timeout" \
            '{matcher: $matcher, hooks: [{type: "command", command: $cmd, timeout: $timeout}]}'
    else
        jq -n --arg cmd "$cmd" --argjson timeout "$timeout" \
            '{hooks: [{type: "command", command: $cmd, timeout: $timeout}]}'
    fi
}

json_entry_hooks_codex() {
    # json_entry_hooks_codex <matcher-or-empty> <cmd> <timeout> <cmd_windows-or-empty>
    # Same as json_entry_hooks, plus Codex's Windows-only override field
    # `commandWindows` when given (native-Windows Codex runs hook commands in
    # PowerShell, which cannot execute a .sh path).
    local matcher="$1" cmd="$2" timeout="$3" cmdw="$4"
    json_entry_hooks "$matcher" "$cmd" "$timeout" | jq --arg w "$cmdw" '
        if $w != "" then .hooks[0].commandWindows = $w else . end'
}

json_entry_stop_claude() {
    local cmd="$1"
    jq -n --arg cmd "$cmd" \
        '{hooks: [{type: "command", command: $cmd, timeout: 15, asyncRewake: true, rewakeSummary: "Bakery wiki sync reminder"}]}'
}

cursor_entry() {
    jq -n --arg cmd "$1" '{command: $cmd}'
}

claude_home_display() {
    # Claude expands "~" in settings.json commands; use the short form only
    # when BAKERY_SYNC_HOME is the default, else the literal (possibly
    # overridden) absolute path.
    if [ "$BAKERY_SYNC_HOME" = "$HOME/.bakery-sync" ]; then
        printf '~/.bakery-sync'
    else
        printf '%s' "$BAKERY_SYNC_HOME"
    fi
}

claude_cmd() { printf '%s/hooks/%s --agent claude' "$(claude_home_display)" "$1"; }
codex_cmd()  { printf '%s/hooks/%s --agent codex'  "$BAKERY_SYNC_HOME" "$1"; }
cursor_cmd() { printf '%s/hooks/%s --agent cursor' "$BAKERY_SYNC_HOME" "$1"; }

codex_cmd_windows() {
    # Windows-only override for Codex. We do not know whether Codex runs it via
    # PowerShell or cmd, and a quoted `"a b.exe" "c" args` breaks in both, so
    # the command is the UNQUOTED forward-slash path of the .cmd wrapper
    # (write_win_wrappers) plus args — valid in either shell. A username with
    # a space falls back to the 8.3 short path; if that still has a space,
    # warn and use the quoted bash.exe form. Empty off Windows.
    is_windows_shell || return 0
    local name="${1%.sh}" w p
    w="$HOOKS_DIR/$name.cmd"
    p=$(cygpath -m "$w")
    case "$p" in
        *" "*) p=$(cygpath -m -s "$w" 2>/dev/null || true) ;;
    esac
    case "$p" in
        ''|*" "*)
            echo "WARNING: $w contains a space and has no 8.3 short path — using a quoted commandWindows that may not run in every shell." >&2
            printf '"%s" "%s/hooks/%s.sh" --agent codex' "$(win_bash_exe)" "$(cygpath -m "$BAKERY_SYNC_HOME")" "$name"
            return 0
            ;;
    esac
    printf '%s --agent codex' "$p"
}

write_win_wrappers() {
    # Windows only: <name>.cmd next to each script Codex/the model invokes,
    #   @"<Git Bash bash.exe>" "%~dp0<name>.sh" %*
    # with CRLF line endings (%~dp0 = the wrapper's own directory, so the
    # hooks dir stays relocatable; bash.exe is the absolute Git Bash path,
    # never the System32 WSL launcher). Written only when the content differs.
    # Exit codes propagate through the batch file; Codex's Stop hook reports
    # via JSON on exit 0, so they are not critical anyway. self_update_hooks
    # does not touch the wrappers: they never change when the scripts do.
    is_windows_shell || return 0
    local name f tmp
    tmp=$(mktemp)
    for name in $WIN_WRAPPED; do
        f="$HOOKS_DIR/$name.cmd"
        printf '@"%s" "%%~dp0%s.sh" %%*\r\n' "$(win_bash_exe)" "$name" > "$tmp"
        if [ -f "$f" ] && cmp -s "$tmp" "$f"; then
            log "unchanged: $f"
            continue
        fi
        would "writing wrapper $f"
        [ "$DRY_RUN" -eq 1 ] || cp "$tmp" "$f"
    done
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# generic registration: hooks.<Event>[] = {matcher?, hooks:[{type,command,timeout,...}]}
# (this shape is identical for Claude's settings.json and Codex's hooks.json)
# ---------------------------------------------------------------------------

# Set to 1 when _register_three actually wrote the file (not dry-run).
REGISTER_WROTE=0

_register_three() {
    # The optional 9th argument "upgrade" makes an existing entry with the
    # same command but different content be replaced in place instead of
    # duplicated (used for Codex; Claude keeps the append-only behaviour).
    local file="$1" label="$2"
    local ev1="$3" en1="$4" ev2="$5" en2="$6" ev3="$7" en3="$8" mode="${9:-}"

    local current='{"hooks":{}}'
    if [ -f "$file" ]; then
        current=$(cat "$file")
        if ! printf '%s' "$current" | jq -e . >/dev/null 2>&1; then
            echo "ERROR: $file is not valid JSON — refusing to touch it." >&2
            exit 1
        fi
    else
        would "no existing $file — will create a minimal one with just the hooks key"
    fi

    local need1 need2 need3
    need1=$([ "$(already_present "$current" "hooks.$ev1" "$en1")" = "true" ] && echo false || echo true)
    need2=$([ "$(already_present "$current" "hooks.$ev2" "$en2")" = "true" ] && echo false || echo true)
    need3=$([ "$(already_present "$current" "hooks.$ev3" "$en3")" = "true" ] && echo false || echo true)

    if [ "$need1" = false ] && [ "$need2" = false ] && [ "$need3" = false ]; then
        log "$label: all hook registrations already present — nothing to do"
        return
    fi

    local up1=false up2=false up3=false
    if [ "$mode" = upgrade ]; then
        [ "$need1" = true ] && up1=$(needs_upgrade "$current" "hooks.$ev1" "$en1")
        [ "$need2" = true ] && up2=$(needs_upgrade "$current" "hooks.$ev2" "$en2")
        [ "$need3" = true ] && up3=$(needs_upgrade "$current" "hooks.$ev3" "$en3")
    fi

    would "registering bakery-sync hooks in $file ($label)"
    [ "$need1" = true ] && would "  $([ "$up1" = true ] && echo '~' || echo '+') $ev1 -> $(printf '%s' "$en1" | jq -r '.hooks[0].command')"
    [ "$need2" = true ] && would "  $([ "$up2" = true ] && echo '~' || echo '+') $ev2 -> $(printf '%s' "$en2" | jq -r '.hooks[0].command')"
    [ "$need3" = true ] && would "  $([ "$up3" = true ] && echo '~' || echo '+') $ev3 -> $(printf '%s' "$en3" | jq -r '.hooks[0].command')"

    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi

    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ]; then
        local bak="$file.bak-$(timestamp)"
        cp "$file" "$bak"
        log "backed up $file -> $bak"
    fi

    local tmp
    tmp=$(mktemp "$(dirname "$file")/$(basename "$file").tmp.XXXXXX")

    printf '%s' "$current" | jq \
        --argjson e1 "$en1" --argjson e2 "$en2" --argjson e3 "$en3" \
        --argjson n1 "$need1" --argjson n2 "$need2" --argjson n3 "$need3" \
        --argjson u1 "$up1" --argjson u2 "$up2" --argjson u3 "$up3" \
        --arg ev1 "$ev1" --arg ev2 "$ev2" --arg ev3 "$ev3" '
        # replace the first same-command entry with $e, drop further ones
        def upsert($e):
            (map(.hooks[0].command? == $e.hooks[0].command) | index(true)) as $i
            | to_entries
            | map(if .key == $i then $e
                  elif .value.hooks[0].command? == $e.hooks[0].command then empty
                  else .value end);
        .hooks //= {}
        | .hooks[$ev1] //= []
        | .hooks[$ev2] //= []
        | .hooks[$ev3] //= []
        | if $n1 then (if $u1 then .hooks[$ev1] |= upsert($e1) else .hooks[$ev1] += [$e1] end) else . end
        | if $n2 then (if $u2 then .hooks[$ev2] |= upsert($e2) else .hooks[$ev2] += [$e2] end) else . end
        | if $n3 then (if $u3 then .hooks[$ev3] |= upsert($e3) else .hooks[$ev3] += [$e3] end) else . end
    ' > "$tmp"

    mv "$tmp" "$file"
    REGISTER_WROTE=1
    log "updated $file"
}

_register_three_cursor() {
    local file="$1"
    local ev1="$2" en1="$3" ev2="$4" en2="$5" ev3="$6" en3="$7"

    local current='{"version":1,"hooks":{}}'
    if [ -f "$file" ]; then
        current=$(cat "$file")
        if ! printf '%s' "$current" | jq -e . >/dev/null 2>&1; then
            echo "ERROR: $file is not valid JSON — refusing to touch it." >&2
            exit 1
        fi
    else
        would "no existing $file — will create a minimal one with version 1 and just the hooks key"
    fi

    local need1 need2 need3 version_ok
    need1=$([ "$(already_present "$current" "hooks.$ev1" "$en1")" = "true" ] && echo false || echo true)
    need2=$([ "$(already_present "$current" "hooks.$ev2" "$en2")" = "true" ] && echo false || echo true)
    need3=$([ "$(already_present "$current" "hooks.$ev3" "$en3")" = "true" ] && echo false || echo true)
    version_ok=$(printf '%s' "$current" | jq -e '.version == 1' >/dev/null 2>&1 && echo true || echo false)

    if [ "$need1" = false ] && [ "$need2" = false ] && [ "$need3" = false ] && [ "$version_ok" = true ]; then
        log "cursor hooks.json: all hook registrations already present — nothing to do"
        return
    fi

    would "registering bakery-sync hooks in $file (cursor)"
    [ "$need1" = true ] && would "  + $ev1 -> $(printf '%s' "$en1" | jq -r '.command')"
    [ "$need2" = true ] && would "  + $ev2 -> $(printf '%s' "$en2" | jq -r '.command')"
    [ "$need3" = true ] && would "  + $ev3 -> $(printf '%s' "$en3" | jq -r '.command')"
    [ "$version_ok" = false ] && would "  + ensuring version: 1"

    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi

    mkdir -p "$(dirname "$file")"
    if [ -f "$file" ]; then
        local bak="$file.bak-$(timestamp)"
        cp "$file" "$bak"
        log "backed up $file -> $bak"
    fi

    local tmp
    tmp=$(mktemp "$(dirname "$file")/$(basename "$file").tmp.XXXXXX")

    printf '%s' "$current" | jq \
        --argjson e1 "$en1" --argjson e2 "$en2" --argjson e3 "$en3" \
        --argjson n1 "$need1" --argjson n2 "$need2" --argjson n3 "$need3" \
        --arg ev1 "$ev1" --arg ev2 "$ev2" --arg ev3 "$ev3" '
        .version = 1
        | .hooks //= {}
        | .hooks[$ev1] //= []
        | .hooks[$ev2] //= []
        | .hooks[$ev3] //= []
        | if $n1 then .hooks[$ev1] += [$e1] else . end
        | if $n2 then .hooks[$ev2] += [$e2] else . end
        | if $n3 then .hooks[$ev3] += [$e3] else . end
    ' > "$tmp"

    mv "$tmp" "$file"
    log "updated $file"
}

# ---------------------------------------------------------------------------
# per-agent: registration
# ---------------------------------------------------------------------------

register_claude_hooks() {
    require_jq

    local ss pt stop
    ss=$(json_entry_hooks "" "$(claude_cmd bakery-sync-session-start.sh)" 5)
    pt=$(json_entry_hooks "Write|Edit|NotebookEdit" "$(claude_cmd bakery-sync-touched.sh)" 5)
    stop=$(json_entry_stop_claude "$(claude_cmd bakery-sync-stop.sh)")

    _register_three "$CLAUDE_SETTINGS" "claude settings.json" \
        SessionStart "$ss" PostToolUse "$pt" Stop "$stop"
}

register_codex_hooks() {
    require_jq
    local ss pt stop
    ss=$(json_entry_hooks_codex "" "$(codex_cmd bakery-sync-session-start.sh)" 5 "$(codex_cmd_windows bakery-sync-session-start.sh)")
    pt=$(json_entry_hooks_codex "apply_patch|Edit|Write" "$(codex_cmd bakery-sync-touched.sh)" 5 "$(codex_cmd_windows bakery-sync-touched.sh)")
    stop=$(json_entry_hooks_codex "" "$(codex_cmd bakery-sync-stop.sh)" 15 "$(codex_cmd_windows bakery-sync-stop.sh)")

    if [ ! -f "$CODEX_HOOKS" ]; then
        would "no existing $CODEX_HOOKS — will create {\"hooks\":{}}"
    fi

    REGISTER_WROTE=0
    _register_three "$CODEX_HOOKS" "codex hooks.json" \
        SessionStart "$ss" PostToolUse "$pt" Stop "$stop" upgrade

    if [ "$REGISTER_WROTE" -eq 1 ]; then
        log "note: Codex hashes its hooks — on next start it will report \"hooks need review\". Approve them once in the TUI (/hooks or the startup prompt)."
    fi
}

register_cursor_hooks() {
    require_jq
    local ss ae stop
    ss=$(cursor_entry "$(cursor_cmd bakery-sync-session-start.sh)")
    ae=$(cursor_entry "$(cursor_cmd bakery-sync-touched.sh)")
    stop=$(cursor_entry "$(cursor_cmd bakery-sync-stop.sh)")

    _register_three_cursor "$CURSOR_HOOKS" \
        sessionStart "$ss" afterFileEdit "$ae" stop "$stop"
}

# ---------------------------------------------------------------------------
# manual follow-up
# ---------------------------------------------------------------------------

print_manual_steps() {
    cat <<EOF

Manual follow-up (the installer does not do this for you):

1. Add a "Wiki updates" section to your own instruction file describing how
   you want wiki edits handled (e.g. delegated to a subagent, committed
   straight to dev):
     - Claude Code: ~/.claude/CLAUDE.md
     - Codex CLI:   ~/.codex/AGENTS.md
     - Cursor:      ~/.cursor/rules/wiki-updates.mdc  (alwaysApply: true)
   See $CLONE_ROOT/tools/bakery-sync/README.md for the convention this
   project follows.

2. Each repo needs a way to turn bakery-sync ON. Either:
     a) team-level — its CLAUDE.md or AGENTS.md contains a section literally
        titled:

          ## Bakery Wiki sync (blocking rule)

        This exact string is the switch the hooks look for; or
     b) per-clone — from inside that repo's clone (no commit, this clone only):

          $BAKERY_SYNC_HOME/hooks/bakery-sync-optin.sh on   # or: off

   Without either, the hooks stay completely silent for that repo — by
   design, so unrelated projects are never nagged about the wiki. A repo
   whose origin remote is in the johnpitralon org and has neither gets a one-time
   "want to turn this on?" prompt at session start instead (at most once per
   24h), which tells the agent to run bakery-sync-optin.sh once you answer.
EOF
}

# ---------------------------------------------------------------------------
# install / uninstall drivers
# ---------------------------------------------------------------------------

do_install() {
    log "== bakery-sync hooks installer =="
    [ "$DRY_RUN" -eq 1 ] && log "(dry run — no changes will be made)"
    log "selected agents: $SELECTED_AGENTS"

    refuse_linked_worktree
    install_scripts
    write_config

    has_agent claude && register_claude_hooks
    has_agent codex  && write_win_wrappers
    has_agent codex  && register_codex_hooks
    has_agent cursor && register_cursor_hooks

    [ "$DRY_RUN" -eq 0 ] && print_manual_steps
    log "done."
}

unregister_std() {
    local file="$1" label="$2"
    if [ ! -f "$file" ]; then
        log "$label: not found — nothing to unregister"
        return
    fi
    local current
    current=$(cat "$file")
    if ! printf '%s' "$current" | jq -e . >/dev/null 2>&1; then
        echo "ERROR: $file is not valid JSON — refusing to touch it." >&2
        exit 1
    fi

    would "removing bakery-sync hook entries from $file ($label)"

    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi

    local bak="$file.bak-$(timestamp)"
    cp "$file" "$bak"
    log "backed up $file -> $bak"

    local tmp
    tmp=$(mktemp "$(dirname "$file")/$(basename "$file").tmp.XXXXXX")

    printf '%s' "$current" | jq '
        def dropcmd: map(select((.hooks // [] | any(.command? // "" | test("bakery-sync-"))) | not));
        if .hooks then
            .hooks |= with_entries(.value |= dropcmd)
        else . end
    ' > "$tmp"

    mv "$tmp" "$file"
    log "updated $file"
}

unregister_cursor() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log "cursor hooks.json: not found — nothing to unregister"
        return
    fi
    local current
    current=$(cat "$file")
    if ! printf '%s' "$current" | jq -e . >/dev/null 2>&1; then
        echo "ERROR: $file is not valid JSON — refusing to touch it." >&2
        exit 1
    fi

    would "removing bakery-sync hook entries from $file (cursor)"

    if [ "$DRY_RUN" -eq 1 ]; then
        return
    fi

    local bak="$file.bak-$(timestamp)"
    cp "$file" "$bak"
    log "backed up $file -> $bak"

    local tmp
    tmp=$(mktemp "$(dirname "$file")/$(basename "$file").tmp.XXXXXX")

    printf '%s' "$current" | jq '
        if .hooks then
            .hooks |= with_entries(.value |= map(select((.command? // "" | test("bakery-sync-")) | not)))
        else . end
    ' > "$tmp"

    mv "$tmp" "$file"
    log "updated $file"
}

uninstall_scripts() {
    if [ ! -d "$HOOKS_DIR" ]; then
        log "not installed: $HOOKS_DIR"
        return
    fi
    # generated Windows wrappers (write_win_wrappers) — no backup, they are derived files
    local w
    for name in $WIN_WRAPPED; do
        w="$HOOKS_DIR/$name.cmd"
        if [ -f "$w" ]; then
            would "removing wrapper $w"
            [ "$DRY_RUN" -eq 1 ] || rm -f "$w"
        fi
    done
    for name in $LIB_AND_SCRIPTS; do
        dst="$HOOKS_DIR/$name"
        if [ -f "$dst" ]; then
            bak="$dst.bak-$(timestamp)"
            would "removing $dst (backed up to $bak first)"
            if [ "$DRY_RUN" -eq 0 ]; then
                cp "$dst" "$bak"
                rm -f "$dst"
            fi
        else
            log "not installed: $dst"
        fi
    done
}

do_uninstall() {
    log "== bakery-sync hooks uninstaller =="
    [ "$DRY_RUN" -eq 1 ] && log "(dry run — no changes will be made)"
    log "selected agents: $SELECTED_AGENTS"

    has_agent claude && unregister_std "$CLAUDE_SETTINGS" "claude settings.json"
    has_agent codex  && unregister_std "$CODEX_HOOKS" "codex hooks.json"
    has_agent cursor && unregister_cursor "$CURSOR_HOOKS"

    uninstall_scripts
    log "note: $STATE_DIR_DEFAULT/ (session history) and $CONFIG_FILE were left in place; remove them manually if desired."
    log "done."
}

if [ "$UNINSTALL" -eq 1 ]; then
    do_uninstall
else
    do_install
fi
