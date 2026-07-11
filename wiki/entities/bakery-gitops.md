---
title: bakery-gitops
type: entity
tags: [repo, gitops, argocd, applicationset]
created: 2026-07-08
updated: 2026-07-10
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
infra/pod-cleanup/           # CronJob — Succeeded/Failed pody (každých 30 min)
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

## Prod skeleton (2026-07-10) ⬜

- [[concepts/Hetzner prod skeleton]]
- `clusters/hetzner-prod/` — Argo overlay (ApplicationSet only)
- `values-hetzner-prod.yaml` per app

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake_buster]]
- [[entities/stock-trader-grabit]]
