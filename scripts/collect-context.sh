#!/usr/bin/env bash
# Sběr kontextu pro wiki update — volá trigger-wiki-update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="${BAKERY_WORKSPACE:-$(dirname "$ROOT")}"
DATE="$(date +%Y-%m-%d)"
TIME="$(date +%H:%M)"
OUT="$ROOT/raw/auto-snapshot-latest.md"

repos=(bakery-platform bakery-gitops bakery-onboarding bakery-wiki fake-buster service-bakery)

{
  echo "# Auto snapshot — ${DATE} ${TIME}"
  echo
  echo "Generováno: \`scripts/collect-context.sh\` (LLM wiki trigger)"
  echo
  echo "## Workspace"
  echo
  echo "- \`BAKERY_WORKSPACE\`: \`${WORKSPACE}\`"
  echo
  echo "## Git stav (sibling repos)"
  echo
  for r in "${repos[@]}"; do
    d="${WORKSPACE}/${r}"
    echo "### ${r}"
    if [ -d "$d/.git" ]; then
      echo "- branch: \`$(git -C "$d" branch --show-current 2>/dev/null || echo '?')\`"
      echo "- last commit: \`$(git -C "$d" log -1 --oneline 2>/dev/null || echo 'n/a')\`"
      unstaged="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      echo "- uncommitted files: ${unstaged}"
    else
      echo "- *(clone nenalezen)*"
    fi
    echo
  done

  if command -v kubectl >/dev/null 2>&1; then
    echo "## Kubernetes (pokud dostupné)"
    echo
    echo "### Argo CD Applications (bakery)"
    echo '```'
    kubectl get application -n argocd 2>/dev/null \
      | grep -E 'bakery|fake-buster|service-buster|service-bakery' || echo "(kubectl nedostupný nebo žádné apps)"
    echo '```'
    echo
    echo "### fake-buster namespace"
    echo '```'
    kubectl get deploy,pods -n fake-buster 2>/dev/null | head -25 || echo "(namespace nedostupný)"
    echo '```'
    echo
    if command -v helm >/dev/null 2>&1; then
      echo "### Helm fake-buster"
      echo '```'
      helm status fake-buster -n bakery-infrastructure 2>/dev/null | head -12 || echo "(release n/a)"
      echo '```'
    fi
  else
    echo "## Kubernetes"
    echo
    echo "*(kubectl není v PATH)*"
  fi
} > "$OUT"

echo "$OUT"
