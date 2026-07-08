---
title: Přehled platformy
type: overview
tags: [overview, platform-v2]
sources: [platform-v2-pilot-snapshot-2026-07-08.md]
created: 2026-07-08
updated: 2026-07-08
---

**Bakery** je generická Kubernetes platforma pro deploy mikroservisních aplikací. Platform v2 nahrazuje monolit **[[entities/service-bakery]]** modelem ve stylu Kytary: oddělené repozitáře pro bootstrap, GitOps, onboarding a **[[entities/bakery-wiki|LLM wiki]]**.

## Cíl Platform v2

| Dříve (service-bakery) | Po migraci |
|------------------------|------------|
| Jeden repo (charts + ansible + onboarding) | `bakery-platform` + `bakery-gitops` + `bakery-onboarding` + `bakery-wiki` |
| `deploy/values.yaml` v app repu | `bakery-gitops/apps/<app>/values.yaml` |
| `run-bootstrap.sh` | `bootstrap/initial.sh` + Argo CD |
| Onboarding v platformě | Samostatné repo [[entities/bakery-onboarding]] |
| Dokumentace rozptýlená | [[entities/bakery-wiki]] (Obsidian + LLM) |

## Pilot (2026-07-08)

- Cluster: **kind-desktop** (koexistence s Kytary — viz [[concepts/Koexistence s Kytary]])
- App: **[[entities/fake_buster]]**
- Postgres: CNPG `kytary-pg1-rw.infrastructure.svc.cluster.local`
- Argo: `bakery-gitops-root`, `bakery-onboarding`, `fake-buster` — **Synced / Healthy** ✅
- Helm `fake-buster`: **deployed**, revize 15 ✅
- Otevřené: ⬜ Kafka broker, ⬜ deprecate Argo `service-bakery`, 🔄 githooks + image-versions lokálně

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

Wiki update: [[concepts/LLM wiki maintenance]] — `task wiki:update` nebo `/wiki-update`.

## Souvislosti

- [[concepts/Platform v2]]
- [[entities/bakery-platform]]
- [[entities/bakery-gitops]]
- [[entities/bakery-wiki]]
- [[concepts/Image versions]]
