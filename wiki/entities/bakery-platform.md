---
title: bakery-platform
type: entity
tags: [repo, platform, bootstrap, helm, ci]
created: 2026-07-08
updated: 2026-07-08
---

Repozitář **infrastrukturního bootstrapu** Platform v2 — náhrada části monolitického [[entities/service-bakery]]. Odpovídá roli **Kytary.K8S.Infrastructure** (initial provisioning, ne GitOps obsah aplikací).

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-platform
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-platform`

## Obsah

| Path | Účel |
|------|------|
| `bootstrap/initial.sh` | Jednorázově: Argo `service-ci`, argo-ci RBAC, `bakery-gitops-root` |
| `charts/bakery-app/` | Generický Helm chart pro app mikroservisy |
| `deploy-values/<app>.yaml` | Values pro Argo single-source pilot |
| `argo/workflows/` | WorkflowTemplate `service-ci` |
| `image-versions.env` | **Single source of truth** pro image tagy a CI toolchains |
| `scripts/` | `apply-app-secrets.sh`, `ci-build-from-catalog.sh`, `build-onboarding-image.sh` |
| `templates/githooks/` | Kanonické git hooky (Kytary-style) |

## Lokální necommitnuté (2026-07-08)

- 🔄 Githooks (`templates/githooks/`, `scripts/refresh-githooks.sh`)
- 🔄 `image-versions.env` — Go 1.26.4, Java 25, Spring Boot 4.0.7, onboarding image vars
- 🔄 `docs/image-versions.md`, build skripty pro onboarding

## Bootstrap pořadí (pilot)

1. Kytary / Argo CD už běží na clusteru
2. `./bootstrap/initial.sh`
3. `./scripts/apply-app-secrets.sh <workspace>/fake_buster local`
4. Argo sync z [[entities/bakery-gitops]]

## Souvislosti

- [[concepts/Platform v2]]
- [[concepts/Image versions]]
- [[entities/bakery-gitops]]
- [[entities/fake_buster]]
