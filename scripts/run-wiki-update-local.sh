#!/usr/bin/env bash
# Zavolá lokální LLM přes OpenAI-kompatibilní API (Ollama, LM Studio, LiteLLM, OpenWebUI…)
# Výstup: triggers/out/wiki-update-response-<timestamp>.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-update}"

# Volitelná konfigurace: triggers/local-models.env nebo env
ENV_FILE="$ROOT/triggers/local-models.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

BASE_URL="${WIKI_LLM_BASE_URL:-http://127.0.0.1:11434/v1}"
MODEL="${WIKI_LLM_MODEL:-qwen2.5:7b}"
API_KEY="${WIKI_LLM_API_KEY:-ollama}"
TIMEOUT="${WIKI_LLM_TIMEOUT_SEC:-600}"
MAX_TOKENS="${WIKI_LLM_MAX_TOKENS:-16384}"

PROMPT_FILE="${WIKI_PROMPT_BUNDLE:-}"
if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
  PROMPT_FILE="$("$ROOT/scripts/build-prompt-bundle.sh" "$MODE")"
fi

OUT_DIR="$ROOT/triggers/out"
TS="$(date +%Y%m%d-%H%M%S)"
RESPONSE="$OUT_DIR/wiki-update-response-${TS}.md"
LATEST="$OUT_DIR/LATEST-response.md"

mkdir -p "$OUT_DIR"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl required" >&2
  exit 1
fi

# Health check (best effort)
if ! curl -sf --max-time 5 "${BASE_URL%/v1}/v1/models" -H "Authorization: Bearer ${API_KEY}" >/dev/null 2>&1 \
   && ! curl -sf --max-time 5 "${BASE_URL}/models" -H "Authorization: Bearer ${API_KEY}" >/dev/null 2>&1; then
  echo "WARN: LLM endpoint neodpovídá na ${BASE_URL} — pokračuji…" >&2
fi

PAYLOAD="$(python3 - "$PROMPT_FILE" "$MODEL" "$MAX_TOKENS" <<'PY'
import json, sys, pathlib
prompt = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
model, max_tokens = sys.argv[2], int(sys.argv[3])
print(json.dumps({
  "model": model,
  "messages": [
    {"role": "system", "content": "Jsi wiki editor pro Bakery platformu. Odpovídej pouze ve formátu <wiki-file path=\"...\">...</wiki-file>."},
    {"role": "user", "content": prompt},
  ],
  "temperature": 0.2,
  "max_tokens": max_tokens,
  "stream": False,
}))
PY
)"

echo "==> Volám ${BASE_URL} model=${MODEL} …" >&2
HTTP_BODY="$(mktemp)"
HTTP_CODE="$(curl -sS --max-time "$TIMEOUT" \
  -o "$HTTP_BODY" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "$PAYLOAD" \
  "${BASE_URL}/chat/completions")"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "ERROR: API HTTP ${HTTP_CODE}" >&2
  cat "$HTTP_BODY" >&2
  rm -f "$HTTP_BODY"
  exit 1
fi

python3 - "$HTTP_BODY" "$RESPONSE" <<'PY'
import json, sys, pathlib
body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(sys.argv[2])
data = json.loads(body)
content = data["choices"][0]["message"]["content"]
out.write_text(content.strip() + "\n", encoding="utf-8")
PY

rm -f "$HTTP_BODY"
cp "$RESPONSE" "$LATEST"

echo "✓ Response: ${RESPONSE#"$ROOT/"}"
echo "  Další krok: ./scripts/apply-wiki-response.sh"
