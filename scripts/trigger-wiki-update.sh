#!/usr/bin/env bash
# Univerzální trigger wiki update — IDE agenty i lokální LLM (Ollama, LM Studio, …)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-update}"
VALID="update ingest lint"
if ! echo "$VALID" | grep -qw "$MODE"; then
  echo "Usage: $0 [update|ingest|lint]" >&2
  exit 1
fi

CONTEXT="$("$ROOT/scripts/collect-context.sh")"
BUNDLE="$("$ROOT/scripts/build-prompt-bundle.sh" "$MODE")"
DATE="$(date +%Y-%m-%d)"
REQUEST="$ROOT/.wiki-update-request"

cat > "$REQUEST" <<EOF
# Wiki update request
mode: ${MODE}
created: ${DATE}
context_raw: ${CONTEXT#"$ROOT/"}
prompt_bundle: ${BUNDLE#"$ROOT/"}
prompt: WIKI_UPDATE.md
schema: CLAUDE.md
agents: AGENTS.md

LLM: proveď režim "${MODE}", pak smaž tento soubor.
EOF

echo "✓ Trigger: .wiki-update-request (mode=${MODE})"
echo "✓ Kontext: ${CONTEXT#"$ROOT/"}"
echo "✓ Prompt bundle: ${BUNDLE#"$ROOT/"}"
echo
echo "─── Lokální LLM (Ollama / LM Studio / LiteLLM) ───"
echo "  cp triggers/local-models.env.example triggers/local-models.env  # jednou"
echo "  ./scripts/run-wiki-update-local.sh ${MODE}"
echo "  ./scripts/apply-wiki-response.sh"
echo
echo "─── Ručně (Open WebUI chat, jakýkoli UI) ───"
echo "  Vlož obsah: ${BUNDLE#"$ROOT/"}"
echo "  Pak: ./scripts/apply-wiki-response.sh <uložená-odpověď.md>"
echo
echo "─── IDE agent (Cursor / Claude / Codex) ───"
echo "  Proveď wiki ${MODE} podle WIKI_UPDATE.md a .wiki-update-request"
echo "  nebo: /wiki-update"
