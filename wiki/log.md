---
title: Log
type: overview
tags: [log, meta]
created: 2026-07-08
updated: 2026-07-08
---

Chronologický záznam aktivit wiki — ingest, query, lint, údržba.

## [2026-07-08] init | Založení bakery-wiki

Vytvořeno repo **bakery-wiki** podle schématu [[Kytary.Wiki]] (Obsidian vault + `CLAUDE.md` schema + `raw/` + `wiki/`).

Počáteční obsah:
- Entity stránky pro Platform v2 repozitáře + `fake_buster` + legacy `service-bakery`
- Koncepty: Platform v2, GitOps, onboarding, koexistence s Kytary, image-versions
- Guardy proti natvrdo zadaným cestám v `wiki/*.md` (`.githooks/pre-commit`, `.claude/hooks/`)

Aktualizováno: [[index]], [[overview]], tento log.

## [2026-07-08] pilot | Platform v2 fake-buster na kind-desktop

Pilotní nasazení (shrnutí pro wiki — detail v app/cluster stavu):

- ✅ `bakery-platform` initial.sh — service-ci, gitops-root
- ✅ `bakery-onboarding` Running v `bakery-agent-infra`
- ✅ fake-buster pody: labeler, inference, db-writer, frontend (4/4 Running)
- 🔄 Argo `fake-buster` OutOfSync (values z bakery-platform deploy-values)
- 🔄 Helm release `failed` rev 14 (db-writer rollout timeout — pody OK)
- ⬜ Kafka — po helm upgrade chybí broker (dočasný bootstrapServers v values)
- ⬜ Githooky + image-versions změny — lokálně, necommitnuto (k 2026-07-08)

Viz [[entities/fake_buster]], [[concepts/Koexistence s Kytary]].
