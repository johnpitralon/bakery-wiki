# Bakery Platform — LLM Wiki Schema

> **Kanonické instrukce:** [`AGENTS.md`](AGENTS.md) — čti nejdřív tam.
> Tento soubor = schéma vaultu (struktura, konvence, pravidla).

## Project context

**Bakery** is a generic Kubernetes platform for deploying microservice apps (fake_buster, stock-trader-grabit, …). Platform v2 splits the monolithic **service-bakery** into:

| Repo | Role |
|------|------|
| **bakery-platform** | Initial bootstrap, `bakery-app` Helm chart, CI, `image-versions.env` |
| **bakery-gitops** | Argo CD apps, values, infra addons |
| **bakery-onboarding** | Go HTTP service — onboard new services into app + gitops repos |
| **bakery-wiki** | Obsidian + LLM wiki |
| **App repos** | Application code + `service-bakery.yaml` + `deploy/clusters/` |

Pilot: **fake_buster** on Kind cluster `kind-desktop` coexisting with **Kytary** stack (`infrastructure` namespace).

## Directory structure

```
bakery-wiki/
├── AGENTS.md              ← kanonické instrukce pro všechna LLM
├── WIKI_UPDATE.md         ← krátký prompt / task příkazy
├── CLAUDE.md              ← tento soubor (schéma vaultu)
├── scripts/
│   ├── trigger-wiki-update.sh
│   ├── wiki-update-aider.sh   ← lokální modely (doporučeno)
│   └── run-wiki-update-local.sh  ← fallback (API + apply)
├── raw/                   ← source documents (immutable, LLM never modifies)
│   └── auto-snapshot-latest.md
├── wiki/                  ← LLM-maintained wiki
│   ├── index.md
│   ├── log.md
│   ├── overview.md
│   ├── sources/
│   ├── entities/
│   └── concepts/
└── triggers/              ← local-models.env, out/
```

## Page conventions

### Frontmatter (YAML)

Every wiki page MUST have frontmatter:

```yaml
---
title: Page Title
type: entity | concept | domain | source | overview
tags: [relevant, tags]
sources: []
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Linking

- Use Obsidian wiki links: `[[Page Name]]` or `[[path/to/page|Display Text]]`
- Entity names: match repo names (`bakery-platform`, `fake_buster`)

### Language

- Write in **Czech** for prose; technical terms in English
- **Never hardcode absolute paths** in `wiki/*.md` — use `<workspace>/<repo>`

## Workflows

Viz `AGENTS.md` — ingest, update, lint.

### Wiki update trigger

```bash
task wiki:update              # příprava
task wiki:aider               # lokální model + Aider (doporučeno)
task wiki:local               # fallback: API bundle + apply
```

## Repository mapping (Platform v2)

| Repo | Role | Status |
|------|------|--------|
| bakery-platform | Bootstrap + charts + CI | ✅ Pilot |
| bakery-gitops | Argo CD GitOps + ApplicationSet | ✅ Pilot |
| bakery-onboarding | Service onboarding API | ✅ Pilot |
| bakery-wiki | LLM-maintained Obsidian wiki | ✅ Active |
| service-bakery | Legacy monolith platform | 🔄 Migrating away |
| fake_buster | App (ML fake news) | ✅ Pilot on kind-desktop |
| stock-trader-grabit | App (trading) | ✅ Pilot on v2 |

## Important rules

1. **Never modify `raw/`** (except humans drop sources; auto-snapshot is overwritten)
2. **Always update `index.md` and `log.md`** after wiki changes
3. **Wiki sync policy** — any agent changing bakery-platform/gitops/onboarding/apps **must** update this wiki in the same session (see `wiki/concepts/Wiki sync policy.md`)
4. **Update `updated` in frontmatter** when editing a page
4. **Prefer updating existing pages** over creating new ones
5. **Track status**: ✅ ⬜ 🔄
6. **No absolute paths** in `wiki/*.md` — enforced by `.githooks/pre-commit`
