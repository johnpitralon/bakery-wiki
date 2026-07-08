# Pilot Platform v2 — snapshot stavu (2026-07-08)

Zdroj: migrace service-bakery → bakery-platform + bakery-gitops + bakery-onboarding.
Pilot app: fake_buster na Kind clusteru `kind-desktop` (koexistence s Kytary).

## Repozitáře

| Repo | GitHub | Role |
|------|--------|------|
| bakery-platform | johnpitralon/bakery-platform | bootstrap, bakery-app chart, CI, image-versions.env |
| bakery-gitops | johnpitralon/bakery-gitops | Argo CD manifests |
| bakery-onboarding | johnpitralon/bakery-onboarding | Go onboard API |
| bakery-wiki | johnpitralon/bakery-wiki | Obsidian + LLM wiki |
| fake_buster | (app) | pilot ML app |
| service-bakery | legacy | migrace pryč |

## Cluster kind-desktop (2026-07-08)

### Argo CD

- bakery-gitops-root: Synced / Healthy
- bakery-onboarding: Synced / Healthy
- fake-buster: Synced / Healthy
- service-bakery: Unknown / Healthy (legacy — deprecate)

### fake-buster namespace

Deployments Running:
- fake-buster-labeler 1/1
- fake-buster-inference 1/1
- fake-buster-db-writer 1/1
- fake-buster-frontend 2/2
- CronJob fake-buster-crawler existuje

### Helm

- Release `fake-buster` v `bakery-infrastructure`: **deployed**, revize 15
- Dříve failed rev 14 (db-writer rollout timeout) — opraveno re-upgrade

### Infra závislosti

- Postgres: CNPG `kytary-pg1-rw.infrastructure`, DB `labeler_db`, user `labeler`
- Kafka: broker po helm migraci chybí — bootstrapServers dočasně v values
- Registry: localhost:30501 — pilot používá kind load + IfNotPresent

## Lokální necommitnuté změny (k 2026-07-08)

- bakery-platform: githooks, image-versions (Go 1.26.4, Java 25, Spring 4.0.7)
- bakery-gitops: githooks, db-init postgres:18-alpine
- bakery-onboarding: githooks step, Dockerfile z image-versions
- fake_buster: parent pom Spring 4.0.7

## Otevřené úkoly

1. Deprecate / odstranit Argo app `service-bakery`
2. Obnovit Kafka v GitOps nebo upravit bootstrapServers
3. Commitnout githooks + image-versions do bakery-* rep
4. Migrovat stock-trader-grabit na v2
