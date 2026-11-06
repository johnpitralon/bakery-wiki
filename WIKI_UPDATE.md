# Wiki update

Krátký prompt — kanonická pravidla v **`AGENTS.md`**, schéma v **`CLAUDE.md`**.

## Doporučené: Aider + lokální model

```bash
cp triggers/local-models.env.example triggers/local-models.env
task wiki:aider
```

Aider (Ollama, LM Studio, LiteLLM) edituje `wiki/` přímo — bez XML bundle.

## IDE agent (Cursor, Claude, Codex)

```
Proveď wiki update podle AGENTS.md. Režim: update.
Aktualizuj wiki/, index.md, append log.md. Smaž .wiki-update-request.
```

Nebo: `task wiki:update` → `/wiki-update`

## Fallback: čistý chat API

```bash
task wiki:local    # bundle → API → apply-wiki-response.sh
```

Pro Open WebUI: vlož `triggers/out/LATEST-prompt.md` do chatu → `apply-wiki-response.sh`.

## Příkazy

| Příkaz | Popis |
|--------|-------|
| `task wiki:update` | snapshot + bundle |
| `task wiki:aider` | **doporučeno** — lokální model |
| `task wiki:local` | API fallback |
| `task wiki:finish` | Po lokálním modelu / Aideru — commit + push + cleanup (`git add -A`) |
| `task wiki:commit` | Jen commit + push |

**Auto commit/push** jen pro pipeline s lokálním modelem: `scripts/wiki-commit-push.sh` (`git add -A`, vypnutí: `WIKI_AUTO_COMMIT=false`). Agenti: explicitní `git add <cesty>` + commit, push udělá post-commit.
