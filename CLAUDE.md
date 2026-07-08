# Bakery Platform — LLM Wiki Schema

This file governs how the LLM maintains the wiki in this Obsidian vault. Read it at the start of every session.

## Project context

**Bakery** is a generic Kubernetes platform for deploying microservice apps (fake_buster, stock-trader-grabit, …). Platform v2 splits the monolithic **service-bakery** into:

| Repo | Role |
|------|------|
| **bakery-platform** | Initial bootstrap, `bakery-app` Helm chart, CI, `image-versions.env` |
| **bakery-gitops** | Argo CD apps, values, infra addons |
| **bakery-onboarding** | Go HTTP service — onboard new services into app + gitops repos |
| **App repos** | Application code + `service-bakery.yaml` + `deploy/clusters/` |

Pilot: **fake_buster** on Kind cluster `kind-desktop` coexisting with **Kytary** stack (`infrastructure` namespace).

## Directory structure

```
bakery-wiki/
├── CLAUDE.md              ← this file (schema — LLM reads first)
├── setup.sh               ← one-time: core.hooksPath
├── raw/                   ← source documents (immutable, LLM never modifies)
│   └── *.md               ← clipped docs, meeting notes, exports
├── wiki/                  ← LLM-maintained wiki (LLM owns this entirely)
│   ├── index.md           ← catalog of all pages
│   ├── log.md             ← chronological activity log (append-only)
│   ├── overview.md        ← high-level platform synthesis
│   ├── sources/           ← summaries of ingested raw sources
│   ├── entities/          ← repos, services, clusters
│   ├── concepts/          ← patterns, decisions, runbooks
│   └── domains/           ← app business domains (optional)
└── Vítejte.md             ← Obsidian default (leave as-is)
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
- Cross-reference aggressively
- Relative paths: `[[entities/bakery-platform]]`, `[[concepts/Platform v2]]`

### Language

- Write in **Czech** for prose; technical terms in English (Kubernetes, Argo CD, Helm, …)
- Entity names: match repo names (`bakery-platform`, `fake_buster`)

### Page structure

1. Frontmatter
2. **Summary** — 2–3 sentences (no heading)
3. **Sections** — `##` headings
4. **Souvislosti** — related links at the bottom

## Workflows

### Ingest (new source → wiki updates)

1. User drops a file into `raw/`
2. LLM reads the source
3. LLM creates `wiki/sources/src-…`
4. LLM updates entity/concept pages
5. LLM updates `wiki/index.md`
6. LLM appends `wiki/log.md`

### Query

1. Read `wiki/index.md`
2. Read relevant pages, synthesize answer
3. File reusable answers as new pages if needed

### Lint

- Contradictions, orphan pages, missing cross-refs
- **Hardcoded absolute paths** in `wiki/*.md` (see rule #9)

## Repository mapping (Platform v2)

| Repo | Role | Status |
|------|------|--------|
| bakery-platform | Bootstrap + charts + CI | ✅ Pilot |
| bakery-gitops | Argo CD GitOps | ✅ Pilot |
| bakery-onboarding | Service onboarding API | ✅ Pilot |
| service-bakery | Legacy monolith platform | 🔄 Migrating away |
| fake_buster | App (ML fake news) | ✅ Pilot on kind-desktop |
| stock-trader-grabit | App (trading) | ⬜ Not migrated to v2 |

## Tech stack reference

- **Apps**: Java 25 / Spring Boot 4, Python, React, Go
- **Deploy**: Helm `bakery-app`, Argo CD, Kustomize root app
- **CI**: Argo Workflows `service-ci` (Kaniko, Maven, Node, Python)
- **Data**: CNPG PostgreSQL (shared `infrastructure` on pilot), Kafka (TBD GitOps)
- **Secrets**: `cluster.env` in app repos (never in bakery-platform)
- **Versions**: `bakery-platform/image-versions.env` (rule #9)

## Important rules

1. **Never modify `raw/`** — sources are immutable
2. **Always update `index.md` and `log.md`** after wiki changes
3. **Update `updated` in frontmatter** when editing a page
4. **Prefer updating existing pages** over creating new ones
5. **Track status**: ✅ ⬜ 🔄
6. **Never hardcode machine-specific paths** in `wiki/*.md`:
   - Forbidden: `/Users/...`, `/home/...`, `C:\Users\...`, literal `workspace_kytary`
   - Use placeholder: **`<workspace>/<repo-name>`** (sibling checkout layout)
   - `<workspace>` = parent of any cloned repo (`dirname "$(git rev-parse --show-toplevel)"` at runtime — never write that path into wiki)

   **Enforced by:**
   - Claude Code hook: `.claude/hooks/check-wiki-paths.sh`
   - Git pre-commit: `.githooks/pre-commit` (enable via `./setup.sh`)
