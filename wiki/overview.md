---
title: Přehled platformy
type: overview
tags: [overview, platform-v2]
created: 2026-07-08
updated: 2026-07-08
---

**Bakery** je generická Kubernetes platforma pro deploy mikroservisních aplikací. Platform v2 nahrazuje monolit **[[entities/service-bakery]]** modelem ve stylu Kytary: oddělené repozitáře pro bootstrap, GitOps a onboarding.

## Cíl Platform v2

| Dříve (service-bakery) | Po migraci |
|------------------------|------------|
| Jeden repo (charts + ansible + onboarding) | `bakery-platform` + `bakery-gitops` + `bakery-onboarding` |
| `deploy/values.yaml` v app repu | `bakery-gitops/apps/<app>/values.yaml` |
| `run-bootstrap.sh` | `bootstrap/initial.sh` + Argo CD |
| Onboarding v platformě | Samostatné repo [[entities/bakery-onboarding]] |

## Pilot (2026-07)

- Cluster: **kind-desktop** (koexistence s Kytary — viz [[concepts/Koexistence s Kytary]])
- App: **[[entities/fake_buster]]**
- Postgres: CNPG `kytary-pg1-rw.infrastructure.svc.cluster.local`
- Stav: core služby Running; Argo `fake-buster` OutOfSync; helm release `failed` (kosmetika)

## Architektura (zjednodušeně)

```
App repo (fake_buster)
  service-bakery.yaml  ──CI──► Argo Workflow service-ci
         │
         ▼
bakery-gitops ──Argo──► bakery-app chart (bakery-platform)
         │
         ▼
Kubernetes (fake-buster NS)
```

Onboarding nové služby: [[entities/bakery-onboarding]] → PR do app repa + [[entities/bakery-gitops]].

## Souvislosti

- [[concepts/Platform v2]]
- [[entities/bakery-platform]]
- [[entities/bakery-gitops]]
- [[concepts/Image versions]]
