#!/usr/bin/env bash
# Acknowledge that the current source state does NOT need a wiki sync
# (chore-only / no-behavior change). Silences the bakery-sync Stop hook for THIS
# exact state; a new source change produces a new signature and re-triggers it.
#
# Usage: bakery-sync-ack.sh <session_id>
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

sid="${1:-}"
[ -z "$sid" ] && { echo "usage: bakery-sync-ack.sh <session_id>" >&2; exit 1; }

pending="$STATE_DIR/$sid.pending"
[ -f "$pending" ] || { echo "no pending bakery-sync state for session $sid (hook hasn't fired yet)" >&2; exit 1; }

cp "$pending" "$STATE_DIR/$sid.ack"
echo "bakery-sync acknowledged for session $sid — chore-only, no wiki update needed"
