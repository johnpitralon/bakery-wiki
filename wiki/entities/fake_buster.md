---
title: fake_buster
type: entity
tags: [repo, app, pilot, ml]
created: 2026-07-08
updated: 2026-07-08
---

Pilotní **aplikační** repozitář pro Platform v2 — detekce fake news (labeler, inference, db-writer, crawler, frontend).

## Repozitář

- **Local clone**: `<workspace>/fake_buster`
- **Bootstrap (legacy)**: `./deploy/run-bootstrap.sh` → **DEPRECATED**, nahrazeno GitOps

## Služby (pilot kind-desktop)

| Služba | Typ | Stav pilotu |
|--------|-----|-------------|
| labeler | Java | ✅ Running |
| inference | Java | ✅ Running |
| db-writer | Java | ✅ Running |
| frontend | React | ✅ Running (2 repliky) |
| crawler | Python CronJob | ✅ existuje |

## Konfigurace

- Secrets: `deploy/clusters/local/cluster.env` → `fake-buster-secrets` (apply z bakery-platform)
- CI katalog: `service-bakery.yaml`
- Deploy values (v2): `bakery-gitops/apps/fake-buster/values.yaml` + `bakery-platform/deploy-values/fake-buster.yaml`

## Infra závislosti (pilot)

- Postgres: CNPG `kytary-pg1-rw.infrastructure.svc.cluster.local`, DB `labeler_db`, user `labeler`
- Kafka: dočasně odkaz na `fake-buster-kafka.bakery-infrastructure` — **broker po migraci chybí** (⬜)
- Registry: `localhost:30501` (Kind)

## Souvislosti

- [[concepts/Koexistence s Kytary]]
- [[entities/bakery-gitops]]
- [[overview]]
