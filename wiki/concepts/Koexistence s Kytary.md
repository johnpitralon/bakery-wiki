---
title: Koexistence s Kytary
type: concept
tags: [kind, pilot, infrastructure]
created: 2026-07-08
updated: 2026-07-08
---

Pilot **fake-buster** běží na stejném Kind clusteru **`kind-desktop`** jako Kytary stack — bez druhého Traefiku a bez duplicitního Postgresu.

## Sdílené

| Komponenta | Namespace | Poznámka |
|------------|-----------|----------|
| Traefik | `traefik` / ingress | jeden controller |
| CNPG Postgres | `infrastructure` | `kytary-pg1-rw` — DB `labeler_db` pro fake-buster |
| Argo CD | `argocd` | bakery Applications vedle kytary apps |
| Keycloak | `infrastructure` | realm fake-buster později |

## Oddělené (bakery)

| Komponenta | Namespace |
|------------|-----------|
| fake-buster služby | `fake-buster` |
| bakery-onboarding | `bakery-agent-infra` |
| Helm release metadata | `bakery-infrastructure` |

## Rizika / otevřené (2026-07-08)

- ⬜ Kafka — vypnuto v gitops values (`bootstrapServers: ""`) do `infra/kafka`
- ✅ ApplicationSet `bakery-apps` z `apps/*/app.json`
- ✅ Argo jediný deployer — legacy helm + `service-bakery` app smazány
- ⬜ Registry `localhost:30501` — `configure-kind-registry.sh` v bakery-platform

Detailní runbook: `service-bakery/docs/coexistence-kind.md` (technický zdroj).

## Souvislosti

- [[entities/fake_buster]]
- [[overview]]
