---
title: Přehled platformy
type: overview
tags: [overview, platform-v2]
sources: [platform-v2-pilot-snapshot-2026-07-08.md]
created: 2026-07-08
updated: 2026-07-08
---

**Bakery** je generická Kubernetes platforma pro deploy mikroservisních aplikací. Platform v2 nahrazuje monolit **[[entities/service-bakery]]** modelem ve stylu Kytary.

## Repozitáře

| Repo | Role |
|------|------|
| [[entities/bakery-platform]] | Bootstrap, chart, CI, image-versions |
| [[entities/bakery-gitops]] | GitOps + ApplicationSet |
| [[entities/bakery-onboarding]] | Onboard API (OWUI + MCP) |
| [[entities/bakery-wiki]] | LLM wiki — [[concepts/Wiki sync policy]] |
| [[entities/fake_buster]] | Pilotní app |

## Pilot kind-desktop (2026-07-08)

- fake-buster: **Running**, Argo **Synced/Healthy**
- ApplicationSet `bakery-apps` aktivní
- Argo jediný deployer (helm release legacy smazán)
- PR #1 merged ve všech bakery-* repech
- ⬜ Kafka (vypnuto v values), ⬜ fake_buster Spring 4.0.7 commit

## Architektura

```
App repo → service-ci → registry → gitops bump → Argo → K8s
Onboarding (OWUI/MCP) → PR do app + gitops
Wiki ← každá platformní změna ([[concepts/Wiki sync policy]])
```

## Souvislosti

- [[concepts/Platform v2]]
- [[concepts/GitOps workflow]]
- [[concepts/Service onboarding]]
- [[concepts/LLM wiki maintenance]]
