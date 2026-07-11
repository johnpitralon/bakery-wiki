---
title: Platform v2
type: concept
tags: [architecture, migration, kytary-style]
created: 2026-07-08
updated: 2026-07-10
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
5. **service-bakery deprecated** — nový vývoj jen v bakery-* repozitářích

## Pilot (2026-07-08) — ✅ dokončen

Oba pilotní app repa na `kind-desktop` vedle Kytary stacku:

- [[entities/fake_buster]] — ML fake news pipeline
- [[entities/stock-trader-grabit]] — trading + GrabIt Web

Sdílená infra: CNPG, Keycloak, Traefik, Argo CD. Bakery-owned: Kafka v `infra/kafka`.

Runbook: `bakery-platform/docs/pilot-runbook.md` (včetně hranic scope s Kytary).

## Produkce (Hetzner) — skeleton ⬜

Remote cluster `hetzner-prod`, branch `main`, placeholdery `CHANGE_ME`. Viz [[concepts/Hetzner prod skeleton]] a `bakery-platform/docs/hetzner-prod-runbook.md`.

## Souvislosti

- [[overview]]
- [[concepts/GitOps workflow]]
- [[concepts/Koexistence s Kytary]]
- [[entities/bakery-platform]]
