#!/usr/bin/env bash
# Sestaví self-contained prompt pro lokální LLM (Ollama, LM Studio, OpenWebUI, LiteLLM…)
# Výstup: triggers/out/wiki-update-prompt-<mode>-<timestamp>.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-update}"
DATE="$(date +%Y-%m-%d)"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT/triggers/out"
OUT="$OUT_DIR/wiki-update-prompt-${MODE}-${TS}.md"
LATEST="$OUT_DIR/LATEST-prompt.md"

mkdir -p "$OUT_DIR"

# Context: latest auto-snapshot or collect fresh
CONTEXT_FILE="$(ls -t "$ROOT"/raw/auto-snapshot-*.md 2>/dev/null | head -1 || true)"
if [ -z "$CONTEXT_FILE" ] || [ ! -f "$CONTEXT_FILE" ]; then
  CONTEXT_FILE="$("$ROOT/scripts/collect-context.sh")"
fi

append_file() {
  local label="$1" path="$2"
  [ -f "$path" ] || return 0
  {
    echo
    echo "---"
    echo "## ${label}"
    echo
    echo '```markdown'
    cat "$path"
    echo '```'
  } >> "$OUT"
}

{
  cat <<EOF
# Bakery wiki update — prompt bundle

> Self-contained prompt pro **lokální i cloud LLM** bez přístupu k souborovému systému.
> Režim: **${MODE}** | Datum: ${DATE}

## Tvůj úkol

Aktualizuj bakery-wiki podle schématu níže. Výstup **pouze** ve formátu wiki-file XML tagu (viz sekce Výstup).
Nepiš vysvětlení mimo tagy — jen soubory k uložení.

### Režim ${MODE}

EOF

  case "$MODE" in
    update)
      cat <<'EOF'
- Sync `wiki/` se stavem z kontextu (snapshot) a existujících stránek
- Aktualizuj `wiki/index.md`, append do `wiki/log.md`
- Uprav entity/concept stránky kde je zastaralý stav (✅/🔄/⬜)
EOF
      ;;
    ingest)
      cat <<'EOF'
- Nový obsah v `raw/` → vytvoř `wiki/sources/src-…`
- Propaguj fakta do entity/concept stránek
- Aktualizuj `wiki/index.md`, append do `wiki/log.md`
EOF
      ;;
    lint)
      cat <<'EOF'
- Najdi kontradikce, orphan stránky, zastaralé statusy
- Oprav cross-reference, aktualizuj `updated:` ve frontmatter
- Append lint záznam do `wiki/log.md`
EOF
      ;;
  esac

  cat <<'EOF'

### Pravidla

1. `raw/` neměň
2. V `wiki/*.md` **nikdy** nepoužívej absolutní cesty (/Users/, /home/) — placeholder <workspace>/<repo>
3. Každá stránka: YAML frontmatter (`title`, `type`, `tags`, `created`, `updated`)
4. Prose česky, tech termíny anglicky
5. Preferuj úpravu existujících stránek před novými

### Výstup (povinný formát)

Pro každý změněný soubor jeden blok:

```xml
<wiki-file path="wiki/overview.md">
---
title: ...
---
(celý obsah souboru)
</wiki-file>
```

Vždy zahrň celý obsah souboru (ne diff). Minimálně: každý soubor který měníš + `wiki/index.md` + `wiki/log.md`.

EOF

  append_file "Schéma (CLAUDE.md)" "$ROOT/CLAUDE.md"
  append_file "Kontext (snapshot)" "$CONTEXT_FILE"
  append_file "wiki/index.md" "$ROOT/wiki/index.md"
  append_file "wiki/overview.md" "$ROOT/wiki/overview.md"
  append_file "wiki/log.md" "$ROOT/wiki/log.md"

  for f in "$ROOT"/wiki/entities/*.md "$ROOT"/wiki/concepts/*.md "$ROOT"/wiki/sources/*.md; do
    [ -f "$f" ] || continue
    rel="${f#"$ROOT/"}"
    append_file "$rel" "$f"
  done

} > "$OUT"

cp "$OUT" "$LATEST"
echo "$OUT"
ln -sf "$(basename "$OUT")" "$OUT_DIR/LATEST-prompt-link.md" 2>/dev/null || true
