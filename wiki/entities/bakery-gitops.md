---
title: bakery-gitops
type: entity
tags: [repo, gitops, argocd]
created: 2026-07-08
updated: 2026-07-08
---

**GitOps** repozitář pro Bakery — odpovídá **Kytary.GitOps**. Argo CD root app (`bakery-gitops-root`) syncuje tento repozitář.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-gitops
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-gitops`

## Struktura

```
kustomization.yaml          # root (path .) — Argo root app
apps/fake-buster/           # Application + namespace + values
apps/bakery-onboarding/     # manifests (standalone Argo app)
infra/fake-buster-db/       # db-init Job skeleton
infra/kafka/                # placeholder (pilot: reuse broker)
apps-registry.json          # vstup pro budoucí ApplicationSet
```

## Pilot poznámky

- Root kustomization **neobsahuje** `apps/bakery-onboarding` — onboarding je samostatná Argo Application (vyhnutí se konfliktu namespace `bakery-agent-infra`).
- `fake-buster` Application může být single-source na `bakery-platform` chart + `deploy-values/fake-buster.yaml`.

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake_buster]]
