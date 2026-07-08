---
title: Koexistence s Kytary
type: concept
tags: [kind, pilot, infrastructure, scope]
created: 2026-07-08
updated: 2026-07-08
---

Pilot **Platform v2** běží na stejném Kind clusteru **`kind-desktop`** jako Kytary stack — bez druhého Traefiku a bez duplicitního Postgresu.

## Sdílené (read-only pro bakery)

| Komponenta | Namespace | Poznámka |
|------------|-----------|----------|
| Traefik | ingress | jeden controller |
| CNPG Postgres | `infrastructure` | `kytary-pg1-rw` — DB pro fake-buster i stock-trader-grabit |
| Argo CD | `argocd` | bakery Applications vedle kytary apps |
| Keycloak | `infrastructure` | sdílený broker; per-app realmy (`fake-buster`, `stock-trader-grabit`) |
| Redis | `infrastructure` | stock-trader-grabit |

Bakery **konzumuje**, nemění ani nemaže kytary infra.

## Oddělené (bakery)

| Komponenta | Namespace |
|------------|-----------|
| fake-buster služby | `fake-buster` |
| stock-trader-grabit služby | `stock-trader-grabit` |
| bakery-onboarding | dle gitops manifestů |
| Kafka (bakery-owned) | `infrastructure` — `kafka.infrastructure.svc.cluster.local:9092` |

## Hranice scope (bakery vs kytary)

Při údržbě clusteru **nikdy**:

- nemazat kytary Argo CD Applications (`kytary-*`, `keycloak-sync-feat-*`, `*-feat-*-local`)
- nemazat NS `infrastructure`, `infrastructure-feat-*`
- force-delete kytary preview apps kvůli pod pressure

Kytary feat preview apps (`Unknown`, `ImagePullBackOff`) jsou očekávané — řeší je kytary tým / jejich ApplicationSet TTL, ne bakery.

**Povolený bakery cleanup:** completed CI pody v `fake-buster` a `stock-trader-grabit`; legacy bakery helm přes `cleanup-legacy-deploy.sh`.

Detail: `bakery-platform/docs/pilot-runbook.md` (sekce *Sdílený cluster — hranice scope*).

## Pilot stav (2026-07-08)

- ✅ ApplicationSet `bakery-apps` z `apps/*/app.json` (větev `dev`)
- ✅ Argo jediný deployer — legacy helm + `service-bakery` app smazány
- ✅ Kafka `infra/kafka/` + obě app values wired
- ✅ Registry `localhost:5001` → `kind-registry:5000` (`configure-kind-registry.sh`)
- ✅ Keycloak realmy bootstrap (`ensure-keycloak-realm.sh`)
- ✅ fake-buster + stock-trader-grabit: **Synced / Healthy**

## Souvislosti

- [[entities/fake_buster]]
- [[entities/stock-trader-grabit]]
- [[overview]]
- [[concepts/GitOps workflow]]
