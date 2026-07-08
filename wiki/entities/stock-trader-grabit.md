---
title: stock-trader-grabit
type: entity
tags: [repo, app, pilot, trading]
created: 2026-07-08
updated: 2026-07-08
sources: []
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
| grabit-web | React (Next.js) | ✅ Running |
| frontend-st | React (Next.js) | ✅ Running |

Argo Application `stock-trader-grabit`: **Synced / Healthy**.

## Platform v2 migrace (hotovo)

- ✅ ApplicationSet deploy z `dev` větve bakery-gitops
- ✅ CI `service-ci` v NS `stock-trader-grabit` + `ensure-ci-prereqs.sh`
- ✅ Keycloak realm `stock-trader-grabit` (`ensure-keycloak-realm.sh`)
- ✅ Auth-proxy routes v `frontend-st` a `grabit-web` (realm fix, ne legacy `service-bakery`)
- ✅ Login ověřen přes `frontend-st.localhost` a `grabit-web.localhost`

## ⚠️ Otevřené (app scope)

Backend (`JwtTokenProvider`) může stále validovat JWT přes HMAC místo Keycloak RS256/JWKS — autentizovaná `/api/**` volání mohou vracet **401** i když login UI funguje. Navržená oprava: JWKS z Keycloak realm endpointu.

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

## Souvislosti

- [[entities/bakery-gitops]], [[entities/bakery-platform]]
- [[concepts/GitOps workflow]], [[concepts/Koexistence s Kytary]]
