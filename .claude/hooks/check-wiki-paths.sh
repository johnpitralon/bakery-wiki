#!/usr/bin/env bash
# PostToolUse guard: block hardcoded paths in wiki/*.md

input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -z "$f" ] && exit 0

case "$f" in
  */wiki/*.md) ;;
  *) exit 0 ;;
esac

[ -f "$f" ] || exit 0

hits=$(grep -nE '(/Users/|/home/|C:\\Users|workspace_kytary)' "$f" 2>/dev/null || true)
[ -z "$hits" ] && exit 0

reason="Hardcoded machine-specific path(s) in $(basename "$f"). Use <workspace>/<repo-name> instead. Offending lines:
$hits"

jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
