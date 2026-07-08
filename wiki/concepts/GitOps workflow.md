---
title: GitOps workflow
type: concept
tags: [gitops, argocd, deploy, applicationset]
created: 2026-07-08
updated: 2026-07-08
---

Deploy model Platform v2: **Argo CD** + [[entities/bakery-gitops]] — **jediný deployer**, žádný ruční helm.

## Root app

`bakery-gitops-root` (`bakery-platform/bootstrap/initial.sh`):
- Source: `bakery-gitops`, path `.`
- Syncuje ApplicationSet + namespace manifesty

## ApplicationSet `bakery-apps`

Generator: `apps/*/app.json` (Kytary-style).

| deployType | Příklad | Zdroje |
|------------|---------|--------|
| helm | fake-buster | gitops values + bakery-platform chart |
| manifests | bakery-onboarding | gitops path |

## App deploy (fake-buster)

- Values: `bakery-gitops/apps/fake-buster/values.yaml` (source of truth)
- Chart: `bakery-platform/charts/bakery-app`
- Argo multi-source přes ApplicationSet templatePatch

## CI → image tag (automatizace)

1. App změna → Argo Workflow `service-ci`
2. Push image do registry
3. `ci-build-from-catalog.sh --bump-gitops` nebo `bump-gitops-image-tag.sh`
4. Commit do gitops → Argo sync

## Anti-pattern (zakázáno)

- Ruční `helm upgrade` pro app deploy — konflikt s Argo
- Legacy Argo app `service-bakery` — smazána

## Git hooky

Kytary-style v `bakery-platform/templates/githooks/` — `task hooks-all`.

## Souvislosti

- [[entities/bakery-gitops]]
- [[entities/bakery-platform]]
- [[concepts/Platform v2]]
- [[concepts/Wiki sync policy]]
