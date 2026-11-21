---
title: bakery-platform
type: entity
tags: [repo, platform, bootstrap, helm, ci, githooks]
created: 2026-07-08
updated: 2026-11-21
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
| `scripts/kind-host-disk-maintenance.sh` | Docker disk prune + kubectl cleanup (Kind pilot) |
| `templates/githooks/` | Kytary-style git hooky |

## CI / vývoj

- `.github/workflows/ci.yml` — helm lint, bash syntax
- `task hooks` / `task hooks-all` — githooks do platform + gitops + onboarding + **multi-agent** + wiki
- `task kind-disk-maintenance` — pravidelná údržba Docker disku + evicted/failed podů na Kind
- `ci-build-from-catalog.sh --bump-gitops` — build + auto tag bump

## Změny pro personal-agents a bump skript (2026-11-21) 🔄

**PR #34 (otevřený) 🔄** — podpora aplikace [[entities/personal-agents]]:

- Chart `bakery-app`: generické `cronjobs: []` (`templates/cronjobs.yaml`, per-item `fullnameOverride`; `enabled: false` položku opravdu vypne).
- Chart `bakery-app`: `persistence: []` (`templates/pvc.yaml`).
- `scripts/apply-app-secrets.sh`: nová větev `personal-agents` (čte 7 klíčů z git-ignorovaného `deploy/clusters/local/cluster.env` app repa, vytvoří Secret `personal-agents-secrets`; bez DB, tedy bez db-init).
- `image-versions.env`: `PERSONAL_AGENTS_PYTHON_TAG=3.12-slim`.
- CI overlay `argo/workflows/overlays/personal-agents` (stejný vzor jako stock-trader-grabit: argo-ci SA/RBAC, WorkflowTemplate `service-ci`, maven cache PVC).
- Sekce v README. Renderování fake-buster a stock-trader-grabit se nemění.

**PR #35 (otevřený) 🔄** — oprava identity v `scripts/bump-gitops-image-tag.sh`: místo trvalého `git config user.name/user.email` se používá `git -c user.name=git-bump-tag -c user.email=git-bump-tag@local` jen pro commit a push; v klonu nezůstává lokální identita. Souvislost: incident v [[entities/bakery-gitops]] (2026-11-21).

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
- [[entities/personal-agents]]
