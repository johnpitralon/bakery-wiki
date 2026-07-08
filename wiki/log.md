---
title: Log
type: overview
tags: [log, meta]
created: 2026-07-08
updated: 2026-07-08
---

Chronologický záznam aktivit wiki — ingest, query, lint, údržba.

## [2026-07-08] init | Založení bakery-wiki

Vytvořeno repo **bakery-wiki** podle schématu Kytary.Wiki (Obsidian vault + `CLAUDE.md` schema + `raw/` + `wiki/`).

Počáteční obsah:
- Entity stránky pro Platform v2 repozitáře + `fake_buster` + legacy `service-bakery`
- Koncepty: Platform v2, GitOps, onboarding, koexistence s Kytary, image-versions
- Guardy proti natvrdo zadaným cestám v `wiki/*.md` (`.githooks/pre-commit`, `.claude/hooks/`)

Aktualizováno: [[index]], [[overview]], tento log.

## [2026-07-08] pilot | Platform v2 fake-buster na kind-desktop

Pilotní nasazení (shrnutí pro wiki — detail v app/cluster stavu):

- ✅ `bakery-platform` initial.sh — service-ci, gitops-root
- ✅ `bakery-onboarding` Running v `bakery-agent-infra`
- ✅ fake-buster pody: labeler, inference, db-writer, frontend (4/4 Running)
- ✅ Argo `fake-buster` Synced / Healthy (po recreate deploymentů v2 chart)
- ✅ Helm release `deployed` rev 15 (oprava po timeoutu rev 14)
- ⬜ Kafka — po helm upgrade chybí broker (dočasný bootstrapServers v values)
- ⬜ Argo `service-bakery` — legacy app, deprecate
- 🔄 Githooky + image-versions změny — lokálně, necommitnuto

Viz [[entities/fake_buster]], [[concepts/Koexistence s Kytary]].

## [2026-07-08] ingest | Pilot snapshot + LLM trigger

- Přidán `raw/platform-v2-pilot-snapshot-2026-07-08.md`
- Vytvořen [[sources/src-platform-v2-pilot-snapshot]]
- Aktualizovány [[overview]], entity stránky, [[index]]
- Nový koncept [[concepts/LLM wiki maintenance]] + entity [[entities/bakery-wiki]]
- Trigger mechanismus: `scripts/trigger-wiki-update.sh`, `WIKI_UPDATE.md`, `AGENTS.md`, `task wiki:update`, `/wiki-update` (Cursor + Claude)

## [2026-07-08] local-llm | Podpora lokálních modelů

- `scripts/build-prompt-bundle.sh` — self-contained prompt (`triggers/out/LATEST-prompt.md`)
- `scripts/run-wiki-update-local.sh` — OpenAI-compatible API (Ollama, LM Studio, LiteLLM)
- `scripts/apply-wiki-response.sh` — `<wiki-file>` → disk
- `triggers/local-models.env.example`, `task wiki:local` / `wiki:run-local` / `wiki:apply`
- Aktualizováno [[concepts/LLM wiki maintenance]], `triggers/README.md`
