---
title: stock-trader-grabit
type: entity
tags: [repo, app, pilot, trading]
created: 2026-07-08
updated: 2026-07-13
sources: [stock-trader-grabit dev, bakery-platform dev, bakery-gitops dev]
---

**Aplikační** repozitář na Platform v2 — obchodní platforma (stock-trader backend, GrabIt Web, Admin frontend).

## Repozitář

- **Local clone**: `<workspace>/stock-trader-grabit`
- **Default branch**: `dev`
- **Deploy**: GitOps (`bakery-gitops/apps/stock-trader-grabit/`), legacy `run-bootstrap.sh` **DEPRECATED**

## Služby (pilot kind-desktop, 2026-07-08)

| Služba | Typ | Stav |
|--------|-----|------|
| stock-trader | Java (WebFlux) | ✅ Running |
| frontend-st | React (Next.js) | ✅ Running — launcher + `/stock-trader/*` admin |
| grabit-web | React (Next.js) | ✅ Running — trading UI; Profil → odkaz na frontend-st |

**GUI split (2026-07-12):** Stock Trader admin pouze ve frontend-st; fake-buster frontend = ML only. Cross-linky `NEXT_PUBLIC_FRONTEND_ST_URL` / `NEXT_PUBLIC_GRABIT_WEB_URL`.

Argo Application `stock-trader-grabit`: **Synced / Healthy**.

## Lokální pilot — CPU fix (2026-07-13)

Pod `stock-trader` žral **500m CPU** kvůli retry smyčkám: Massive WebSocket reconnect (~5 s) + Loki4j timeout stack trace.

**Opravy:**
- GitOps: `global.loki.enabled: false`, `STOCK_MULTI_PROVIDER_ENABLED=false`, `MASSIVE/FINNHUB_WEBSOCKET_AUTO_CONNECT=false`
- Kód (`8abe7e7`): WS exponential backoff, Loki appenders jen pod Spring profile `loki`
- Po deploy CPU ~80m idle (místo 500m limit)

## E2E smoke

Playwright sada `e2e/` (projekty `frontend-st`, `grabit-web`, `cross-host`) — `task e2e`. Viz [[concepts/E2E smoke tests]].

**Auth (2026-07-12):** `frontend-st` obnovuje Keycloak access token (TTL 5 min) před expirací — stejný vzor jako grabit-web.

## Plány dotažení (2026-07)

- ✅ **Plan 1** — grabit-web Trading/Markets + JWKS auth (`512bbbd`, `e21befc`)
- ✅ **Plan 2** — hygiena repa, Platform v2 docs, Node 20, demo credentials flag (`7871cea`, `433fe20`, `b738b4e`); gitops `NEXT_PUBLIC_SHOW_DEMO_CREDENTIALS=true` pro lokální pilot
- ✅ **Plan 3** — pin SHA tagů v gitops, CI IMAGE_TAG z HEAD, PR checks workflow (`.github/workflows/pr-checks.yml`)
- 🔄 **Plan 4** — TickerQueryService + TickerImportService extrakce, config hardening, trading tests (zbývá CompanyInfo/PriceHistory/Earnings)
- ✅ **Plán 5** — frontend-st Jest, Next.js 15, iOS Keycloak auth, iOS testy/logging/config (xcodebuild test čeká na plné Xcode)

## Platform v2 migrace (hotovo)

- ✅ ApplicationSet deploy z `dev` větve bakery-gitops
- ✅ CI `service-ci` v NS `stock-trader-grabit` + `ensure-ci-prereqs.sh`
- ✅ Keycloak realm `stock-trader-grabit` (`ensure-keycloak-realm.sh`)
- ✅ Auth-proxy routes v `frontend-st` a `grabit-web` (realm fix, ne legacy `service-bakery`)
- ✅ Login ověřen přes `frontend-st.localhost` a `grabit-web.localhost`

## Auth (Keycloak RS256 / JWKS) — hotovo

- ✅ `JwtTokenProvider` — dual mode: `JWT_JWKS_URI` → RS256 přes JWKS (`JwksKeyLocator`), jinak HS256 fallback
- ✅ GitOps env: `JWT_JWKS_URI` → `keycloak.infrastructure.svc.cluster.local:8080/.../certs`
- ✅ Deploy stock-trader image tag `e21befc` (commit `e21befc` na `dev`)
- ✅ E2E: token přes `grabit-web` auth-proxy → `/api/watchlist` a `/api/tickers` **200** (ne 401)

## ⚠️ Otevřené (infra / data)

- Flyway migrace neběžely automaticky při prvním deployi — jednorázově spuštěny v clusteru (2026-07-08). Dlouhodobě: platformní flyway job nebo Spring Flyway při startu ověřit v CI/E2E.
- Tickers vrací prázdné pole dokud nejsou seed data / provider API klíče v DB.

## Konfigurace

- Secrets: `deploy/clusters/local/cluster.env` → `apply-app-secrets.sh` (NS `stock-trader-grabit`)
- CI katalog: `service-bakery.yaml`
- Values: `bakery-gitops/apps/stock-trader-grabit/values.yaml`
- `KEYCLOAK_INTERNAL_URL` pro auth-proxy uvnitř clusteru

## Infra závislosti (pilot)

- Postgres: CNPG `kytary-pg1-rw.infrastructure.svc.cluster.local` (grabit_db, stock_trader_db)
- Kafka: `kafka.infrastructure.svc.cluster.local:9092`
- Redis: `redis.infrastructure.svc.cluster.local`
- Keycloak: realm `stock-trader-grabit`, host URL `https://keycloak.local.k8s.kytary.cz`
- Registry: `localhost:5001`

## Backend refactoring (Plán 4, 2026-07-10)

God class `TickerService` rozdělen na doménové služby v `service/ticker/` — veřejné API `TickerService` zůstává fasáda pro handlery/schedulery:

| Služba | Účel |
|--------|------|
| `TickerQueryService` | read/search, price history lookup |
| `TickerImportService` | listing sync, EODHD/popular import |
| `CompanyInfoService` | Alpha Vantage OVERVIEW, EODHD fundamentals |
| `PriceHistoryService` | daily time series import/UPSERT |
| `EarningsService` | earnings calendar, reported-earnings job |

`TickerService` ~1100 řádků (dříve ~4470); zbývá price update joby + international price v fasádě.

## iOS GrabIt (Plán 5, 2026-07-11)

| Oblast | Stav |
|--------|------|
| Keycloak auth + token refresh | ✅ Úloha 3 |
| `APIClient` failable init + `APIClientFactory` fallback | ✅ Úloha 4 |
| `AppLog` (`os.Logger`) místo `print()` | ✅ Úloha 4 |
| `Info.plist` — `AuthAPIURL`, `StockTraderAPIURL`, `KeycloakRealm` | ✅ Úloha 4 |
| Unit testy `GrabItTests` (APIClient, AuthService, TokenStorage) | ✅ připraveno; `xcodebuild test` vyžaduje plné Xcode |
| Simulátor defaults | Keycloak `http://localhost:30084`, API `https://stock-trader.localhost` |

## Otevřené body (mimo Plán 5)

- ✅ Portfolio `/api/trading/portfolio` 500 — fix `TradingService` (`43644ad`, `4808c25`), nasazeno v clusteru (`gitops` `b701745`)
- `xcodebuild test` (iOS) — vyžaduje plné Xcode
- bakery-platform PR #13 — merge čeká na approval
- Plán 4 backend refactoring — rozpracovaný

## Souvislosti

- [[entities/bakery-gitops]], [[entities/bakery-platform]]
- [[concepts/GitOps workflow]], [[concepts/Koexistence s Kytary]]
