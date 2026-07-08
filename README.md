# bakery-wiki

Obsidian vault + **LLM-maintained wiki** for the Bakery platform (Platform v2).

Inspired by [Kytary.Wiki](https://github.com/ITKytaryDevTeam/Kytary.Wiki) — same schema: `raw/` (immutable sources) + `wiki/` (LLM-owned knowledge graph).

## Quick start

1. Open this folder as an **Obsidian vault** (or add to workspace).
2. Run once after clone:

```bash
./setup.sh
```

3. Read `CLAUDE.md` before any LLM session that edits `wiki/`.

## Wiki update (libovolné LLM — včetně lokálních)

### IDE agent
```bash
task wiki:update
```

### Lokální model (Ollama, LM Studio, LiteLLM, Open WebUI)
```bash
cp triggers/local-models.env.example triggers/local-models.env
task wiki:local
```

| Příkaz | Popis |
|--------|-------|
| `task wiki:bundle` | Self-contained prompt do `triggers/out/` |
| `task wiki:run-local` | OpenAI-compatible API call |
| `task wiki:apply` | Zapíše `<wiki-file>` odpověď na disk |

Detail: `triggers/README.md`, `WIKI_UPDATE.md`

## Structure

| Path | Who edits |
|------|-----------|
| `raw/` | Humans only (drop sources here) |
| `wiki/` | LLM (+ human review via PR) |
| `CLAUDE.md` | Schema — read first |
| `AGENTS.md` | Auto-instrukce pro AI agenty |
| `WIKI_UPDATE.md` | Univerzální update prompt |

## Related repos

- `bakery-platform` — bootstrap, charts, `image-versions.env`
- `bakery-gitops` — Argo CD
- `bakery-onboarding` — onboard API
