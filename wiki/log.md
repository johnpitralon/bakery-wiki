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
- ✅ Argo `fake-buster` Synced / Healthy (5/5 pody po CI + registry fix)
- ✅ CI E2E: labeler → inference → db-writer → crawler → frontend do kind-registry
- ⬜ Kafka — disabled v values do infra/kafka
- ✅ Legacy Argo `service-bakery` smazána
- ✅ Default branch všech rep: **dev**

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
- `scripts/wiki-update-aider.sh` — **doporučeno** pro lokální modely
- Aktualizováno [[concepts/LLM wiki maintenance]]

## [2026-07-08] platform-hardening | PR #1 merged + Argo-only

- **bakery-platform**, **bakery-gitops**, **bakery-onboarding** — PR #1 na `main`
- ApplicationSet `bakery-apps` z `apps/*/app.json` ([[entities/bakery-gitops]])
- Argo jediný deployer; `cleanup-legacy-deploy.sh` (helm + service-bakery app)
- `bump-gitops-image-tag.sh`, `configure-kind-registry.sh`, githooks, CI workflows
- Aktualizováno: [[overview]], [[entities/bakery-platform]], [[entities/bakery-gitops]], [[concepts/GitOps workflow]]

## [2026-07-08] onboarding-llm | MCP multi-client

- [[entities/bakery-onboarding]]: MCP `cmd/mcp-server`, Open WebUI OpenAPI, `/onboard-service`
- Aktualizováno [[concepts/Service onboarding]]

## [2026-07-08] pilot-fix | Registry :5001 + CI E2E + dev default

- **Registry:** `kind-registry` na host `:5001`; gitops `registryHost: localhost:5001`
- **configure-kind-registry.sh:** upstream `kind-registry:5000`, fix `docker exec -i`
- **CI E2E:** 5/5 služeb fake-buster build → registry; `fake-buster` Argo **Healthy**
- **Větve:** všechny bakery rep — default **`dev`**, `main` = release
- Aktualizováno: [[entities/fake_buster]], [[concepts/GitOps workflow]], pilot-runbook

## [2026-07-08] auto-commit | Wiki commit/push po každém update

- `scripts/wiki-commit-push.sh` — auto commit + push po update
- `.githooks/post-commit` — push po každém commitu v bakery-wiki
- `task wiki:commit`, `task wiki:finish`; `apply-wiki-response.sh` volá commit automaticky
- Aktualizováno [[concepts/Wiki sync policy]], `AGENTS.md`, `/wiki-update` commands
