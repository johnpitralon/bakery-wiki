---
title: GitOps workflow
type: concept
tags: [gitops, argocd, deploy]
created: 2026-07-08
updated: 2026-07-08
---

Deploy model Platform v2 přes **Argo CD** a repozitář [[entities/bakery-gitops]].

## Root app

`bakery-gitops-root` (vytvořen `bakery-platform/bootstrap/initial.sh`):
- Source: `bakery-gitops` repo, path `.`
- Syncuje Application CRs v `apps/*`

## App deploy (pilot fake-buster)

Varianta **single-source** (kvůli Argo multi-source problémům):
- Chart: `bakery-platform/charts/bakery-app`
- Values: `bakery-platform/deploy-values/fake-buster.yaml`

Alternativa: values pouze v gitops `apps/fake-buster/values.yaml`.

## CI → image tag

1. Změna v app repu → Argo Workflow `service-ci` (Maven/Node/Python/Kaniko)
2. Push image do registry
3. Bump tag v gitops values (ručně / budoucí automation)

## Git hooky (vývoj)

Kytary-style: `local/<user>/<slug>` → PR. Kanonické hooky v `bakery-platform/templates/githooks/`.

## Souvislosti

- [[entities/bakery-gitops]]
- [[entities/bakery-platform]]
- [[concepts/Platform v2]]
