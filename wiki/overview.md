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
| [[entities/fake_buster]] | Pilotní app #1 (ML) |
| [[entities/stock-trader-grabit]] | Pilotní app #2 (trading) |

## Pilot kind-desktop (2026-07-08) — ✅ hotovo

| App | Argo | Login |
|-----|------|-------|
| fake-buster | Synced / Healthy | ✅ auth-proxy |
| stock-trader-grabit | Synced / Healthy | ✅ auth-proxy |

- ApplicationSet `bakery-apps` na větvi **`dev`**
- Argo jediný deployer (legacy helm smazán)
- Kafka v `infra/kafka`, registry `:5001`, Keycloak realmy bootstrap
- [[entities/service-bakery]] deprecated (tag `platform-v2-pilot-final`)

Runbook: `bakery-platform/docs/pilot-runbook.md`

## Architektura

```
App repo → service-ci → registry → gitops bump → Argo → K8s
Onboarding (OWUI/MCP) → PR do app + gitops
Wiki ← každá platformní změna ([[concepts/Wiki sync policy]])
```

## Souvislosti

- [[concepts/Platform v2]]
- [[concepts/GitOps workflow]]
- [[concepts/Koexistence s Kytary]]
- [[concepts/Service onboarding]]
- [[concepts/LLM wiki maintenance]]
