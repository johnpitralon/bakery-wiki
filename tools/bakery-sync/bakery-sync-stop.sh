#!/usr/bin/env bash
# Stop hook: if the session produced source changes in a repo that has
# bakery-sync enabled (marker or "Bakery Wiki sync" instruction switch), and the
# wiki wasn't touched yet, rewake the agent to update the wiki and
# commit+push it. Agent-neutral (Claude Code / Codex CLI / Cursor).
#
# Exit codes:
#   0  — nothing to do (silent allow stop)
#   claude — exit 2 + stdout = rewake message (asyncRewake)
#   codex  — exit 0 + stdout = {"decision":"block","reason":<message>}
#   cursor — exit 0 + stdout = {"followup_message":<message>}
# (see lib.sh emit_rewake — the agent-specific mapping lives there)
#
# 2026-09-05 fix — rewake storm while a delegated subagent writes the wiki.
# When a coordinator delegates the actual wiki edit to a subagent (reading
# 50-80KB pages, editing for 5-15 minutes), the coordinator's own turn ends
# with nothing left to do, hits this Stop hook, gets exit 2 ("wiki not
# synced yet"), says "waiting", and stops again — every few seconds, for
# the whole duration of the subagent's write. One incident produced 30+
# rewakes in a single delegated wiki write before the subagent committed.
# The hook had no notion of "work is in flight" and no cooldown between
# rewakes, so it fired as fast as Stop hooks could run. Fixed with two
# self-healing guards (no manual in-progress marker — a stuck/crashed
# subagent must self-recover without operator intervention):
#   1. Active-wiki-work window: if "<state>.wikitouched" was appended to
#      (by bakery-sync-touched.sh, which runs for subagent tool calls under
#      the same session_id) within BAKERY_SYNC_ACTIVE_WINDOW seconds, the
#      wiki is being edited right now — stay silent. A stalled subagent's
#      mtime ages out and the reminder returns on its own.
#   2. Rewake cooldown: at most one rewake per (signature, stage) per
#      BAKERY_SYNC_COOLDOWN seconds, tracked in "<state>.lastfire". A new
#      source edit (new signature) or a stage transition bypasses the
#      cooldown immediately — only repeats of the identical state are
#      throttled.
#
# 2026-10-19 — Codex: wiki update off the critical path. Codex's Stop hook is
# synchronous and {"decision":"block"} continues THE SAME turn, so the user
# waited while the model wrote the wiki inline (Claude feels non-blocking
# because asyncRewake + a background subagent). Three additions:
#   * Codex stop_hook_active == true -> exit 0 at once: the model is already
#     continuing because of a block in this turn; never chain blocks.
#   * Delegation guard: bakery-sync-delegated.sh <sid> records that the wiki
#     write went to a background subagent; while that footprint is unchanged
#     and younger than BAKERY_SYNC_DELEGATE_WINDOW (default 1800 s) the hook is
#     silent, so the parent turn can end immediately. A new source edit or an
#     expired window brings the reminder back (a dead subagent can't lose the
#     sync silently).
#   * Codex gets a dedicated update message: spawn_agent, delegated.sh, end
#     the turn — no wait_agent / polling.
# Both guards sit strictly AFTER the "stage is empty -> done" idempotency
# check (2026-09-03 fix) so genuine completion is still reported instantly,
# and strictly BEFORE the ack check so an acknowledged state still exits 0
# regardless.

set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$LIB_DIR/lib.sh"

parse_agent "$@"

input=$(cat)
session_id=$(session_id_of "$input")
[ -z "$session_id" ] && exit 0

# Codex: already continuing after a block in this very turn -> never chain
# another one (2026-10-19, see header).
if [ "$AGENT" = "codex" ] && [ -n "$(stop_hook_active_of "$input")" ]; then
    exit 0
fi

state_file="$STATE_DIR/$session_id"
[ -f "$state_file" ] || exit 0

IFS=$'\t' read -r repo start_head start_ts < "$state_file"
[ -z "${repo:-}" ] && exit 0
[ -e "$repo/.git" ] || exit 0   # -e, not -d: in a git worktree .git is a file

# Only act for repos that currently have bakery-sync enabled (marker or the
# "Bakery Wiki sync" instruction-file switch — see lib.sh is_enabled/enabled_state).
is_enabled "$repo" || exit 0

# --- did THIS session change source? (tool-edit footprint) -----------------
# We do NOT trust `start_head..HEAD`: on a shared branch/clone the HEAD advances
# with parallel/other-session commits, mis-attributing foreign work and looping
# forever. We also do NOT track git commits: in a shared clone a commit's HEAD
# cannot be reliably tied to this session, and command-text matching is fragile.
#
# The only reliable per-session signal is the tool-edit footprint: files this
# session edited via Write/Edit/NotebookEdit, recorded by bakery-sync-touched.sh
# into "<state_file>.touched" (repo-relative paths). Foreign work never appears
# there. Committing a tool-edited file keeps it in .touched, so commit tracking
# would add nothing for detection anyway.
#
# Draft design specs/plans under docs/superpowers/{specs,plans}/ are brainstorm
# artifacts, not behavior/architecture changes — ignored; anything else counts
# (SPEC_PATH_RE lives in lib.sh, next to footprint_of).

touched_file="$state_file.touched"

# Files this session edited via tools, outside the draft-spec path.
session_touched=""
[ -f "$touched_file" ] && session_touched=$(sort -u "$touched_file" | grep -vE "$SPEC_PATH_RE" | grep -vE '^[[:space:]]*$' || true)

[ -z "$session_touched" ] && exit 0

# Footprint version (lib.sh footprint_of): hash of the RAW non-draft
# footprint. Every new source edit changes it; draft-spec edits don't. Unlike
# `sig` below (sort -u, used for cooldown/ack) it cannot miss a re-edit.
# bakery-sync-delegated.sh computes it with the same helper.
footprint=$(footprint_of "$touched_file")

# --- did wiki get touched this session? ------------------------------------
[ -n "$WIKI_DIR" ] || exit 0        # no wiki dir configured → silent
[ -d "$WIKI_DIR/.git" ] || exit 0   # wiki repo not present locally → silent

wiki_porcelain=$(git -C "$WIKI_DIR" status --porcelain 2>/dev/null || echo "")
wiki_ahead=$(git -C "$WIKI_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "0")

# Per-session attribution on the WIKI side (2026-09-01 fix). The wiki repo is
# shared by parallel sessions, so repo-wide porcelain must NOT be read as
# "this session has unfinished wiki work": before this fix, foreign
# uncommitted files flipped every stopping session into the "commit" stage
# and the message advised `git add -A` — i.e. adopt someone else's mid-flight
# work (two false alarms + one near-miss on 2026-09-01, sessions Onboarding ×
# servisni-portal). Attribution signal: ".wikitouched" (wiki files edited by
# THIS session via Write/Edit, recorded by bakery-sync-touched.sh). Foreign
# porcelain is ignored for staging; it no longer counts as "wiki updated"
# either — someone else's dirty files never satisfied this session's duty.
my_wiki_dirty=""
if [ -n "$wiki_porcelain" ] && [ -f "$state_file.wikitouched" ]; then
    porcelain_paths=$(printf '%s\n' "$wiki_porcelain" | sed 's/^...//' | sed 's/^"//;s/"$//')
    my_wiki_dirty=$(sort -u "$state_file.wikitouched" | grep -Fx -f /dev/stdin <(printf '%s\n' "$porcelain_paths") 2>/dev/null || true)
fi

# "Wiki touched" is judged against the LAST source edit of this session, not
# the session start (2026-09-25 fix). Before, any wiki commit newer than
# start_ts satisfied it — one wiki update early in a long session silenced
# every later source change, and so did any teammate's commit pulled into the
# shared clone (dozens a day). akordy-kytary-php 23. 9.: rewake at 15:51, wiki
# written 15:53, two more feature commits the same evening never reached the
# wiki. Now it counts only when, after the last source edit (mtime of
# .touched — appended on every edit), this session left dirty wiki files, or
# edited the wiki via tools (.wikitouched), or the local git user committed
# to the wiki (covers wiki edits made through a shell, which PostToolUse does
# not see). Commits by other authors never count.
src_ts=$(file_mtime "$touched_file")
wiki_email=$(git -C "$WIKI_DIR" config user.email 2>/dev/null || echo "")
own_wiki_commit=0
if [ -n "$wiki_email" ]; then
    own_wiki_commit=$(git -C "$WIKI_DIR" log --since="@$src_ts" --format='%ct %ae' 2>/dev/null \
        | awk -v t="$src_ts" -v e="$wiki_email" '$1 > t && tolower($2) == tolower(e) { n++ } END { print (n ? 1 : 0) }')
fi
wiki_touched=0
if [ -n "$my_wiki_dirty" ]; then wiki_touched=1; fi
if [ -f "$state_file.wikitouched" ] && [ "$(file_mtime "$state_file.wikitouched")" -ge "$src_ts" ]; then wiki_touched=1; fi
if [ "${own_wiki_commit:-0}" -eq 1 ]; then wiki_touched=1; fi

# A footprint this session already brought to "done" stays done (2026-10-02
# fix). Completion clears .wikitouched (2026-09-03), so afterwards "wiki
# touched" rested on a single re-derivable signal — on 2. 10. the installed
# Stop hook compared the last wiki commit with start_ts, which a /compact
# had just moved forward (see bakery-sync-session-start.sh), and a session
# whose wiki was committed and pushed at 10:07 was told at 10:08 to update
# it. own_wiki_commit has the same blind spots (commit from another clone or
# a worktree branch not in the wiki clone's HEAD, different user.email).
# ".synced" holds the footprint version recorded at completion; until a new
# source edit changes it, the update stage cannot come back. Commit/push are
# still judged below, so new wiki edits of this session are not skipped.
if [ -f "$state_file.synced" ] && [ "$(cat "$state_file.synced" 2>/dev/null)" = "$footprint" ]; then
    wiki_touched=1
fi

# Three stages: missing update, missing commit, missing push.
stage=""
if [ "$wiki_touched" -eq 0 ]; then
    stage="update"
elif [ -n "$my_wiki_dirty" ]; then
    stage="commit"
elif [ "${wiki_ahead:-0}" -gt 0 ]; then
    stage="push"
fi

# Idempotency: if Claude already did everything, allow stop.
# Nase wiki prace je hotova a pushnuta -> vycistit otisk (2026-09-03 fix).
# Bez tohohle je ".wikitouched" KUMULATIVNI: soubor, ktery jsme kdy editovali,
# nam zustane pripsany navzdy, takze kdyz ho pozdeji upravi JINA session, hook
# reknem "tvoje" a poradi ho commitnout — tedy privlastnit si cizi rozpracovanou
# praci. Presne to se stalo 2026-09-03 se stránkou "ArgoCD AppSet feature-env"
# a "index.md" (upravovala je servisni-portal session). Je to inverze te puvodni
# chyby, kterou tenhle hook rano opravoval: ne cizi spina blokujici vsechny, ale
# cizi spina pripsana konkretne nam. Otisk proto zahazujeme v okamziku, kdy uz
# neni co dokoncovat; nova skutecna editace si ho zalozi znovu.
if [ -z "$stage" ]; then
    rm -f "$state_file.wikitouched" "$state_file.delegated"
    printf '%s' "$footprint" > "$state_file.synced"
    exit 0
fi

# --- guard 0: wiki write delegated to a background subagent (2026-10-19) ----
# bakery-sync-delegated.sh <sid> wrote "<footprint> <ts>" when the session
# handed the wiki to a subagent. Silent while the footprint is unchanged (no
# new source edit) and the declaration is younger than DELEGATE_WINDOW.
# Self-healing: a new edit changes the footprint, an expired window (dead or
# stalled subagent) lets the reminder return. Completion (above) removes it.
delegated_file="$state_file.delegated"
if [ -f "$delegated_file" ]; then
    read -r dg_fp dg_ts < "$delegated_file" 2>/dev/null || true
    case "${dg_ts:-}" in
        '' | *[!0-9]*) ;;   # unreadable declaration -> ignore it
        *)
            if [ "${dg_fp:-}" = "$footprint" ] && [ $(( $(date +%s) - dg_ts )) -lt "$DELEGATE_WINDOW" ]; then
                exit 0
            fi
            ;;
    esac
fi

# --- guard 1: active wiki work in flight (2026-09-05 fix) ------------------
# ".wikitouched" is appended to (>>) by bakery-sync-touched.sh on every
# Write/Edit/NotebookEdit against the wiki repo under this session_id —
# including calls made by a delegated subagent, since it inherits the same
# session_id. A recent mtime means the wiki is being edited RIGHT NOW, so a
# rewake telling Claude to "finish the sync" would just interrupt in-flight
# work and restart the loop. Self-healing: if the writer stalls or crashes,
# the file stops getting new appends, its mtime ages past the window, and
# the reminder comes back on its own — no manual marker to forget to clear.
if [ -f "$state_file.wikitouched" ]; then
    wikitouched_mtime=$(file_mtime "$state_file.wikitouched")
    now_ts=$(date +%s)
    if [ $(( now_ts - wikitouched_mtime )) -lt "$ACTIVE_WINDOW" ]; then
        exit 0
    fi
fi

# --- guard 2: rewake cooldown (2026-09-05 fix) ------------------------------
# Throttle repeats of the IDENTICAL (signature, stage) state to at most one
# rewake per COOLDOWN seconds. A new source edit (new signature, computed
# below) or a stage transition (update -> commit -> push) is a real state
# change and bypasses the cooldown immediately — this only silences the
# hook re-firing on an unchanged state across rapid Stop calls.
#
# Signature = hash of the session's tool-edit footprint (also reused below
# for the ack check), so a genuinely NEW edit by this session produces a new
# signature and bypasses both the cooldown and any prior ack — but foreign
# work never moves it.
sig=$(bakery_sync_hash "$session_touched")
lastfire_file="$state_file.lastfire"
if [ -f "$lastfire_file" ]; then
    read -r lf_sig lf_stage lf_ts < "$lastfire_file" 2>/dev/null || true
    if [ "${lf_sig:-}" = "$sig" ] && [ "${lf_stage:-}" = "$stage" ]; then
        now_ts=${now_ts:-$(date +%s)}
        if [ $(( now_ts - ${lf_ts:-0} )) -lt "$COOLDOWN" ]; then
            exit 0
        fi
    fi
fi
printf '%s %s %s\n' "$sig" "$stage" "$(date +%s)" > "$lastfire_file"

# --- acknowledgement: chore-only states can be silenced --------------------
# The escape hatch in the message ("if wiki not needed, ack it") must be REAL:
# without a marker this hook re-fires on every Stop forever (asyncRewake loop).
ack_file="$state_file.ack"
if [ -f "$ack_file" ] && [ "$(cat "$ack_file" 2>/dev/null)" = "$sig" ]; then
    exit 0   # this exact state was already acknowledged as not-needing-wiki
fi
printf '%s' "$sig" > "$state_file.pending"

repo_name=$(basename "$repo")

msg=""
case "$stage" in
    update)
        if [ "$AGENT" = "codex" ]; then
            msg=$(cat <<EOF
Session ve **$repo_name** editovala tyto soubory, ale bakery-wiki ještě nebyla aktualizovaná:
$session_touched

Per ~/.codex/AGENTS.md (sekce "Wiki updates") NEPIŠ wiki v hlavním vlákně — uživatel by na to čekal. Udělej přesně tohle:
  1. spawn_agent (model gpt-5.6-terra, reasoning_effort high, bez forku turnů) s KOMPLETNÍM samostatným zadáním: seznam editovaných souborů výše, co se změnilo a proč, cesta k wiki $WIKI_DIR, "postupuj podle schématu v $WIKI_DIR/CLAUDE.md" (včetně entry na KONEC wiki/log.md a řádku do wiki/index.md u nové stránky), commit rovnou do dev (git pull --rebase origin dev; git add jen soubory, které subagent editoval — explicitní cesty, NIKDY -A) a git push origin dev.
  2. Hned potom spusť:
       $(user_cmd "$BAKERY_SYNC_HOME/hooks/bakery-sync-delegated.sh" "$session_id")
     (hook pak ${DELEGATE_WINDOW} s mlčí, dokud neuděláš novou source editaci).
  3. Ukonči tah HNED. NEvolej wait_agent, nespi a nepolluj — subagent poběží dál na pozadí.

Pokud po review usoudíš, že změna wiki **nepotřebuje** (chore-only / no-behavior change), místo toho spusť:
  $(user_cmd "$BAKERY_SYNC_HOME/hooks/bakery-sync-ack.sh" "$session_id")
EOF
)
        else
            msg=$(cat <<EOF
Session ve **$repo_name** editovala tyto soubory, ale bakery-wiki ještě nebyla aktualizovaná:
$session_touched

Per CLAUDE.md "Bakery Wiki sync" blocking rule projdi tyhle změny a updatuj relevantní stránky v $WIKI_DIR/wiki/ podle schématu v $WIKI_DIR/CLAUDE.md. Vždy připoj entry na KONEC wiki/log.md (jeden append-only log) a (pokud vytváříš novou stránku) i do wiki/index.md.

Po dokončení edits commitni a pushni:
  cd $WIKI_DIR
  git fetch origin
  git pull --rebase origin dev
  git add <JEN soubory, které jsi editoval TY — explicitní cesty; NIKDY -A:
           wiki sdílí paralelní sessions a -A by přivlastnilo cizí
           rozpracovanou práci>
  git commit -m "docs(wiki): <stručný popis>"
  git push origin dev

Pokud po review usoudíš, že změna wiki **nepotřebuje** (chore-only / no-behavior change), potvrď to spuštěním:
  $(user_cmd "$BAKERY_SYNC_HOME/hooks/bakery-sync-ack.sh" "$session_id")
Tím tento stav umlčíš (nová source změna hook znovu spustí).

Pokud wiki píšeš delegovaným subagentem, po jeho spuštění zavolej:
  $(user_cmd "$BAKERY_SYNC_HOME/hooks/bakery-sync-delegated.sh" "$session_id")
hook pak ${DELEGATE_WINDOW} s mlčí (nová source editace ho vrátí).

Pokud wiki právě píše delegovaný subagent, nic nedělej — tahle připomínka se během aktivní editace sama odmlčí a vrátí se nejdřív za ${COOLDOWN} s.
EOF
)
        fi
        ;;
    commit)
        msg=$(cat <<EOF
bakery-wiki má neuncommitted edits TÉTO session:
$my_wiki_dirty

Dokonči sync (add pouze tyto soubory, žádné cizí):
  cd $WIKI_DIR
  git fetch origin
  git pull --rebase origin dev
  git add <JEN soubory, které jsi editoval TY — explicitní cesty; NIKDY -A:
           wiki sdílí paralelní sessions a -A by přivlastnilo cizí
           rozpracovanou práci>
  git commit -m "docs(wiki): <stručný popis>"
  git push origin dev

Pokud wiki právě píše delegovaný subagent, nic nedělej — tahle připomínka se během aktivní editace sama odmlčí a vrátí se nejdřív za ${COOLDOWN} s.
EOF
)
        ;;
    push)
        msg=$(cat <<EOF
bakery-wiki má lokální commits ahead of origin/dev — push chybí:
  cd $WIKI_DIR
  git fetch origin
  git pull --rebase origin dev
  git push origin dev
EOF
)
        ;;
esac

emit_rewake "$msg"
