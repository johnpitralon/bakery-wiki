#!/usr/bin/env bash
# Commit + push wiki změn po update (agent nebo apply-wiki-response).
# Usage: ./scripts/wiki-commit-push.sh [commit message]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${WIKI_AUTO_COMMIT:-true}" != "true" ]]; then
  echo "WIKI_AUTO_COMMIT=false — přeskakuji commit"
  exit 0
fi

if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  :
else
  echo "✓ Žádné změny k commitu"
  exit 0
fi

MSG="${1:-}"
if [[ -z "$MSG" ]]; then
  MODE="${WIKI_UPDATE_MODE:-update}"
  MSG="wiki: auto-${MODE} $(date +%Y-%m-%d)"
fi

# Necommitovat trigger artefakty (gitignore) — git add -A respektuje .gitignore
git add -A

if git diff --cached --quiet; then
  echo "✓ Nic ke commitu po staging"
  exit 0
fi

git commit -m "$MSG"

if [[ "${WIKI_AUTO_PUSH:-true}" != "true" ]]; then
  echo "✓ Commit vytvořen (WIKI_AUTO_PUSH=false)"
  exit 0
fi

branch="$(git branch --show-current)"
if git push -u origin "$branch" 2>&1; then
  echo "✓ Pushed origin/$branch"
else
  echo "WARN: push selhal — commit zůstal lokálně. Zkus: gh auth switch + git push" >&2
  exit 1
fi
