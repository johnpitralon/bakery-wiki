---
title: stock-trader-grabit
type: entity
tags: [repo, app, pilot, trading]
created: 2026-07-08
updated: 2026-07-14
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

Argo Application `stock-trader-grabit`: **Synced / Healthy** (gitops `a2047e3`, 2026-07-14).

## Manuální joby + provider override (2026-07-14)

**Problém:** POST trigger z admin UI (`frontend-st` → Stock Trader) vracel **403 Access Denied** — `SPRING_PROFILES_ACTIVE=prod` zapínal CSRF, frontend posílá jen JWT Bearer. Provider override navíc selhával bez Redis.

**Opravy (lokální pilot kind-desktop):**
- Backend image `local-jobs-v2`: CSRF vypnuto pro `/api/**`, in-memory fallback pro provider override v `ProviderSwitchService`
- Admin UI image `local-jobs-e432e10`: manuální trigger i s provider dropdown, mapování jobů včetně Time Series UPSERT
- GitOps: `SPRING_PROFILES_ACTIVE=local` pro pilot (JWT API bez CSRF); tagy `local-jobs-v2` / `local-jobs-e432e10` v `localhost:5001` registry

**Ověření:** `POST /api/tickers/update?provider=Alpha%20Vantage` → **200**; log potvrzuje `Set provider override: Alpha Vantage`.

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

## GrabIt redesign — backend kontrakt detailu instrumentu (2026-07-13)

- Nový autentizovaný `GET /api/instruments/{symbol}/overview` vrací immutable typed DTO pro web a iOS; existující ticker/admin routy zůstávají beze změny.
- Zdroj dat je persistovaný `TickerEntity` a nejnovější dokončená daily candle. Její close je `previousClose` pro změnu živé ceny; jediný bar stačí pro OHLC/as-of, bez baru zůstávají hodnoty `null`.
- `dataFreshness` používá 15minutový práh nad timestampem zdroje a injektovaný `Clock`; přesně na hranici je `FRESH`, starší je `STALE`, chybějící nebo budoucí timestamp je `UNKNOWN`.
- Backend nemá autoritativní market calendar/status, proto kontrakt pravdivě vrací `marketStatus=UNKNOWN` a `marketStatusSource=UNAVAILABLE`.
- Chyby používají stabilní JSON `{error, message}` bez interních detailů; integrační security test potvrzuje, že `/api/**` vyžaduje autentizaci.
- Blocking JPA lookup se na hranici handleru přesouvá na Reactor `boundedElastic`; neočekávané chyby se logují se symbolem, zatímco odpověď zůstává sanitizovaná.
- Provider numeric sentinely se mapují na `null`; jiné malformed hodnoty logují symbol + field. Provider precision se zachovává, vypočtené procento používá šest míst `HALF_UP`.
- Defaultní UTC `Clock` je override-friendly přes `@ConditionalOnMissingBean`.
- TDD pokrytí: cílené testy 25/25, celý backend suite 178/178 PASS.

## GrabIt redesign — web detail a bezpečná objednávka (2026-07-13)

- Nová route `/instruments/[symbol]` používá typed overview, dokončená daily OHLCV data, watchlist a portfolio/positions; loading, 404, API error, partial, stale a empty stavy nevyrábějí náhradní finanční hodnoty.
- Graf nabízí pouze pravdivé rozsahy nad seřazenou denní historií (`1R`, `3R`, `5R`, `100R`) a má textový souhrn i rozbalitelnou OHLCV tabulku. Intraday ovládání, falešný `MAX`, placeholder ani dekorativní gradient se nezobrazují.
- Centralizovaná product policy povoluje STOCKS, ETFS, FOREX, INDICES, COMMODITIES a pouze Bitcoin z CRYPTO; ostatní typy se odfiltrují ze search/Markets a detail, trading i ticket je pravdivě odmítnou.
- Reusable `OrderTicket` podporuje jen BUY/SELL a MARKET/LIMIT, quantity nebo cash amount, striktní plain-decimal vstup s maximálně osmi desetinnými místy a skutečný fee endpoint. BUY kontroluje cash balance, SELL reálnou pozici.
- `CLOSED` blokuje přípravu objednávky; `UNKNOWN` je viditelně označený a vyžaduje explicitní potvrzení. Status se znovu kontroluje při confirmu. LIMIT simulační backend provádí okamžitě za zadanou limitní cenu.
- Odeslání je dvoukrokové: explicitní review a confirm; při potvrzení se znovu ověří podporovaný typ/symbol instrumentu, market status, čerstvá MARKET cena a poplatek. Duplicate submit je blokovaný a po úspěchu se invalidují portfolio, positions a trades.
- `/trading?symbol=...` bezpečně předvybere instrument a znovu používá `OrderTicket`; odstraněny STOP, SL/TP a placeholder intraday chart.
- Markets a `TickerSearch` navigují na URL-encoded detail symbolu; kategorie odpovídají podporovanému produktu a změna kategorie nepřepisuje aktivní search.
- Bezpečné API chyby preferují strukturovaný lidský `message`, poté strukturovaný `error`; plain-text backend body ani stack-like obsah se nezobrazí a historie použije pevný fallback.
- Web verifikace: Jest 130/130, TypeScript, Next production build a lint PASS.

## GrabIt redesign — iOS instrument hub (2026-07-14)

- `MarketsView` → `TickerDetailsView` → předvyplněný trade flow; stejný typed overview kontrakt jako web (`InstrumentOverview`, `InstrumentPolicy`).
- `GrabItAPI` filtruje podle `instrumentType`; `OrderEntryView` / `TradingView` sjednoceny s fee-aware objednávkou (MARKET/LIMIT, bez SL/TP/STOP).
- Design system: `GrabItTheme`, `GrabItPriceFormatter`, `PriceChange`; sdílené stavy loading/empty/stale/unsupported.
- Unit testy: `InstrumentPolicyTests`, `InstrumentOverviewDecodingTests`; `swift -frontend -parse` OK; plný `xcodebuild test` vyžaduje Xcode.app.

## GrabIt redesign — produktové plochy web (2026-07-14)

- Společná IA: **Domů · Objevovat · Obchodovat · Portfolio · Profil** (Czech labels v `Navigation`; `/instruments/*` pod Objevovat).
- Dashboard: skutečná hodnota portfolia, watchlist, pozice a omezené příležitosti z API; bez falešných performance grafů.
- Discovery (`/markets`): podporované kategorie, hledání, deep-link na detail; bez altcoinů/CFD placeholderů.
- Portfolio: pozice a historie z API, analýza tab s upřímným empty state; pozice/historie linkují na `/instruments/[symbol]`.
- Integrační security test overview: `@DynamicPropertySource` pinnuje HS256 secret (host `JWT_SECRET` env jinak přebíjí `application-test.properties`).

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
