#!/usr/bin/env bash
# Declare that THIS session handed the wiki write to a background subagent.
# Agent-neutral, like bakery-sync-ack.sh — run it right after spawning the
# subagent, then end the turn.
#
# Why: Codex's Stop hook is synchronous, so a "wiki not synced yet" block makes
# the user wait while the model writes the wiki inline, and the model's own
# turn has nothing to do while a subagent works — the hook would nag again on
# every Stop. This records "delegated at <ts>, for this footprint version";
# bakery-sync-stop.sh then stays silent for BAKERY_SYNC_DELEGATE_WINDOW seconds
# (default 1800) as long as the session makes no NEW source edit. Self-healing:
# a new source edit changes the footprint, and a dead subagent just lets the
# window run out — either way the reminder comes back (unlike bakery-sync-ack.sh
# this is a promise to do the work, not a claim that none is needed).
# Completion (stage empty) removes the file again.
#
# Usage: bakery-sync-delegated.sh <session_id>
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

sid="${1:-}"
[ -z "$sid" ] && { echo "usage: bakery-sync-delegated.sh <session_id>" >&2; exit 1; }

touched="$STATE_DIR/$sid.touched"
[ -f "$touched" ] || { echo "no tracked source edits for session $sid — nothing to delegate" >&2; exit 1; }

printf '%s %s\n' "$(footprint_of "$touched")" "$(date +%s)" > "$STATE_DIR/$sid.delegated"
echo "bakery-sync: wiki write delegated for session $sid — reminders paused for ${DELEGATE_WINDOW}s (until a new source edit)"
