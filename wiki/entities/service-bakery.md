---
title: service-bakery
type: entity
tags: [repo, legacy, platform, archived]
created: 2026-07-08
updated: 2026-07-08
---

**Legacy** monolitická platforma — Helm chart `service-bakery`, Ansible, bootstrap skripty. **Decommissioned** po Platform v2 pilotu (viz [[concepts/Platform v2]]).

## Repozitář

- **Stav**: 🗄️ **ARCHIVED / smazán** (2026-07-08) — záloha u provozovatele
- **Poslední tag**: `platform-v2-pilot-final`
- **Náhrada**: [[entities/bakery-platform]], [[entities/bakery-gitops]], [[entities/bakery-onboarding]]
- **Argo CD**: legacy Application `service-bakery` — **smazána** ✅

> **Poznámka:** soubor `service-bakery.yaml` v app repech **zůstává** — je to CI katalog služeb, ne tento repozitář.

## Co se přesunulo

| service-bakery | Platform v2 |
|----------------|---------------|
| `charts/service-bakery` | `bakery-platform/charts/bakery-app` |
| `scripts/bootstrap/` | `bakery-platform/bootstrap/` |
| `services/go/onboarding` | `bakery-onboarding` |
| Argo apps v jednom repu | `bakery-gitops` |
| `image-versions.env` | `bakery-platform/image-versions.env` (kanonické) |

## Souvislosti

- [[concepts/Platform v2]]
- [[entities/bakery-platform]]
- [[overview]]
