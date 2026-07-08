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

## [2026-07-08] stock-trader-grabit | Plán 1 (Trading/Markets) nasazen + bump-tag fix

- **stock-trader-grabit PR #58** mergnut do dev: order creation, watchlist, `instrumentType` filtr, logout/close position, bez mock dat. CI build 3 služeb → tag `56d7d29`, Argo Synced/Healthy.
- **bakery-platform:** fix `bump-gitops-image-tag.sh` — regex `\1` + tag začínající číslicí korumpoval values.yaml (`\g<1>` fix, commit 6cf0034). Poškozený bump opraven v bakery-gitops (PR #11).
- **⚠️ Objeven blocker:** backend validuje JWT HS256 shared secretem, Keycloak vydává RS256 → všechna autentizovaná `/api/**` 401. Viz [[entities/stock-trader-grabit]].
- Přidáno [[entities/stock-trader-grabit]]; aktualizován [[index]].

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

## [2026-07-08] pilot-complete | Platform v2 pilot dokončen

Pilot na `kind-desktop` — obě app **Synced / Healthy**:

- ✅ **fake-buster** — Kafka, Keycloak realm, login auth-proxy, registry `:5001`
- ✅ **stock-trader-grabit** — CI prereqs, Keycloak realm, auth-proxy fix, login ověřen
- ✅ **Kafka** — `infra/kafka/` v bakery-gitops, obě app values wired
- ✅ **Keycloak** — `ensure-keycloak-realm.sh`, URL `keycloak.local.k8s.kytary.cz`
- ✅ **Scope hranice** — runbook + wiki: nemazat kytary feat preview Argo apps
- ✅ **service-bakery** — deprecated (tag `platform-v2-pilot-final`)
- ✅ **bakery-platform PR #12** — runbook scope + bump-gitops regex fix

Aktualizováno: [[overview]], [[concepts/Platform v2]], [[concepts/Koexistence s Kytary]],
[[entities/fake_buster]], [[entities/stock-trader-grabit]], [[entities/bakery-platform]],
[[entities/bakery-gitops]], [[entities/service-bakery]], [[index]], tento log.

## [2026-07-08] decommission | service-bakery repo smazán

- Repozitář **service-bakery** zálohován a odstraněn (GitHub + lokální clone)
- Tag `platform-v2-pilot-final` = poslední snapshot
- Decommission checklist v `bakery-platform/docs/decommission-service-bakery.md` — hotovo
- Aktualizováno [[entities/service-bakery]], tento log

## [2026-07-08] stock-trader-grabit | Plan 1 + JWKS auth fix

- ✅ **Plan 1** (grabit-web trading/markets) — PR #58 merged, CI tag `56d7d29` → frontend/backend features
- ✅ **JWKS/RS256** — `JwtTokenProvider` + `JWT_JWKS_URI` v gitops; Spring bean fix `e21befc`; CI build + deploy
- ✅ **E2E auth** — token přes grabit-web auth-proxy; `/api/watchlist` a `/api/tickers` 200 (dříve 401)
- ⚠️ Flyway — prázdné DB při prvním deployi; jednorázové migrace v clusteru (tx + analytics)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.
