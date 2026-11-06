---
title: LLM wiki maintenance
type: concept
tags: [wiki, llm, automation, trigger]
created: 2026-07-08
updated: 2026-11-06
---

Mechanismus udržování [[entities/bakery-wiki]] — **nezávislý na konkrétním LLM**: cloud IDE agenty **i lokální modely** (Ollama, LM Studio, LiteLLM, Open WebUI).

## Princip

1. **Schéma** (`CLAUDE.md`) — jednotná pravidla
2. **Trigger** (`scripts/trigger-wiki-update.sh`) — snapshot + prompt bundle + `.wiki-update-request`
3. **Prompt bundle** (`triggers/out/LATEST-prompt.md`) — celý kontext v jednom souboru pro lokální LLM
4. **Lokální API** (`scripts/run-wiki-update-local.sh`) — OpenAI-compatible endpoint
5. **Apply** (`scripts/apply-wiki-response.sh`) — `<wiki-file>` → disk

## Dva režimy

| Režim | Kdo | Jak |
|-------|-----|-----|
| **IDE agent** | Cursor, Claude, Codex, Aider | Čte repo, edituje `wiki/` přímo |
| **Lokální LLM** | Ollama, LM Studio, vLLM, Open WebUI | Bundle → API → apply response |

## Lokální pipeline

```bash
task wiki:update
cp triggers/local-models.env.example triggers/local-models.env
task wiki:run-local    # nebo task wiki:local (= update+run+apply)
task wiki:apply
```

Env: `WIKI_LLM_BASE_URL`, `WIKI_LLM_MODEL` — default Ollama `http://127.0.0.1:11434/v1`.

## Režimy práce

| Režim | Kdy | Co LLM dělá |
|-------|-----|-------------|
| `update` | Po práci na platformě | Sync entity + overview |
| `ingest` | Nový `raw/` | `wiki/sources/src-…` + propagace |
| `lint` | Periodicky | Kontradikce, orphan, statusy |

## Retrieval (search-first)

Dotazy nad wiki se nečtou přes celý `index.md`, ale přes `tools/wiki-query.py`:

```bash
python3 tools/wiki-query.py search "<dotaz>"
python3 tools/wiki-query.py section <cesta> <nadpis>
python3 tools/wiki-query.py related <cesta>      # jen když je potřeba
```

Index (`tools/wiki_index.py`) žije v `.cache/` — je odvozený, gitignored a staví se znovu
z manifestu, když neodpovídá working tree. Postup je převzatý z Kytary.Wiki a v bakery-wiki
není měřený. `tools/wiki-integrity-check.py` (frontmatter, odkazy, kotvy, indexace, strop
40 000 znaků; výjimka klíčem `size_exception`) i přestavba indexu běží v `.githooks/pre-commit`
při staged `wiki/*.md`. Viz [[entities/bakery-wiki]], [[concepts/Wiki sync policy]].

## Integrace

| Nástroj | Jak spustit |
|---------|-------------|
| Ollama | `task wiki:local` |
| LM Studio | `WIKI_LLM_BASE_URL=http://127.0.0.1:1234/v1` |
| LiteLLM / bakery gateway | URL z `bakery-agent-infra` |
| Open WebUI | Vlož `LATEST-prompt.md` do chatu → apply |
| Cursor / Claude | `/wiki-update` → `task wiki:finish` |
| Aider + Ollama | `task wiki:aider` → `task wiki:finish` |

Po každém update: agent commitne explicitními `git add <cesty>` (nikdy `-A`) a push udělá post-commit; `task wiki:finish` / `wiki-commit-push.sh` (`git add -A`) jen pro pipeline s lokálním modelem.
Viz [[concepts/Wiki sync policy]].

Detail: `triggers/README.md`

## Souvislosti

- [[entities/bakery-wiki]]
- [[concepts/Wiki sync policy]]
- [[log]]
