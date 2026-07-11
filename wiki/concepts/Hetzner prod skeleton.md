---
title: Hetzner prod skeleton
type: concept
tags: [production, hetzner, gitops, deploy]
sources: []
created: 2026-07-10
updated: 2026-07-10
---

Skeleton **produkčního** prostředí bakery na Hetzner Kubernetes — bez reálných secretů (`CHANGE_ME`), branch **`main`**, cluster **`hetzner-prod`**.

## Rozdíl oproti pilotu (kind-desktop)

| | Pilot | Hetzner prod |
|---|--------|--------------|
| Cluster | `kind-desktop` (sdílený s Kytary) | `hetzner-prod` (remote) |
| Git branch | `dev` | `main` |
| ApplicationSet | `argocd/applicationset.yaml` | `clusters/hetzner-prod/argocd/applicationset.yaml` |
| Helm values | `apps/<app>/values.yaml` | `apps/<app>/values-hetzner-prod.yaml` |
| App secrets | `deploy/clusters/local/cluster.env` | `deploy/clusters/hetzner-prod/cluster.env` |
| Registry | Kind host `:5001` | Externí (Harbor / GHCR / …) |
| Infra NS | Kytary `infrastructure` (read-only) | Vlastní `bakery-infrastructure` |

## GitOps layout

```
bakery-gitops/clusters/hetzner-prod/
  kustomization.yaml          # Argo path — jen ApplicationSet
  argocd/
    applicationset.yaml       # bakery-apps-hetzner-prod
    cluster-hetzner-prod.secret.example.yaml
```

Overlay **neobsahuje** `infra/*` (Kustomize omezení cest). CNPG db-init, Kafka atd. se aplikují zvlášť po `bootstrap/initial.sh`.

Argo aplikace: `fake-buster-hetzner-prod`, `stock-trader-grabit-hetzner-prod`, …

## App repa

Profil v každém app repu:

- `deploy/clusters/hetzner-prod/cluster.yaml`
- `deploy/clusters/hetzner-prod/cluster.env.example` → `cluster.env` (gitignored)

## Bootstrap pořadí (operátor)

1. Argo cluster secret `hetzner-prod` na management clusteru
2. `bootstrap/initial.sh` na Hetzner clusteru (`GITOPS_BRANCH=main`)
3. `kubectl apply -k clusters/hetzner-prod` (ApplicationSet)
4. Infra: `kubectl apply -k infra/...` per app
5. `apply-app-secrets.sh` + `ensure-keycloak-realm.sh` z app rep
6. CI build s `CLUSTER_NAME=hetzner-prod`

Runbook: `bakery-platform/docs/hetzner-prod-runbook.md`

## Stav

⬜ Skeleton v repu — **go-live až po doplnění** DNS, registry, DB, tokenů operátorem.

## Souvislosti

- [[concepts/Platform v2]]
- [[entities/bakery-gitops]]
- [[entities/bakery-platform]]
- [[concepts/Koexistence s Kytary]] (pilot — jiný cluster)
