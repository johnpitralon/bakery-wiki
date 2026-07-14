---
title: Index
type: overview
tags: [index, meta]
created: 2026-07-08
updated: 2026-07-14
---

Katalog stránek wiki. LLM čte tento soubor jako první při dotazech.

## Přehled

- [[overview|Přehled platformy]] — Platform v2, repozitáře, pilot fake-buster + stock-trader-grabit ✅

## Entity (repozitáře & systémy)

| Stránka | Popis |
|---------|-------|
| [[entities/bakery-platform]] | Bootstrap, `bakery-app` chart, CI, `image-versions.env` |
| [[entities/bakery-gitops]] | Argo CD root app, app manifests, infra skeleton |
| [[entities/bakery-onboarding]] | Go HTTP `/v1/onboard` — scaffold + gitops registrace |
| [[entities/bakery-wiki]] | Obsidian vault + LLM wiki (tento repozitář) |
| [[entities/service-bakery]] | Legacy monolitická platforma (migrace pryč) |
| [[entities/fake-buster]] | Pilotní app — labeler, inference, db-writer, frontend, crawler |
| [[entities/stock-trader-grabit]] | App — stock-trader, grabit-web, frontend-st; typed instrument API, centrální product policy, web detail a bezpečný OrderTicket (pilot v2) |

## Koncepty

| Stránka | Popis |
|---------|-------|
| [[concepts/Platform v2]] | Rozdělení platformy na 4+ repozitáře (Kytary-style) |
| [[concepts/Hetzner prod skeleton]] | Prod cluster `hetzner-prod` — skeleton, branch `main`, `CHANGE_ME` |
| [[concepts/GitOps workflow]] | Argo CD, bakery-gitops-root, app Applications |
| [[concepts/Service onboarding]] | bakery-onboarding pipeline a artefakty |
| [[concepts/Koexistence s Kytary]] | Kind `kind-desktop`, sdílený `infrastructure` NS, **scope hranice** |
| [[concepts/Image versions]] | `image-versions.env` jako single source of truth |
| [[concepts/LLM wiki maintenance]] | Trigger pro update wiki (libovolné LLM) |
| [[concepts/Wiki sync policy]] | **Povinně** — wiki po každé platformní změně |
| [[concepts/E2E smoke tests]] | Playwright smoke v app repech (`task e2e`) |

## Zdroje

| Stránka | Typ | Datum |
|---------|-----|-------|
| [[sources/src-platform-v2-pilot-snapshot]] | pilot snapshot | 2026-07-08 |
| `raw/auto-snapshot-*.md` | auto (trigger skript) | průběžně |

## Meta

- [[log|Log aktivit]]

## Trigger (LLM — IDE i lokální)

```bash
task wiki:update      # příprava
task wiki:aider       # lokální model
task wiki:finish      # commit + push po agent update
```

Viz [[concepts/LLM wiki maintenance]], [[concepts/Wiki sync policy]].
