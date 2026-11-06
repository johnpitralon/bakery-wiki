#!/usr/bin/env bash
# lib.sh — shared helpers for the bakery-sync hooks (Claude Code / Codex CLI /
# Cursor). Sourced by every bakery-sync-*.sh script; not meant to be run
# directly. Keep this POSIX-ish bash: no GNU-only flags, no `sed -i` (BSD
# sed's `-i` needs a backup-suffix argument GNU sed treats differently — use
# sed_inplace below instead). Must run under macOS's bash 3.2, Linux/WSL
# bash, and Git Bash on Windows.

# --- paths & tunables --------------------------------------------------------

# macOS's /usr/bin/git can exist but fail until the Xcode licence is accepted.
# Keep a working Git from PATH; otherwise try the installed Command Line Tools.
# Resolve this inside the hooks so installer registrations stay idempotent.
if [ -x /Library/Developer/CommandLineTools/usr/bin/git ] &&
   ! git --version >/dev/null 2>&1 &&
   /Library/Developer/CommandLineTools/usr/bin/git --version >/dev/null 2>&1; then
    export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"
fi

BAKERY_SYNC_HOME="${BAKERY_SYNC_HOME:-$HOME/.bakery-sync}"
STATE_DIR="${BAKERY_SYNC_STATE_DIR:-$BAKERY_SYNC_HOME/state}"
ACTIVE_WINDOW="${BAKERY_SYNC_ACTIVE_WINDOW:-600}"
COOLDOWN="${BAKERY_SYNC_COOLDOWN:-300}"
# How long a "wiki write delegated to a background subagent" declaration
# (bakery-sync-delegated.sh -> <state>.delegated) silences the Stop hook.
DELEGATE_WINDOW="${BAKERY_SYNC_DELEGATE_WINDOW:-1800}"
ORG_RE="${BAKERY_SYNC_ORG_RE:-(github\.com|github-johnpitralon)[:/]johnpitralon/}"

_bakery_sync_config_get() {
    # _bakery_sync_config_get <KEY> <file> -> prints value or nothing.
    # Simple KEY=VALUE parser (grep/cut) — never `source`s the file, since it
    # is not trusted input in the same way as a script we ship ourselves.
    local key="$1" file="$2"
    [ -f "$file" ] || return 0
    grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d'=' -f2-
}

# WIKI_DIR: env override first, else the value the installer wrote into
# $BAKERY_SYNC_HOME/config, else empty. Callers must treat "empty" the same as
# "wiki repo not present locally" (stay silent) — no more hardcoded default
# pointing at the original macOS clone layout.
if [ -n "${BAKERY_SYNC_WIKI_DIR:-}" ]; then
    WIKI_DIR="$BAKERY_SYNC_WIKI_DIR"
else
    WIKI_DIR="$(_bakery_sync_config_get BAKERY_SYNC_WIKI_DIR "$BAKERY_SYNC_HOME/config")"
fi

# --- hashing (best available tool; shasum on macOS, sha1sum on most Linux) --

bakery_sync_hash() {
    # bakery_sync_hash <string> -> a stable-ish hex digest, best tool available.
    if command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum | awk '{print $1}'
    elif command -v sha1sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha1sum | awk '{print $1}'
    else
        printf '%s' "$1" | cksum | awk '{print $1}'
    fi
}

# --- session footprint --------------------------------------------------------

# Draft design specs/plans under docs/superpowers/{specs,plans}/ are brainstorm
# artifacts, not behavior/architecture changes — never part of the footprint.
SPEC_PATH_RE='docs/superpowers/(specs|plans)/'

footprint_of() {
    # footprint_of <touched_file> -> "footprint version" on stdout: the hash
    # of the RAW non-draft footprint (unsorted, with repeats). .touched is
    # append-only, so every new source edit — even to a file already listed —
    # changes it; draft-spec edits don't. Unlike the sort -u'd signature used
    # for cooldown/ack it cannot miss a re-edit. ONE definition shared by the
    # Stop hook (.synced) and bakery-sync-delegated.sh (.delegated), so both
    # always compare like with like.
    local f="$1"
    bakery_sync_hash "$( { [ -f "$f" ] && grep -vE "$SPEC_PATH_RE" "$f" | grep -vE '^[[:space:]]*$'; } || true)"
}

# --- file mtime (BSD vs GNU stat) -------------------------------------------

file_mtime() {
    # file_mtime <path> -> modification time as a unix epoch integer, 0 if it
    # can't be read. Always returns a BARE INTEGER: callers feed it straight
    # into $(( )) under `set -u`, where any stray word aborts the hook.
    #
    # Order matters, and so does the numeric check. GNU's `stat -f` is
    # --file-system, which does NOT reject the BSD "%m" format: it takes it
    # as another FILE operand, fails on that one (exit 1) — and still prints
    # a filesystem block for the real file on STDOUT. In a `$(a || b)` chain
    # that block is captured together with b's output, so a BSD-first probe
    # returned 'File: "..." ... 1700000000' on Git Bash and every caller died
    # with "File: unbound variable" (2026-09-14; the active-work window and
    # the ask-once throttle were dead on Windows). BSD stat, in the other
    # direction, rejects -c with a usage error and prints nothing to stdout,
    # so GNU-first is safe both ways.
    local ts
    ts=$(stat -c %Y "$1" 2>/dev/null) || ts=$(stat -f %m "$1" 2>/dev/null) || ts=""
    case "$ts" in
        '' | *[!0-9]*) printf '0\n' ;;
        *)             printf '%s\n' "$ts" ;;
    esac
}

# --- agent selection ----------------------------------------------------------

AGENT="claude"

parse_agent() {
    # parse_agent "$@" -> sets global AGENT. Recognises --agent X / --agent=X
    # anywhere in the argument list; falls back to $BAKERY_SYNC_AGENT, then
    # "claude". Exits 1 on an unrecognised agent name.
    AGENT="${BAKERY_SYNC_AGENT:-claude}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --agent)
                shift
                AGENT="${1:-}"
                ;;
            --agent=*)
                AGENT="${1#--agent=}"
                ;;
        esac
        shift
    done
    case "$AGENT" in
        claude|codex|cursor) ;;
        *)
            echo "bakery-sync: unknown --agent '$AGENT' (expected claude|codex|cursor)" >&2
            exit 1
            ;;
    esac
}

# --- platform & agent-runnable commands ---------------------------------------

is_windows_shell() {
    # True under Git Bash / MSYS2 / Cygwin (native Windows, no WSL: WSL's
    # uname says Linux and WSL paths are POSIX anyway).
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

win_bash_exe() {
    # Windows path of the bash running us, e.g.
    # C:\Program Files\Git\usr\bin\bash.exe. Always spell this absolute
    # path out for PowerShell: a bare `bash` there can resolve to
    # C:\Windows\System32\bash.exe (the WSL launcher), not Git Bash.
    cygpath -w "$(command -v bash)"
}

win_cmd_wrapper() {
    # win_cmd_wrapper <posix_script_path> -> forward-slash Windows path of the
    # .cmd wrapper install.sh wrote next to the script, ONLY if the wrapper
    # exists and its path needs no quoting (no space; a username with a
    # space falls back to the 8.3 short path). Returns 1 otherwise.
    local w="${1%.sh}.cmd" p
    [ -f "$w" ] || return 1
    p=$(cygpath -m "$w") || return 1
    case "$p" in
        *" "*) p=$(cygpath -m -s "$w" 2>/dev/null) || return 1 ;;
    esac
    case "$p" in
        ''|*" "*) return 1 ;;
    esac
    printf '%s' "$p"
}

user_cmd() {
    # user_cmd <posix_script_path> [args...] -> the command line the AGENT
    # (the model) should run for one of our scripts. Codex on native Windows
    # executes commands in PowerShell, which cannot run a /c/Users/.../x.sh
    # path. There it gets the unquoted path of the .cmd wrapper install.sh
    # wrote (win_cmd_wrapper) — runs as-is in PowerShell and cmd alike. A
    # script without a usable wrapper (install.sh itself, a spaced path)
    # gets `& "<Git Bash bash.exe>" "<C:/ script>"` instead. install.sh (any
    # agent, on Windows) renders as the install.ps1 PowerShell launcher. Every other
    # combination — including Claude Code on Windows, which itself runs
    # commands through Git Bash — keeps the plain POSIX path.
    local script="$1" w
    shift
    if [ "${script##*/}" = "install.sh" ] && is_windows_shell && [ -f "${script%.sh}.ps1" ]; then
        # Windows users only use PowerShell: the installer entry point is the
        # install.ps1 launcher (any agent, the user types it).
        printf 'powershell -NoProfile -ExecutionPolicy Bypass -File "%s"' "$(cygpath -w "${script%.sh}.ps1")"
    elif [ "$AGENT" = "codex" ] && is_windows_shell; then
        if w=$(win_cmd_wrapper "$script"); then
            printf '%s' "$w"
        else
            printf '& "%s" "%s"' "$(win_bash_exe)" "$(cygpath -m "$script")"
        fi
    else
        printf '%s' "$script"
    fi
    if [ $# -gt 0 ]; then
        printf ' %s' "$*"
    fi
}

# --- path normalisation -------------------------------------------------------

norm_path() {
    # norm_path <path> -> normalised path on stdout. On Git Bash, `cygpath -u`
    # turns a Windows-style path (C:\... or C:/...) into the POSIX form
    # (/c/...) that the string-prefix comparisons in these scripts assume;
    # elsewhere it's a no-op since cygpath doesn't exist. Repeated slashes are
    # collapsed and a trailing slash is stripped so "/a/b/", "/a//b" and
    # "/a/b" all compare equal.
    local p="${1:-}"
    if command -v cygpath >/dev/null 2>&1; then
        p="$(cygpath -u "$p" 2>/dev/null || printf '%s' "$p")"
    fi
    p="$(printf '%s' "$p" | sed -e 's#//*#/#g')"
    case "$p" in
        */) p="${p%/}" ;;
    esac
    [ -z "$p" ] && p="/"
    printf '%s' "$p"
}

# --- JSON helpers --------------------------------------------------------------

json_get() {
    # json_get <json> <jq_filter> -> value, or empty string on missing/null.
    local json="$1" filter="$2"
    printf '%s' "$json" | jq -r "${filter} // empty" 2>/dev/null
}

session_id_of() {
    # session_id_of <json> -> session id, agent-aware (Cursor calls it
    # conversation_id; Claude/Codex call it session_id).
    local json="$1"
    case "$AGENT" in
        cursor) json_get "$json" '.conversation_id // .session_id' ;;
        *)      json_get "$json" '.session_id' ;;
    esac
}

hook_cwd() {
    # hook_cwd <json> -> the working directory the hook fired in.
    local json="$1" cwd
    cwd="$(json_get "$json" '.cwd // .workspace_roots[0]')"
    [ -z "$cwd" ] && cwd="$(pwd)"
    printf '%s' "$cwd"
}

stop_hook_active_of() {
    # stop_hook_active_of <json> -> "true" when the Stop input says the agent
    # is already continuing because an earlier Stop hook blocked in this same
    # turn (Codex sends it; Claude too). Empty otherwise — jq's `// empty`
    # maps both a missing field and `false` to nothing.
    json_get "$1" '.stop_hook_active'
}

session_source_of() {
    # session_source_of <json> -> "startup", "resume", etc. Cursor's payload
    # has no such field, so it always reads as "startup".
    local json="$1" src
    src="$(json_get "$json" '.source')"
    [ -z "$src" ] && src="startup"
    printf '%s' "$src"
}

touched_files_of() {
    # touched_files_of <json> -> one absolute path per line, agent-aware.
    #   claude: tool_input.file_path / .notebook_path
    #   cursor: .file_path
    #   codex:  only for the apply_patch tool — parse "*** Add/Update/Delete
    #           File:" and "*** Move to:" lines out of the patch text;
    #           relative paths get hook_cwd prefixed. Any other codex tool
    #           (Bash, MCP, ...) prints nothing.
    local json="$1" cwd tool patch
    case "$AGENT" in
        cursor)
            json_get "$json" '.file_path'
            ;;
        codex)
            tool="$(json_get "$json" '.tool_name')"
            [ "$tool" = "apply_patch" ] || return 0
            patch="$(json_get "$json" '.tool_input.command // .tool_input.input // .tool_input.patch')"
            [ -z "$patch" ] && return 0
            cwd="$(hook_cwd "$json")"
            printf '%s\n' "$patch" | while IFS= read -r line; do
                p=""
                case "$line" in
                    '*** Add File: '*)    p="${line#'*** Add File: '}" ;;
                    '*** Update File: '*) p="${line#'*** Update File: '}" ;;
                    '*** Delete File: '*) p="${line#'*** Delete File: '}" ;;
                    '*** Move to: '*)     p="${line#'*** Move to: '}" ;;
                esac
                [ -z "$p" ] && continue
                case "$p" in
                    /*) printf '%s\n' "$p" ;;
                    *)  printf '%s\n' "$cwd/$p" ;;
                esac
            done
            ;;
        *)
            json_get "$json" '.tool_input.file_path // .tool_input.notebook_path'
            ;;
    esac
}

# --- repo / switch helpers ----------------------------------------------------

repo_of() {
    # repo_of <dir> -> normalised git toplevel path, or non-zero if not a repo.
    local dir="$1" repo
    repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ -z "$repo" ] && return 1
    norm_path "$repo"
}

marker_path() {
    # marker_path <repo> -> absolute path to the per-clone override marker,
    # shared across worktrees (git-common-dir, not git-dir).
    local repo="$1" gcd
    gcd="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 1
    [ -z "$gcd" ] && return 1
    case "$gcd" in
        /*) : ;;
        *) gcd="$repo/$gcd" ;;
    esac
    norm_path "$gcd/info/bakery-sync"
}

_bakery_sync_instructions_enabled() {
    local repo="$1"
    grep -q "Bakery Wiki sync" "$repo/CLAUDE.md" 2>/dev/null && return 0
    grep -q "Bakery Wiki sync" "$repo/AGENTS.md" 2>/dev/null && return 0
    return 1
}

enabled_state() {
    # enabled_state <repo> -> "on|off <source>" on stdout, source one of
    # marker|instructions|none. The per-clone marker wins over the
    # instruction-file switch.
    local repo="$1" mp val
    mp="$(marker_path "$repo" 2>/dev/null || true)"
    if [ -n "$mp" ] && [ -f "$mp" ]; then
        val="$(tr -d '[:space:]' < "$mp" 2>/dev/null)"
        case "$val" in
            on)  printf 'on marker\n';  return 0 ;;
            off) printf 'off marker\n'; return 0 ;;
        esac
    fi
    if _bakery_sync_instructions_enabled "$repo"; then
        printf 'on instructions\n'
    else
        printf 'off none\n'
    fi
}

is_enabled() {
    # is_enabled <repo> -> exit 0/1
    local repo="$1" state
    state="$(enabled_state "$repo")"
    [ "${state%% *}" = "on" ]
}

is_org_repo() {
    # is_org_repo <repo> -> exit 0/1, true if origin matches $ORG_RE.
    local repo="$1" url
    url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
    [ -z "$url" ] && return 1
    printf '%s' "$url" | grep -Eq "$ORG_RE"
}

# --- agent output helpers -----------------------------------------------------

emit_context() {
    # emit_context <text> -> prints agent-appropriate stdout for a
    # non-blocking SessionStart context injection. Caller exits 0 afterwards.
    local text="$1"
    case "$AGENT" in
        cursor) jq -n --arg t "$text" '{additional_context: $t}' ;;
        *)      printf '%s\n' "$text" ;;
    esac
}

emit_rewake() {
    # emit_rewake <text> -> agent-appropriate rewake, and exits itself
    # (exit code differs by agent: Claude uses exit 2 + stdout text; Codex
    # and Cursor use exit 0 + a JSON body).
    local text="$1"
    case "$AGENT" in
        codex)
            jq -n --arg t "$text" '{decision: "block", reason: $t}'
            exit 0
            ;;
        cursor)
            jq -n --arg t "$text" '{followup_message: $t}'
            exit 0
            ;;
        *)
            printf '%s\n' "$text"
            exit 2
            ;;
    esac
}

# --- install drift --------------------------------------------------------------

stale_hook_scripts() {
    # stale_hook_scripts <installed_dir> <source_dir> -> basenames, one per
    # line, of the scripts the source dir ships whose installed copy differs
    # or is missing. "Shipped" = every *.sh in <source_dir> except install.sh
    # itself — the same set install.sh's LIB_AND_SCRIPTS copies
    # (install.test.sh fails if the two ever diverge). Prints nothing when
    # <source_dir> doesn't exist.
    local inst="$1" src="$2" f name
    [ -d "$src" ] || return 0
    for f in "$src"/*.sh; do
        [ -f "$f" ] || continue
        name="${f##*/}"
        [ "$name" = "install.sh" ] && continue
        cmp -s "$f" "$inst/$name" || printf '%s\n' "$name"
    done
}

_physical_dir() {
    # _physical_dir <dir> -> symlink-resolved absolute path, non-zero if the
    # dir doesn't exist. (macOS tmp dirs live behind /var -> /private/var.)
    ( cd "$1" 2>/dev/null && pwd -P )
}

self_update_hooks() {
    # self_update_hooks -> copies stale scripts from the wiki clone into the
    # RUNNING hooks dir (LIB_DIR) and prints a one-line note on stdout when it
    # did. Silent no-op otherwise. Needs LIB_DIR set by the calling script.
    #
    # Why: fixes in tools/bakery-sync/ did nothing until every user re-ran
    # install.sh by hand — on the owner's machine the hooks sat 5 weeks behind
    # the repo, and the stale-install hint (added later) could not fire from
    # an install that predates it. Only SCRIPT CONTENT is refreshed here;
    # agent registrations (hooks.json / settings.json) still need install.sh,
    # and this function never runs it.
    #
    # Safety — ALL must hold, else we do nothing (the caller then falls back
    # to the warn_stale_install hint):
    #   * a wiki clone with tools/bakery-sync/install.sh is configured;
    #   * the running scripts live in exactly $BAKERY_SYNC_HOME/hooks — never
    #     overwrite a repo checkout or a tests dir the scripts are run from;
    #   * the clone's tools/bakery-sync equals origin/dev (tracked files
    #     identical to the origin/dev commit, no untracked files): only code
    #     that already sits on the shared branch gets installed, never local
    #     WIP or an unpushed commit. No fetch here — keep SessionStart fast
    #     (Codex gives it 5 s); the bakery-sync flow pulls the clone anyway.
    [ -n "${WIKI_DIR:-}" ] && [ -n "${LIB_DIR:-}" ] || return 0
    local src="$WIKI_DIR/tools/bakery-sync" stale name tmp updated="" phys_lib phys_home
    [ -f "$src/install.sh" ] || return 0

    phys_lib=$(_physical_dir "$LIB_DIR") || return 0
    phys_home=$(_physical_dir "$BAKERY_SYNC_HOME/hooks") || return 0
    [ "$phys_lib" = "$phys_home" ] || return 0

    stale=$(stale_hook_scripts "$LIB_DIR" "$src")
    [ -n "$stale" ] || return 0

    git -C "$WIKI_DIR" diff --quiet origin/dev -- tools/bakery-sync >/dev/null 2>&1 || return 0
    [ -z "$(git -C "$WIKI_DIR" ls-files --others --exclude-standard -- tools/bakery-sync 2>/dev/null)" ] || return 0

    for name in $stale; do
        # temp file in the same dir -> mv is an atomic rename; a hook firing
        # concurrently sees either the old or the new script, never half.
        tmp=$(mktemp "$LIB_DIR/.$name.upd.XXXXXX" 2>/dev/null) || continue
        if cp "$src/$name" "$tmp" 2>/dev/null && chmod 0755 "$tmp" && mv "$tmp" "$LIB_DIR/$name"; then
            updated="$updated $name"
        else
            rm -f "$tmp"
        fi
    done
    [ -n "$updated" ] || return 0
    printf '[bakery-sync] Hooky automaticky aktualizovány z %s:%s — informativní, nic dělat nemusíš.\n' "$src" "$updated"
}

# --- misc ----------------------------------------------------------------------

sed_inplace() {
    # sed_inplace <sed_expr> <file> — BSD-sed-safe in-place edit via a temp
    # file + mv. Never use `sed -i` directly: BSD sed requires a (possibly
    # empty) backup-suffix argument that GNU sed parses differently, so a
    # script portable to both must avoid the flag entirely.
    local expr="$1" file="$2" tmp
    tmp="$(mktemp "${file}.tmp.XXXXXX")"
    sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}
