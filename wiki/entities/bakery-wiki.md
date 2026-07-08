---
title: bakery-wiki
type: entity
tags: [repo, wiki, obsidian, llm]
created: 2026-07-08
updated: 2026-07-08
---

**Obsidian vault + LLM wiki** pro Bakery platformu — analogie **Kytary.Wiki**. Znalostní graf Platform v2, pilotů a rozhodnutí.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-wiki
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-wiki`

## Struktura

| Path | Kdo edituje |
|------|-------------|
| `raw/` | Lidé (immutable pro LLM) |
| `wiki/` | LLM + review přes PR |
| `triggers/out/` | Prompt bundle + LLM odpovědi (lokální modely) |
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
- Claude hook: `.claude/hooks/check-wiki-paths.sh`

## Souvislosti

- [[concepts/LLM wiki maintenance]]
- [[overview]]
- [[concepts/Platform v2]]
