---
title: E2E smoke tests
type: concept
tags: [e2e, playwright, testing, smoke]
sources: []
created: 2026-07-12
updated: 2026-07-12
---

# E2E smoke tests (Playwright)

Pilotní **browser smoke** sady v aplikačních repech — ne náhrada unit/integration testů, ale ověření nasazeného clusteru (`*.localhost`).

## Kde

| Repo | Cesta | Frontends |
|------|-------|-----------|
| `fake-buster` | `e2e/` | ML frontend (`frontend.localhost`, aliasy `labeler` / `inference`) |
| `stock-trader-grabit` | `e2e/` | `frontend-st`, `grabit-web` (+ alias `stock-trader.localhost`) |

## Spuštění

```bash
cd <workspace>/fake-buster && task e2e
cd <workspace>/stock-trader-grabit && task e2e
```

Vyžaduje běžící pilot (`kind-desktop`) a přístup k `https://*.localhost` (Playwright `ignoreHTTPSErrors`).

## Co pokrývá smoke

- **HTML shell** — title / ingress odpovídá správnému frontendu
- **Same-origin proxy** — `/api/*-proxy/*`, OIDC metadata přes `auth-proxy`
- **Login** — Keycloak password grant (`admin` / `admin123`) → dashboard (kde UI hydratuje)
- **Alias hosty** — legacy BE hosty míří na frontend ingress

## Proměnné

| Proměnná | Účel |
|----------|------|
| `E2E_BASE_URL` | fake-buster frontend (default `https://frontend.localhost`) |
| `E2E_FRONTEND_ST_URL` / `E2E_GRABIT_WEB_URL` | stock-trader-grabit |
| `E2E_USERNAME` / `E2E_PASSWORD` | Keycloak pilot účet |
| `E2E_SKIP_LOGIN` | přeskočí login flow |
| `E2E_SKIP_UI` | fake-buster — jen proxy + shell (při mismatched Next `_next/static` mezi replikami) |

## CI

`.github/workflows/e2e-smoke.yml` v obou app repech — **`workflow_dispatch` only** (GitHub runner nemá pilot cluster). PR checks zůstávají u Jest/Maven.

## Souvislost

- [[entities/fake-buster]] — GUI split, API proxy
- [[entities/stock-trader-grabit]] — tři frontends, CORS/proxy fix
- Unit testy: Jest (React), Maven (Java), pytest (crawler) — beze změny
