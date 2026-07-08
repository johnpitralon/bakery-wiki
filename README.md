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

## Structure

| Path | Who edits |
|------|-----------|
| `raw/` | Humans only (drop sources here) |
| `wiki/` | LLM (+ human review via PR) |
| `CLAUDE.md` | Schema — read first |

## Related repos

- `bakery-platform` — bootstrap, charts, `image-versions.env`
- `bakery-gitops` — Argo CD
- `bakery-onboarding` — onboard API
