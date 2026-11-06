#!/usr/bin/env bash
# PostToolUse hook: record the source/wiki files THIS session edits, so the
# bakery-sync Stop hook can attribute changes by real footprint instead of a
# naive start_head..HEAD diff (which mis-attributes parallel/other-session
# commits on a shared branch). Agent-neutral (Claude Code / Codex CLI /
# Cursor — see lib.sh, touched_files_of()). Never blocks — always exit 0.
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

parse_agent "$@"

input=$(cat)
sid="$(session_id_of "$input")"
[ -z "$sid" ] && exit 0

state_file="$STATE_DIR/$sid"
[ -f "$state_file" ] || exit 0

IFS=$'\t' read -r repo _rest < "$state_file"
[ -z "${repo:-}" ] && exit 0
repo="$(norm_path "$repo")"

wiki_dir=""
[ -n "$WIKI_DIR" ] && wiki_dir="$(norm_path "$WIKI_DIR")"

# Only record files inside the session's wiki-rule repo, as repo-relative
# paths (matches `git diff --name-only` output used by the Stop hook), and
# separately files inside the wiki repo (wiki-relative), for per-session
# attribution on the wiki side.
touched_files_of "$input" | while IFS= read -r file; do
    [ -z "$file" ] && continue
    file="$(norm_path "$file")"
    case "$file" in
        "$repo"/*)
            printf '%s\n' "${file#"$repo"/}" >> "$state_file.touched"
            ;;
    esac
    if [ -n "$wiki_dir" ]; then
        case "$file" in
            "$wiki_dir"/*)
                printf '%s\n' "${file#"$wiki_dir"/}" >> "$state_file.wikitouched"
                ;;
        esac
    fi
done

exit 0
