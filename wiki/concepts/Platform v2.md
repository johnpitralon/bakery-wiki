---
title: Platform v2
type: concept
tags: [architecture, migration, kytary-style]
created: 2026-07-08
updated: 2026-07-08
---

Rozdělení monolitické platformy [[entities/service-bakery]] do čtyř rolí — analogie k Kytary stacku (Infrastructure + GitOps + Onboarding + app repa).

## Mapování

| Kytary | Bakery v2 |
|--------|-----------|
| Kytary.K8S.Infrastructure | [[entities/bakery-platform]] |
| Kytary.GitOps | [[entities/bakery-gitops]] |
| Kytary.Onboarding | [[entities/bakery-onboarding]] |
| StockBass / app repa | `fake_buster`, `stock-trader-grabit`, … |

## Principy

1. **Bakery je generická** — žádné hardcodované app repa v platformě
2. **Secrets v app repu** — `cluster.env`, ne v bakery-platform
3. **Verze imagí** — `bakery-platform/image-versions.env` (rule #9)
4. **GitOps jako source of truth** pro deploy stav clusteru
5. **service-bakery se po migraci zahodí** — neudržovat paralelně

## Pilot

První app: [[entities/fake_buster]] na `kind-desktop`. Stav 2026-07-08: core služby Running, Argo Synced.

Runbook: `bakery-platform/docs/pilot-runbook.md` (technický; tato wiki = znalostní graf).
Wiki update: [[concepts/LLM wiki maintenance]].

## Souvislosti

- [[overview]]
- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
