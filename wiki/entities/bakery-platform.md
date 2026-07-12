---
title: bakery-platform
type: entity
tags: [repo, platform, bootstrap, helm, ci, githooks]
created: 2026-07-08
updated: 2026-07-12
---

Repozitář **infrastrukturního bootstrapu** Platform v2 — náhrada části [[entities/service-bakery]]. Role **Kytary.K8S.Infrastructure**.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-platform
- **Default branch**: `dev` (`main` = release)
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
| `scripts/ensure-ci-prereqs.sh` | Secrets + maven PVC pro CI v app NS |
| `scripts/ensure-keycloak-realm.sh` | Realm + uživatelé z cluster.env |
| `scripts/utils/ensure-kind-registry-host.sh` | Host Docker `kind-registry` + persist `~/docker-persistent/worker1/registry` |
| `scripts/utils/configure-kind-registry.sh` | Kind containerd pro registry pull |
| `docs/pilot-runbook.md` | Pilot runbook včetně scope hranic s Kytary |
| `templates/githooks/` | Kytary-style git hooky |

## CI / vývoj

- `.github/workflows/ci.yml` — helm lint, bash syntax
- `task hooks` / `task hooks-all` — githooks do platform + gitops + onboarding + **multi-agent** + wiki
- `ci-build-from-catalog.sh --bump-gitops` — build + auto tag bump

## Bootstrap pořadí

1. Kytary / Argo CD na clusteru
2. `./bootstrap/initial.sh`
3. `./scripts/apply-app-secrets.sh <app-repo> local`
4. `./scripts/ensure-keycloak-realm.sh <app-repo> local`
5. `./scripts/utils/ensure-kind-registry-host.sh` + `./scripts/utils/configure-kind-registry.sh` (nebo `task kind-registry`)
6. Argo sync [[entities/bakery-gitops]]

## Souvislosti

- [[concepts/Platform v2]]
- [[concepts/Image versions]]
- [[concepts/GitOps workflow]]
- [[entities/bakery-gitops]]
