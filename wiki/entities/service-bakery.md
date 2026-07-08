---
title: service-bakery
type: entity
tags: [repo, legacy, platform]
created: 2026-07-08
updated: 2026-07-08
---

**Legacy** monolitická platforma — Helm chart `service-bakery`, Ansible, bootstrap skripty, onboarding v `services/go/onboarding`. **Deprecated** po dokončení Platform v2 pilotu (viz [[concepts/Platform v2]]).

## Repozitář

- **Local clone**: `<workspace>/service-bakery`
- **Stav**: 🛑 **DEPRECATED** — `.DO_NOT_USE`, README banner, tag `platform-v2-pilot-final`
- **Argo CD**: legacy Application `service-bakery` — **smazána** ✅

## Co se přesouvá

| service-bakery | Platform v2 |
|----------------|---------------|
| `charts/service-bakery` | `bakery-platform/charts/bakery-app` |
| `scripts/bootstrap/` | `bakery-platform/bootstrap/` |
| `services/go/onboarding` | `bakery-onboarding` |
| Argo apps v jednom repu | `bakery-gitops` |
| `image-versions.env` | `bakery-platform/image-versions.env` (kanonické) |

## Pravidla (platí i pro migraci)

- Nikdy `kubectl delete pv`
- Secrets v app `cluster.env`, ne v bakery-platform
- MD dokumentace → `docs/` (nebo tato wiki)

## Souvislosti

- [[concepts/Platform v2]]
- [[entities/bakery-platform]]
- [[overview]]
