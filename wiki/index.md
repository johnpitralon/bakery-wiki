---
title: Index
type: overview
tags: [index, meta]
created: 2026-07-08
updated: 2026-07-08
---

Katalog stránek wiki. LLM čte tento soubor jako první při dotazech.

## Přehled

- [[overview|Přehled platformy]] — Platform v2, repozitáře, pilot fake-buster

## Entity (repozitáře & systémy)

| Stránka | Popis |
|---------|-------|
| [[entities/bakery-platform]] | Bootstrap, `bakery-app` chart, CI, `image-versions.env` |
| [[entities/bakery-gitops]] | Argo CD root app, app manifests, infra skeleton |
| [[entities/bakery-onboarding]] | Go HTTP `/v1/onboard` — scaffold + gitops registrace |
| [[entities/service-bakery]] | Legacy monolitická platforma (migrace pryč) |
| [[entities/fake_buster]] | Pilotní app — labeler, inference, db-writer, frontend, crawler |

## Koncepty

| Stránka | Popis |
|---------|-------|
| [[concepts/Platform v2]] | Rozdělení platformy na 4 repozitáře (Kytary-style) |
| [[concepts/GitOps workflow]] | Argo CD, bakery-gitops-root, app Applications |
| [[concepts/Service onboarding]] | bakery-onboarding pipeline a artefakty |
| [[concepts/Koexistence s Kytary]] | Kind `kind-desktop`, sdílený `infrastructure` NS |
| [[concepts/Image versions]] | `image-versions.env` jako single source of truth |

## Zdroje

| Stránka | Typ | Datum |
|---------|-----|-------|
| *(zatím prázdné — drop do `raw/`)* | | |

## Meta

- [[log|Log aktivit]]
