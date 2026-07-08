#!/usr/bin/env bash
# Wiki update přes Aider + lokální model (Ollama, LM Studio, LiteLLM…)
# Model edituje soubory přímo — žádný XML bundle/apply.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-update}"
ENV_FILE="$ROOT/triggers/local-models.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

MODEL="${AIDER_MODEL:-${WIKI_LLM_MODEL:-ollama/qwen2.5-coder}}"
AIDER="${AIDER_BIN:-aider}"

if ! command -v "$AIDER" >/dev/null 2>&1; then
  echo "ERROR: aider not found. Install: pip install aider-chat" >&2
  echo "Fallback: task wiki:bundle + Open WebUI, nebo task wiki:run-local" >&2
  exit 1
fi

"$ROOT/scripts/trigger-wiki-update.sh" "$MODE" >/dev/null

MSG="Proveď wiki ${MODE} podle AGENTS.md a WIKI_UPDATE.md. Aktualizuj wiki/, index.md, log.md. Žádné absolutní cesty v wiki/*.md."

cd "$ROOT"
exec "$AIDER" \
  --model "$MODEL" \
  --message "$MSG" \
  --file CLAUDE.md \
  --file AGENTS.md \
  --file WIKI_UPDATE.md \
  --file wiki/index.md \
  --file wiki/overview.md \
  --file wiki/log.md \
  --file raw/auto-snapshot-latest.md
