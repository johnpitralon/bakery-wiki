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
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-gitops`

## Struktura (2026-07-08)

```
argocd/applicationset.yaml   # bakery-apps — git generator apps/*/app.json
apps/fake-buster/
  app.json                   # helm app metadata
  values.yaml                # deploy source of truth
apps/bakery-onboarding/
  app.json                   # manifests app
  manifests/
infra/fake-buster-db/        # db-init skeleton
infra/kafka/                 # placeholder
apps-registry.json           # lidský index → app.json
```

## ApplicationSet

Jeden Application per `apps/*/app.json` (Kytary-style):
- **helm** (`fake-buster`): multi-source — gitops values + `bakery-platform` chart
- **manifests** (`bakery-onboarding`): path `apps/bakery-onboarding/manifests`

Statické `application.yaml` CR **odstraněny** — generuje ApplicationSet.

## Deploy pravidlo

**Argo CD jediný deployer** — žádný ruční `helm upgrade`. Legacy helm release v `bakery-infrastructure` smazán (`cleanup-legacy-deploy.sh`).

## Pilot stav

- Argo: `bakery-gitops-root`, `fake-buster`, `bakery-onboarding` — **Synced / Healthy**
- Kafka v values: `bootstrapServers: ""` (vypnuto do infra/kafka)
- CI: `.github/workflows/validate.yml` (kustomize build)

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake_buster]]
