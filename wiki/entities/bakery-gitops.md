---
title: bakery-gitops
type: entity
tags: [repo, gitops, argocd, applicationset]
created: 2026-07-08
updated: 2026-10-26
---

**GitOps** repozitář pro Bakery — odpovídá **Kytary.GitOps**. Argo CD root app syncuje tento repozitář; aplikace řídí **ApplicationSet**.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-gitops
- **Default branch**: `dev`
- **Local clone**: `<workspace>/bakery-gitops`

## Struktura (2026-07-08)

```
argocd/applicationset.yaml   # bakery-apps — local pilot, branch dev
clusters/hetzner-prod/       # prod overlay (ApplicationSet, branch main)
apps/fake-buster/
  app.json
  values.yaml
  values-hetzner-prod.yaml   # prod skeleton (CHANGE_ME)
apps/stock-trader-grabit/
  app.json
  values.yaml
  values-hetzner-prod.yaml
apps/bakery-onboarding/
  app.json
  manifests/
infra/fake-buster-db/        # CNPG db-init
infra/stock-trader-grabit-db/
infra/kafka/                 # Kafka StatefulSet + Service
infra/registry/              # ExternalName → host kind-registry (:5001) — pilot only
infra/monitoring/            # Prometheus/Loki/Grafana overlay + blackbox probes + disk-pressure mitigations
infra/pod-cleanup/           # CronJob — Succeeded/Failed pody (každých 10 min)
apps-registry.json
```

## ApplicationSet

**Pilot** (`argocd/applicationset.yaml`): jeden Application per `apps/*/app.json`, destination in-cluster, values `values.yaml`, branch `dev`.

**Prod** (`clusters/hetzner-prod/argocd/applicationset.yaml`): stejný generator, destination cluster `hetzner-prod`, values `values-hetzner-prod.yaml`, branch `main`. Aplikace pojmenované `*-hetzner-prod`.

## Deploy pravidlo

**Argo CD jediný deployer** — žádný ruční `helm upgrade`. Legacy helm release smazán (`cleanup-legacy-deploy.sh`).

## Pilot stav (2026-07-08)

- Argo: `bakery-gitops-root`, `fake-buster`, `stock-trader-grabit`, `bakery-onboarding` — **Synced / Healthy**
- Kafka: `bootstrapServers: kafka.infrastructure.svc.cluster.local:9092` v obou app values
- Keycloak URL: `https://keycloak.local.k8s.kytary.cz` + per-app realmy

## Kafka: init chown na kind bind mountu (2026-10-26)

Incident a fix v `infra/kafka/kafka-statefulset.yaml` (commit `c72e431`, `fix(kafka): chown v init kontejneru best-effort (kind bind mount z macOS)`).

- **Příznak** (`kind-desktop`): `infrastructure/kafka-0` v `Init:CrashLoopBackOff`, 305+ restartů od 2026-10-25 10:34. Init kontejner `fix-data-permissions` (busybox:1.36, `runAsUser 0`) spouštěl `chown -R 1000:1000 /var/lib/kafka/data && chmod 755 ...` a padal na `chown: .../metadata/__cluster_metadata-0/*.checkpoint: Permission denied`.
- **Příčina**: PV Kafky (storage class `standard`, hostPath `/persistent-data/pvc-…_infrastructure_kafka-data-kafka-0` na nodu `desktop-worker2`) je na lokálním kindu bind mount z macOS (`<macOS home>/docker-persistent/worker2`) přes Docker Desktop file sharing. Soubory patří macOS uid 501 a root v kontejneru je nesmí přeowner-ovat.
- **Fix**: `chown` i `chmod` jsou best-effort (`chown … 2>/dev/null || echo 'fix-data-permissions: chown selhal …, pokračuji'; chmod … || true`). Kafka (uid 1000, `fsGroup 1000`) na tento share zapisuje i bez chown.

### Gotcha při rolloutu (bude se opakovat)

Deadlock: fix se nenasadí, dokud Kafka není healthy, a Kafka není healthy bez fixu.

1. Argo app `bakery-gitops-root` (automated, prune + selfHeal) měla od 2026-10-23 09:06 zaseknutou sync operaci „waiting for healthy state of apps/StatefulSet/kafka“, takže nikdy nevzala novou git revizi. Odblokování = ukončit operaci (bez `argocd` CLI):
   ```bash
   kubectl -n argocd patch application bakery-gitops-root --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}'
   ```
   Auto-sync pak aplikoval `c72e431`.
2. StatefulSet změnil template (`updateRevision`), ale rozbitý pod sám nevyměnil (známé chování StatefulSetu s podem, který nikdy nebyl Ready). Nutné ruční:
   ```bash
   kubectl -n infrastructure delete pod kafka-0
   ```

**Výsledek**: `kafka-0` 1/1 Running (načetl existující data), `bakery-gitops-root` Synced / Healthy. Dopad na [[entities/fake-buster]] (`db-writer`) viz tam. Zbytek: starý evicted pod `fake-buster-db-writer-…-fc5cf` (ContainerStatusUnknown, evikce kvůli ephemeral-storage pressure na nodu) je neškodný a lze ho smazat.

## Monitoring overlay (Kytary `monitoring` NS)

`infra/monitoring/` — bakery scrape jobs, Grafana dashboardy, blackbox HTTP probes pro fronty.

**Kind DiskPressure mitigace** (2026-07-12):

| Artefakt | Účel |
|----------|------|
| `promtail-workers-only-patch.yaml` | Promtail jen na workerech (ne control-plane) |
| `monitoring-maintenance-cronjob.yaml` | Každých 15 min: udrží patch + smaže Failed pody v `monitoring` |
| `infra/pod-cleanup` | `bakery-pod-cleanup` každých **10 min** cluster-wide |

Host údržba: `task kind-disk-maintenance` v [[entities/bakery-platform]].

## Prod skeleton (2026-07-10) ⬜

- [[concepts/Hetzner prod skeleton]]
- `clusters/hetzner-prod/` — Argo overlay (ApplicationSet only)
- `values-hetzner-prod.yaml` per app

## Souvislosti

- [[concepts/GitOps workflow]]
- [[entities/bakery-platform]]
- [[entities/fake-buster]]
- [[entities/stock-trader-grabit]]
