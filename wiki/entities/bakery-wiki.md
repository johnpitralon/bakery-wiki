---
title: bakery-wiki
type: entity
tags: [repo, wiki, obsidian, llm]
created: 2026-07-08
updated: 2026-11-06
---

**Obsidian vault + LLM wiki** pro Bakery platformu — analogie **Kytary.Wiki**. Znalostní graf Platform v2, pilotů a rozhodnutí.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-wiki
- **Default branch**: `dev`
- **Local clone**: `<workspace>/bakery-wiki`

## Struktura

| Path | Kdo edituje |
|------|-------------|
| `raw/` | Lidé (immutable pro LLM) |
| `wiki/` | LLM + review přes PR |
| `triggers/out/` | Prompt bundle + LLM odpovědi (lokální modely) |
| `tools/` | Retrieval (`wiki-query.py`), kontrola integrity, hooky `tools/bakery-sync/` |
| `.cache/` | Odvozený index (gitignored) |
| `CLAUDE.md` | Schéma vaultu |
| `AGENTS.md` | Instrukce pro libovolné AI agenty |

## Trigger wiki update

### IDE agent (Cursor, Claude, Codex…)

```bash
task wiki:update
```

### Lokální model (Ollama, LM Studio, LiteLLM, Open WebUI)

```bash
task wiki:local
# nebo: update → run-local → apply
```

Konfigurace API: `triggers/local-models.env` (z `.example`).

Lokální model dostane **prompt bundle** (`triggers/out/LATEST-prompt.md`) — celý kontext v jednom souboru, bez přístupu k disku. Odpověď se aplikuje přes `apply-wiki-response.sh`.

Viz [[concepts/LLM wiki maintenance]], `triggers/README.md`.

## Guardy

- Pre-commit: žádné absolutní cesty v `wiki/*.md`
- Pre-commit navíc: `tools/wiki-integrity-check.py` + `tools/wiki_index.py --force` (fail-closed), varování (nikdy blok), když chybí bakery-sync hooky
- Post-commit: auto-push na origin (`WIKI_AUTO_PUSH=false` vypne)
- Claude hook: `.claude/hooks/check-wiki-paths.sh`
- Hooky bakery-sync (session-start/touched/stop): viz [[concepts/Wiki sync policy]]

## Souvislosti

- [[concepts/LLM wiki maintenance]]
- [[overview]]
- [[concepts/Platform v2]]
