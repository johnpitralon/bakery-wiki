---
title: personal-agents
type: entity
tags: [app, cronjob, kind-desktop, onboarding]
sources: []
created: 2026-11-21
updated: 2026-11-21
---

Aplikace na Platform v2 (stav 🔄 onboarding na `kind-desktop`). Repo `johnpitralon/personal-agents` (privátní) je monorepo osobních jednoúčelových automatizačních agentů majitele.

## Obsah

- První agent `agents/dph` připravuje měsíční české DPH (DPHDP3 + kontrolní hlášení XML, xlsx, zip odeslaný majiteli e-mailem).
- Python 3.12 / uv. Používá lokální LLM přes LM Studio na Macu, z podů dostupné na `http://host.docker.internal:5665`.
- Tato stránka popisuje jen platformní a deployment tvar; žádná daňová data ani hodnoty secretů se do wiki nedávají.

## Deployment

- Cíl: cluster `kind-desktop`, namespace `personal-agents`, Kubernetes **CronJob** z chartu `bakery-app` (viz [[entities/bakery-platform]]). Větev app repa `dev` → kind; `main` zatím nenasazuje nikam.
- Image: per-app Argo CI CronWorkflow (kaniko → `localhost:5001`), poté bump `tag:` v `apps/personal-agents/values.yaml` v [[entities/bakery-gitops]].
- Secrets: k8s Secret `personal-agents-secrets` vytváří `bakery-platform/scripts/apply-app-secrets.sh <app_repo_path> local`; čte 7 klíčů z git-ignorovaného `deploy/clusters/local/cluster.env`. Bez DB, tedy bez db-init.
- Persistence: statický PV na `desktop-worker3` v `/persistent-data/personal-agents`, vlastník uid/gid 10001, storage class `local-static`, Retain.

## Registrace v bakery-gitops

Registrace (`apps/personal-agents/{app.json, values.yaml, namespace.yaml, pv.yaml, kustomization.yaml, ci-cronworkflow.yaml}`, `infra/registry/personal-agents-registry.yaml`, položky v `apps-registry.json` a root kustomization) **není v `dev`**: byla revertována po incidentu s identitou `git-bump-tag` (viz [[entities/bakery-gitops]]). Přistane znovu jako běžné PR.

## Stav

- 🔄 bakery-platform PR #34 (cronjobs, persistence, secrets arm, CI overlay) — otevřený
- 🔄 bakery-platform PR #35 (oprava identity v bump skriptu) — otevřený
- ✅ Incident v bakery-gitops vyřešen revertem (PR #23)
- ⬜ Merge PR #34 (app.json používá chartRevision `dev`, takže PR #34 musí být nejdřív v bakery-platform `dev`)
- ⬜ Příprava adresáře pro PV
- ⬜ `ensure-ci-prereqs.sh personal-agents` a `apply-app-secrets.sh`
- ⬜ Dockerfile v `dev` větvi personal-agents
- ⬜ Znovu zaregistrovat v bakery-gitops přes PR
