---
title: bakery-gitops
type: entity
tags: [repo, gitops, argocd, applicationset]
created: 2026-07-08
updated: 2026-07-08
---

**GitOps** repozitář pro Bakery — odpovídá **Kytary.GitOps**. Argo CD root app syncuje tento repozitář; aplikace řídí **ApplicationSet**.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-gitops
- **Default branch**: `dev`
- **Local clone**: `<workspace>/bakery-gitops`

## Struktura (2026-07-08)

```
argocd/applicationset.yaml   # bakery-apps — git generator apps/*/app.json
apps/fake-buster/
  app.json
  values.yaml
apps/stock-trader-grabit/
  app.json
  values.yaml
apps/bakery-onboarding/
  app.json
  manifests/
infra/fake-buster-db/        # CNPG db-init
infra/stock-trader-grabit-db/
infra/kafka/                 # Kafka StatefulSet + Service
apps-registry.json
```

## ApplicationSet

Jeden Application per `apps/*/app.json` (Kytary-style):
- **helm** (`fake-buster`, `stock-trader-grabit`): multi-source — gitops values + `bakery-platform` chart
- **manifests** (`bakery-onboarding`): path `apps/bakery-onboarding/manifests`

## Deploy pravidlo

**Argo CD jediný deployer** — žádný ruční `helm upgrade`. Legacy helm release smazán (`cleanup-legacy-deploy.sh`).

## Pilot stav (2026-07-08)

- Argo: `bakery-gitops-root`, `fake-buster`, `stock-trader-grabit`, `bakery-onboarding` — **Synced / Healthy**
- Kafka: `bootstrapServers: kafka.infrastructure.svc.cluster.local:9092` v obou app values
- Keycloak URL: `https://keycloak.local.k8s.kytary.cz` + per-app realmy

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake_buster]]
- [[entities/stock-trader-grabit]]
