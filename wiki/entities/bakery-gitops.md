---
title: bakery-gitops
type: entity
tags: [repo, gitops, argocd, applicationset]
created: 2026-07-08
updated: 2026-07-12
---

**GitOps** repozitář pro Bakery — odpovídá **Kytary.GitOps**. Argo CD root app syncuje tento repozitář; aplikace řídí **ApplicationSet**.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-gitops
- **Default branch**: `dev`
- **Local clone**: `<workspace>/bakery-gitops`

## Struktura (2026-07-08)

```
argocd/applicationset.yaml   # bakery-apps — local pilot, branch dev
clusters/hetzner-prod/       # prod overlay (ApplicationSet, branch main)
apps/fake-buster/
  app.json
  values.yaml
  values-hetzner-prod.yaml   # prod skeleton (CHANGE_ME)
apps/stock-trader-grabit/
  app.json
  values.yaml
  values-hetzner-prod.yaml
apps/bakery-onboarding/
  app.json
  manifests/
infra/fake-buster-db/        # CNPG db-init
infra/stock-trader-grabit-db/
infra/kafka/                 # Kafka StatefulSet + Service
infra/registry/              # ExternalName → host kind-registry (:5001) — pilot only
infra/monitoring/            # Prometheus/Loki/Grafana overlay + blackbox probes + disk-pressure mitigations
infra/pod-cleanup/           # CronJob — Succeeded/Failed pody (každých 10 min)
apps-registry.json
```

## ApplicationSet

**Pilot** (`argocd/applicationset.yaml`): jeden Application per `apps/*/app.json`, destination in-cluster, values `values.yaml`, branch `dev`.

**Prod** (`clusters/hetzner-prod/argocd/applicationset.yaml`): stejný generator, destination cluster `hetzner-prod`, values `values-hetzner-prod.yaml`, branch `main`. Aplikace pojmenované `*-hetzner-prod`.

## Deploy pravidlo

**Argo CD jediný deployer** — žádný ruční `helm upgrade`. Legacy helm release smazán (`cleanup-legacy-deploy.sh`).

## Pilot stav (2026-07-08)

- Argo: `bakery-gitops-root`, `fake-buster`, `stock-trader-grabit`, `bakery-onboarding` — **Synced / Healthy**
- Kafka: `bootstrapServers: kafka.infrastructure.svc.cluster.local:9092` v obou app values
- Keycloak URL: `https://keycloak.local.k8s.kytary.cz` + per-app realmy

## Monitoring overlay (Kytary `monitoring` NS)

`infra/monitoring/` — bakery scrape jobs, Grafana dashboardy, blackbox HTTP probes pro fronty.

**Kind DiskPressure mitigace** (2026-07-12):

| Artefakt | Účel |
|----------|------|
| `promtail-workers-only-patch.yaml` | Promtail jen na workerech (ne control-plane) |
| `monitoring-maintenance-cronjob.yaml` | Každých 15 min: udrží patch + smaže Failed pody v `monitoring` |
| `infra/pod-cleanup` | `bakery-pod-cleanup` každých **10 min** cluster-wide |

Host údržba: `task kind-disk-maintenance` v [[entities/bakery-platform]].

## Prod skeleton (2026-07-10) ⬜

- [[concepts/Hetzner prod skeleton]]
- `clusters/hetzner-prod/` — Argo overlay (ApplicationSet only)
- `values-hetzner-prod.yaml` per app

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake-buster]]
- [[entities/stock-trader-grabit]]
