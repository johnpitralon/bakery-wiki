---
title: bakery-onboarding
type: entity
tags: [repo, go, onboarding, bootstrap-tier]
created: 2026-07-08
updated: 2026-07-08
---

Go HTTP služba pro **onboardování nových mikroservis** do app repozitáře a [[entities/bakery-gitops]]. Zjednodušená varianta **Kytary.Onboarding** pro ekosystém johnpitralon / service-bakery.

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-onboarding
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-onboarding`
- **Go modul**: `github.com/johnpitralon/bakery-onboarding`

## API

- `POST /v1/onboard` — strukturovaný JSON (OpenWebUI tool)
- Health: `/healthz`, `/readyz`

## Pipeline (MVP)

`resolve` → `repo_create` → `deploy_scaffold` → `git_hooks` → `gitops_register`

Výstupy:
- Scaffold v app repu (`services/<lang>/<name>`)
- Zápis do `service-bakery.yaml`
- Zápis do `bakery-gitops/apps/<app>/values.yaml`
- 2× PR (app + gitops)

## Deploy

- Namespace pilotu: `bakery-agent-infra`
- Image tag z [[concepts/Image versions|image-versions.env]] (`BAKERY_ONBOARDING_DEPLOY_IMAGE`)
- Secret `bakery-onboarding-secrets` (`gh-token`) — z app `cluster.env`, ne v platformě

## Souvislosti

- [[concepts/Service onboarding]]
- [[entities/bakery-gitops]]
- [[entities/bakery-platform]]
