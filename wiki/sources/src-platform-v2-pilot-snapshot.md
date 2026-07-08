---
title: src-platform-v2-pilot-snapshot
type: source
tags: [source, pilot, platform-v2]
sources: [platform-v2-pilot-snapshot-2026-07-08.md]
created: 2026-07-08
updated: 2026-07-08
---

Shrnutí zdroje `raw/platform-v2-pilot-snapshot-2026-07-08.md` — počáteční ingest stavu Platform v2 pilotu.

## Klíčové body

- Čtyři nové repozitáře (platform, gitops, onboarding, wiki) + legacy service-bakery
- Pilot fake-buster na `kind-desktop` — **core služby Running**, Argo **Synced/Healthy**
- Helm release fake-buster: **deployed rev 15** (oprava po timeoutu rev 14)
- Sdílený CNPG Postgres z Kytary `infrastructure` namespace
- **Otevřené:** Kafka broker, legacy Argo app `service-bakery`, necommitnuté githooks/image-versions

## Propagace do wiki

Tento zdroj inicializoval / aktualizoval:
- [[overview]]
- [[entities/fake_buster]]
- [[entities/bakery-platform]]
- [[entities/bakery-gitops]]
- [[entities/bakery-onboarding]]
- [[entities/bakery-wiki]]
- [[concepts/Koexistence s Kytary]]
- [[concepts/LLM wiki maintenance]]

## Souvislosti

- [[log]]
- [[overview]]
