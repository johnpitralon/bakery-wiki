---
title: fake-buster
type: entity
tags: [repo, app, pilot, ml]
created: 2026-07-08
updated: 2026-07-12
sources: [platform-v2-pilot-snapshot-2026-07-08.md]
---

Pilotní **aplikační** repozitář pro Platform v2 — detekce fake news (labeler, inference, db-writer, crawler, frontend).

## Frontend

Jeden ML Next.js frontend — viz `fake-buster/docs/frontend-split-and-monitoring.md`:

| Host | Účel |
|------|------|
| `frontend.localhost` | ML labeling, crawler admin, monitoring |
| `labeler.localhost` / `inference.localhost` | Ingress aliasy → stejný frontend |

Stock Trader / GrabIt UI jsou v [[entities/stock-trader-grabit]].

## E2E smoke

Playwright sada `e2e/` — `task e2e`. Viz [[concepts/E2E smoke tests]].

## Repozitář

- **URL**: https://github.com/johnpitralon/fake-buster
- **Local clone**: `<workspace>/fake-buster`
- **Default branch**: `dev`
- **Deploy**: GitOps — legacy `./deploy/run-bootstrap.sh` **DEPRECATED**

## Služby (pilot kind-desktop, 2026-07-08)

| Služba | Typ | Stav pilotu |
|--------|-----|-------------|
| labeler | Java | ✅ Running |
| inference | Java | ✅ Running |
| db-writer | Java | ✅ Running |
| frontend | React | ✅ Running |
| crawler | Python CronJob | ✅ existuje |

Argo Application `fake-buster`: **Synced / Healthy**.

## Konfigurace

- Secrets: `deploy/clusters/local/cluster.env` → `apply-app-secrets.sh` z bakery-platform
- CI katalog: `service-bakery.yaml`
- Deploy values: `bakery-gitops/apps/fake-buster/values.yaml`

## Infra závislosti (pilot)

- Postgres: CNPG `kytary-pg1-rw.infrastructure.svc.cluster.local`, DB `labeler_db`
- Kafka: `kafka.infrastructure.svc.cluster.local:9092`
- Keycloak: realm `fake-buster`, frontend URL `https://keycloak.local.k8s.kytary.cz`
- Registry: `localhost:5001` (node pull) / `host.docker.internal:5001` (Kaniko push)

Login ověřen přes frontend auth-proxy.

## Souvislosti

- [[concepts/Koexistence s Kytary]]
- [[entities/bakery-gitops]]
- [[overview]]
