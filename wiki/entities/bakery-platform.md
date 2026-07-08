---
title: bakery-platform
type: entity
tags: [repo, platform, bootstrap, helm, ci, githooks]
created: 2026-07-08
updated: 2026-07-08
---

Repozitář **infrastrukturního bootstrapu** Platform v2 — náhrada části [[entities/service-bakery]]. Role **Kytary.K8S.Infrastructure**.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-platform
- **Default branch**: `main` (PR #1 merged 2026-07-08)
- **Local clone**: `<workspace>/bakery-platform`

## Obsah

| Path | Účel |
|------|------|
| `bootstrap/initial.sh` | Argo `service-ci`, argo-ci RBAC, `bakery-gitops-root` |
| `charts/bakery-app/` | Generický Helm chart |
| `deploy-values/<app>.yaml` | Reference/template (kanonické values v gitops) |
| `argo/workflows/` | WorkflowTemplate `service-ci` |
| `image-versions.env` | Single source of truth pro image tagy |
| `scripts/bump-gitops-image-tag.sh` | CI → commit tagu do bakery-gitops |
| `scripts/cleanup-legacy-deploy.sh` | Odstranění helm release + legacy Argo app |
| `scripts/utils/configure-kind-registry.sh` | Kind containerd pro registry pull |
| `templates/githooks/` | Kytary-style git hooky |

## CI / vývoj

- `.github/workflows/ci.yml` — helm lint, bash syntax
- `task hooks-all` — githooks do platform + gitops + onboarding
- `ci-build-from-catalog.sh --bump-gitops` — build + auto tag bump

## Bootstrap pořadí

1. Kytary / Argo CD na clusteru
2. `./bootstrap/initial.sh`
3. `./scripts/apply-app-secrets.sh <workspace>/fake_buster local`
4. `./scripts/utils/configure-kind-registry.sh`
5. Argo sync [[entities/bakery-gitops]]

## Souvislosti

- [[concepts/Platform v2]]
- [[concepts/Image versions]]
- [[concepts/GitOps workflow]]
- [[entities/bakery-gitops]]
