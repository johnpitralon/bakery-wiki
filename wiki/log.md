---
title: Log
type: overview
tags: [log, meta]
created: 2026-07-08
updated: 2026-07-14
---

Chronologický záznam aktivit wiki — ingest, query, lint, údržba.

## [2026-07-08] init | Založení bakery-wiki

Vytvořeno repo **bakery-wiki** podle schématu Kytary.Wiki (Obsidian vault + `CLAUDE.md` schema + `raw/` + `wiki/`).

Počáteční obsah:
- Entity stránky pro Platform v2 repozitáře + `fake-buster` + legacy `service-bakery`
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

Viz [[entities/fake-buster]], [[concepts/Koexistence s Kytary]].

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
- Aktualizováno: [[entities/fake-buster]], [[concepts/GitOps workflow]], pilot-runbook

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
[[entities/fake-buster]], [[entities/stock-trader-grabit]], [[entities/bakery-platform]],
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

## [2026-07-10] stock-trader-grabit | Plan 4 — TickerImportService

- ✅ `TickerImportService` — listing/EODHD/popular/symbol import + `upsertTickersFromProvider` s Map loaded/updated
- ✅ `TickerSymbolUtils`, `TickerCompanyInfoMapper` — sdílené helpery
- ✅ `TickerService` zmenšen na fasádu (~3600 ř., dříve ~4400)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-10] stock-trader-grabit | Plan 4 (částečně)

- ✅ `TickerQueryService` extrahován z `TickerService` (read/search/history queries)
- ✅ Testy: `TickerQueryServiceTest`, `TickerServiceTest`, `TradingServiceTest`, `TradingHandlerTest`
- ✅ `AutomatedOpenApiGenerator` — odstraněny neimplementované Postman/AI větve
- ✅ `application.properties` — odstraněny nebezpečné defaulty (JWT, DB, legacy hosty)
- ✅ `docs/provider-api-keys.md`; gitops `SPRING_KAFKA_BOOTSTRAP_SERVERS`
- 🔄 Zbývá: další extrakce TickerService (Import, CompanyInfo, …), finální smoke

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-10] stock-trader-grabit | Plan 3 dokončen

- ✅ GitOps values už pinují SHA tagy (stock-trader `e21befc`, frontends `56d7d29`); Argo **Synced / Healthy**
- ✅ CI: `ci-build-from-catalog.sh` defaultuje `IMAGE_TAG` z lokálního git HEAD; Kaniko dual tag SHA + `latest`
- ✅ `deploy/run-ci-build.sh` — export IMAGE_TAG, volitelný `GITOPS_BUMP=true`
- ✅ `.github/workflows/pr-checks.yml` — backend testy, grabit-web jest/build, frontend-st build na PR
- ⬜ Argo Image Updater — follow-up (žádný vzor v bakery-gitops)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-10] stock-trader-grabit | Plan 2 dokončen

- ✅ Odstraněny verzované `coverage/` a `.idea/` z gitu; `.gitignore` doplněn
- ✅ Docs sjednoceny na Platform v2 (README, bootstrap deprecated, `cluster.env.example`, Taskfile `secrets` task)
- ✅ grabit-web Dockerfile: Node 20; login UI: demo credentials jen při `NEXT_PUBLIC_SHOW_DEMO_CREDENTIALS=true`
- ✅ `deploy/clusters/local/cluster.yaml` — Platform v2 profil (jen `cluster_name`, bez legacy `app_repos`)
- ✅ GitOps: `NEXT_PUBLIC_SHOW_DEMO_CREDENTIALS: "true"` u `grabit-web` a `frontend-st` pro lokální pilot
- ✅ Pody v NS `stock-trader-grabit`: stock-trader, grabit-web, frontend-st **Running** (2026-07-10)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-10] stock-trader-grabit | Plan 4 — TickerService split dokončen

- ✅ `CompanyInfoService`, `PriceHistoryService`, `EarningsService` extrahovány z `TickerService`
- ✅ Oprava korupce `TickerService` po `TickerImportService` extrakci
- ✅ `TickerService` fasáda ~1100 ř. (dříve ~4470); handlery/schedulery beze změny API
- ⬜ Úloha 7: PR CI + smoke v clusteru po merge

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-10] infra | Kind registry — persist + in-cluster DNS

- ✅ Host `kind-registry` s bind mount `~/docker-persistent/worker1/registry` (Kytary worker1 layout)
- ✅ Skript `ensure-kind-registry-host.sh` (migrace z Docker volume přes `docker cp`)
- ✅ GitOps `infra/registry/`: `fake-buster-registry`, `stock-trader-grabit-registry` → `host.docker.internal:5001`
- ✅ Ověřeno z podu: DNS + `/v2/` OK v NS `stock-trader-grabit`

Aktualizováno: [[entities/bakery-platform]], [[entities/bakery-gitops]], [[concepts/Koexistence s Kytary]], tento log.

## [2026-07-10] infra | Hetzner prod skeleton

- ⬜ GitOps `clusters/hetzner-prod/` — ApplicationSet `bakery-apps-hetzner-prod`, branch `main`
- ⬜ `values-hetzner-prod.yaml` pro fake-buster a stock-trader-grabit (placeholdery)
- ⬜ App profily `deploy/clusters/hetzner-prod/` v obou app repách
- ⬜ Runbook `bakery-platform/docs/hetzner-prod-runbook.md`

Aktualizováno: [[concepts/Hetzner prod skeleton]], [[entities/bakery-gitops]], [[concepts/Platform v2]], [[index]], tento log.

## [2026-07-10] infra | Pod cleanup CronJob

- ✅ `infra/pod-cleanup/` — CronJob `bakery-pod-cleanup` každých 30 min (Succeeded + Failed/Evicted)
- ✅ ClusterRole + SA v `bakery-agent-infra`
- ✅ Pilot runbook — automatický cleanup dokumentován

Aktualizováno: [[entities/bakery-gitops]], [[concepts/Koexistence s Kytary]], tento log.

## [2026-07-11] stock-trader-grabit | Plán 5 Úloha 1 — frontend-st Jest

- ✅ Jest + Testing Library setup (vzor grabit-web)
- ✅ Smoke testy login + dashboard (3 testy PASS)
- ✅ PR CI `frontend-st-build` — `npx jest --ci` před buildem
- Commit `538905e` na `dev`

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-11] stock-trader-grabit | Plán 5 Úloha 3 — iOS Keycloak auth

- ✅ `AuthService` — password + refresh grant na Keycloak (`client_id: frontend`)
- ✅ `APIClient` — form POST, proactive refresh (<60s), 401 retry
- ✅ `TokenStorage` + JWT role/username z access tokenu
- ✅ Config Keycloak NodePort `:30084` (dříve chybně `:30082` = Grafana)
- Commit `ebe1ee0` na `dev`

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-11] stock-trader-grabit | Plán 5 Úloha 4 — iOS testy, logging, config

- ✅ `GrabItTests` target v `project.yml` + `project.pbxproj` + Xcode scheme
- ✅ `APIClient` — `init?`, `APIURLResolver`, `APIClientFactory` s fallback URL
- ✅ `AppLog` — strukturované logování (`api`, `auth`, `config`, `websocket`, `ui`)
- ✅ `Config` — URL z `Info.plist` (simulátor: `:30084` + `stock-trader.localhost`)
- ✅ Unit testy: `APIClientTests`, `AuthServiceTests`
- ⬜ `xcodebuild test` — blokováno bez plného Xcode; commit lokálně připraven

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-11] stock-trader-grabit | Plán 5 Úloha 2 — Next.js 15 upgrade

- ✅ `grabit-web` + `frontend-st`: Next `14.2.35` → **15.5.20**
- ✅ Jest (61 + 3 testů) a `npm run build` OK v obou appkách
- ✅ `auth-proxy` route už měla async `params` (Next 15 ready)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-11] stock-trader-grabit | portfolio 500 fix + CI deploy 4808c25

- ✅ `TradingService.getPortfolio` — writable tx (readOnly blokoval bootstrap účtu), null-safe `isDemoMode`
- ✅ Commity `43644ad`, `4808c25` na `dev`
- ✅ CI build všech 3 služeb, gitops `b701745`, cluster **Synced/Healthy** na tagu `4808c25`

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-12] bakery-platform | Kytary-style githooks pro multi-agent

- ✅ `refresh-githooks.sh --all` rozšířeno o `bakery-multi-agent-platform` a `bakery-wiki`
- ✅ `bakery-multi-agent-platform`: sync `.githooks/` (`local/<user>/<slug>` + auto PR), `task hooks`
- ✅ PR [#14](https://github.com/johnpitralon/bakery-platform/pull/14), multi-agent PR [#1](https://github.com/johnpitralon/bakery-multi-agent-platform/pull/1)

Aktualizováno: [[entities/bakery-platform]], tento log.

## [2026-07-12] fake-buster | Přejmenování repozitáře + Kytary githooks

- ✅ GitHub `johnpitralon/fake_buster` → **johnpitralon/fake-buster**
- ✅ Lokální clone: `<workspace>/fake-buster` (dříve `fake_buster`)
- ✅ Kytary-style `.githooks/` + `task hooks` (PR [#11](https://github.com/johnpitralon/fake-buster/pull/11))
- ✅ stock-trader-grabit githooks PR [#60](https://github.com/johnpitralon/stock-trader-grabit/pull/60)

Aktualizováno: [[entities/fake-buster]], tento log.

## [2026-07-12] kind-desktop | Trvalá mitigace DiskPressure

Incident: všechny 4 nody `DiskPressure` → masové **Evicted** pody (promtail na control-plane, argocd-repo-server). Recovery ~6 min po uvolnění Docker build cache.

**Trvalé opatření (nasazeno + na `dev`):**

- ✅ `bakery-gitops` `9885911`: Promtail workers-only, `monitoring-maintenance` CronJob (15 min), `bakery-pod-cleanup` každých 10 min
- ✅ `bakery-platform` PR [#18](https://github.com/johnpitralon/bakery-platform/pull/18): `task kind-disk-maintenance`, runbook
- ✅ Live cluster: 3× promtail na workerech, žádný na control-plane; `DiskPressure: False`

Aktualizováno: [[entities/bakery-gitops]], [[entities/bakery-platform]], tento log.

## [2026-07-12] GUI split | Tři frontendy — fake-buster / frontend-st / grabit-web

- ✅ **fake-buster** `frontend.localhost` — pouze ML (Dashboard, Label, Training, Crawler Admin, Users); odstraněn Stock Trader UI
- ✅ **frontend-st** — launcher + `/stock-trader/*` admin (jediná kopie Stock Trader GUI)
- ✅ **grabit-web** — trading; Profil → odkaz na frontend-st
- ✅ Cross-link env: `NEXT_PUBLIC_FRONTEND_ST_URL`, redirects `/stock-trader` z fake-buster
- ✅ Dokumentace: `fake-buster/docs/frontend-split-and-monitoring.md`
- Aktualizováno: [[entities/fake-buster]], [[entities/stock-trader-grabit]], gitops env

## [2026-07-12] monitoring | Crawler batch monitoring + chart env fix

- ✅ `kube-state-metrics` v `monitoring` (CronJob/Job metriky pro `fake-buster-crawler`)
- ✅ Prometheus alert rules: `BakeryCrawlerJobFailed`, `BakeryCrawlerStale`, `BakeryCrawlerJobRunningTooLong`
- ✅ Grafana dashboard `fake-buster-crawler` + panel v overview
- ✅ `bakery-app` chart: crawler CronJob dostává DB/Kafka/Loki env (oprava padajících jobů)
- ⬜ Argo sync `fake-buster` — aplikuje nový CronJob manifest s DB credentials

Aktualizováno: [[entities/bakery-gitops]], [[entities/bakery-platform]], tento log.

## [2026-07-12] fix | CORS stock-trader + Keycloak role mapping fake-buster

- ✅ **stock-trader-grabit** — `APP_CORS_ALLOWED_ORIGINS` v gitops + `${CORS_ALLOWED_ORIGINS}` v Spring prod/dev; oprava Network Error z `frontend-st`
- ✅ **bakery-platform** — chart injektuje `APP_CORS_ALLOWED_ORIGINS` vedle `CORS_ALLOWED_ORIGINS`
- ✅ **fake-buster** — `mapKeycloakRole` filtruje `default-roles-fake-buster`; oprava visícího „Checking permissions…“
- ✅ Mergnuto do `dev`: fake-buster #20, stock-trader-grabit #65, bakery-platform #20, bakery-gitops přímo

Aktualizováno: tento log.

## [2026-07-12] ingress | Backend API přes frontend proxy, BE ingress vypnutý

- ✅ **fake-buster** — `/api/labeler-proxy`, `/api/inference-proxy`; alias `labeler/inference/db-writer.localhost` → `frontend.localhost`
- ✅ **stock-trader-grabit** — `/api/stock-trader-proxy` na frontend-st a grabit-web; `stock-trader.localhost` → frontend-st
- ✅ **bakery-platform** — `ingress.additionalHosts` v IngressRoute
- ✅ **bakery-gitops** — vypnutý veřejný ingress BE služeb, internal `*_SERVICE_URL` pro proxy

Aktualizováno: [[entities/fake-buster]], [[entities/stock-trader-grabit]], tento log.

## [2026-07-12] test | Playwright E2E smoke v app repech

- ✅ **fake-buster** — `e2e/` (proxy, shell, alias hosty, login); `task e2e`; `.github/workflows/e2e-smoke.yml` (workflow_dispatch)
- ✅ **stock-trader-grabit** — `e2e/` (frontend-st, grabit-web, proxy, `stock-trader.localhost` alias); 9/9 testů proti pilotu
- ✅ **bakery-wiki** — [[concepts/E2E smoke tests]]

Aktualizováno: [[entities/fake-buster]], [[entities/stock-trader-grabit]], [[index]], tento log.

## [2026-07-12] fix | frontend-st Keycloak token refresh (401 na Scheduled Jobs)

- ✅ **stock-trader-grabit** PR #67 — `frontend-st` proaktivně obnovuje Keycloak JWT (5 min TTL) + retry na 401; oprava 401 na `/api/statistics/jobs` po idle
- ✅ Mergnuto do `dev`: `c34a9b1`

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-13] fix | stock-trader CPU burn (Massive WS + Loki retry loops)

- ✅ **stock-trader-grabit** PR #72–#73 — WS backoff, Loki appenders jen pod profile `loki`, image `8abe7e7`
- ✅ **bakery-gitops** — vypnutý Loki + multi-provider WS pro lokální pilot
- ✅ **bakery-platform** — `SPRING_PROFILES_INCLUDE=loki` v `bakery-app.lokiEnv` (PR #22)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-13] feat | Kind cluster pause/resume (bakery-platform)

- ✅ `task kind-pause` / `task kind-resume` / `task kind-status` — docker stop/start Kind bez mazání dat
- Dokumentace: `bakery-platform/docs/pilot-runbook.md` (PR #23)

Aktualizováno: [[entities/bakery-platform]], tento log.

## [2026-07-13] feat | GrabIt typed instrument overview API

- ✅ **stock-trader-grabit** — nový autentizovaný `GET /api/instruments/{symbol}/overview` pro web/iOS
- ✅ Typed immutable DTO nad `TickerEntity` + nejnovější dokončenou daily candle; jeden bar stačí, bez baru jsou history hodnoty `null`
- ✅ Deterministická freshness (15 minut, budoucí timestamp `UNKNOWN`); bez autoritativního zdroje market status vždy `UNKNOWN` / `UNAVAILABLE`
- ✅ Chyby `{error, message}` bez leaků a integračně ověřená autentizace `/api/**`
- ✅ JPA lookup na `boundedElastic`, sanitizované error logování, contextual provider decimal parsing a override-friendly `Clock`
- ✅ TDD: cílené testy 25/25, celý backend suite 178/178

Aktualizováno: [[entities/stock-trader-grabit]], [[index]], tento log.

## [2026-07-13] feat | GrabIt web instrument hub a bezpečný OrderTicket

- ✅ `/instruments/[symbol]` — typed overview, daily-only Recharts graf, OHLCV tabulka, fundamentals/market metadata a pravdivé loading/404/error/partial/stale/empty stavy
- ✅ Reusable dvoukrokový `OrderTicket` — BUY/SELL, MARKET/LIMIT, quantity/cash amount, skutečný fee, balance/position kontroly, confirm revalidation a duplicate-submit lock
- ✅ `/trading?symbol=...` používá stejný ticket; odstraněny STOP, SL/TP a placeholder intraday chart
- ✅ Centralizovaná product policy: STOCKS/ETFS/FOREX/INDICES/COMMODITIES + Bitcoin-only CRYPTO; nepodporované výsledky i order flow jsou blokované
- ✅ `UNKNOWN` market vyžaduje explicitní acknowledgement, `CLOSED` blokuje přípravu a status se znovu ověřuje při confirmu
- ✅ Strict plain-decimal validace (max. 8 míst), pravdivá okamžitá LIMIT simulace, `100R` místo falešného `MAX`
- ✅ Confirm znovu aplikuje centralizovanou product policy a odmítne mezitím nepodporovaný instrument ještě před `createOrder`
- ✅ Bezpečné backend message: strukturovaný `message` → `error`; plain-text/stack-like history body se nezobrazuje, chronologická daily data a solid chart styling bez gradientu
- ✅ TDD + verifikace: Jest 130/130, TypeScript, Next production build a lint

Aktualizováno: [[entities/stock-trader-grabit]], [[index]], tento log.

## [2026-07-14] feat | GrabIt redesign — iOS instrument hub + produktové plochy

- ✅ **iOS** — Markets → detail → trade flow; typed overview, product policy, fee-aware OrderEntry; design system tokeny
- ✅ **Web produktové plochy** — Czech navigace (Domů/Objevovat/Obchodovat/Portfolio/Profil), dashboard z API, portfolio bez falešných statistik, deep-linky na detail
- ✅ **Backend** — security test fix: `@DynamicPropertySource` pro HS256 v CI (host `JWT_SECRET` env)
- ✅ Verifikace: Jest 130/130, backend suite PASS, Next build PASS; GitOps smoke po merge (login → discovery → detail → order → portfolio)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.

## [2026-07-14] fix | Manuální joby stock-trader — GitOps deploy na kind-desktop

- ✅ **GitOps** `bakery-gitops` commit `a2047e3`: `stock-trader:local-jobs-v2`, `frontend-st:local-jobs-e432e10`, `SPRING_PROFILES_ACTIVE=local`
- ✅ **Argo** `stock-trader-grabit` Synced; POST job trigger s providerem **200** (dříve 403 CSRF)
- ✅ Provider override funguje i bez Redis (in-memory fallback)

Aktualizováno: [[entities/stock-trader-grabit]], tento log.
