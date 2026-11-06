#!/usr/bin/env bash
# bakery-sync-optin.sh — per-clone override for whether bakery-sync fires in this
# repo. Writes/reads a marker file at <git-common-dir>/info/bakery-sync (shared
# across worktrees, never committed — it lives inside .git). The marker wins
# over the team-level "Bakery Wiki sync" instruction-file switch (CLAUDE.md or
# AGENTS.md) — see lib.sh enabled_state()/is_enabled().
#
# Usage:
#   bakery-sync-optin.sh on|off|status [--repo <dir>]
#
# Default repo is the current directory's git toplevel.
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

usage() {
    echo "usage: bakery-sync-optin.sh on|off|status [--repo <dir>]" >&2
}

cmd="${1:-}"
case "$cmd" in
    on|off|status) ;;
    *) usage; exit 1 ;;
esac
shift || true

repo_arg="."
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            shift
            repo_arg="${1:-}"
            ;;
        --repo=*)
            repo_arg="${1#--repo=}"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

repo="$(repo_of "$repo_arg" 2>/dev/null)" || { echo "bakery-sync-optin: not a git repository: $repo_arg" >&2; exit 1; }

case "$cmd" in
    status)
        enabled_state "$repo"
        exit 0
        ;;
    on|off)
        mp="$(marker_path "$repo")" || { echo "bakery-sync-optin: cannot resolve marker path for $repo" >&2; exit 1; }
        mkdir -p "$(dirname "$mp")"
        printf '%s\n' "$cmd" > "$mp"
        enabled_state "$repo"
        exit 0
        ;;
esac
