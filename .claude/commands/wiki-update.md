---
description: Aktualizuj bakery-wiki podle aktuálního stavu (snapshot + wiki graf)
---

Spusť workflow wiki update pro Bakery platformu.

1. Přečti `CLAUDE.md`, `AGENTS.md` a `WIKI_UPDATE.md` v kořeni bakery-wiki.
2. Pokud neexistuje `.wiki-update-request`, spusť `./scripts/trigger-wiki-update.sh update`.
3. Přečti `.wiki-update-request` a uvedený `raw/auto-snapshot-*.md`.
4. Aktualizuj relevantní stránky v `wiki/` (entity, concepts, overview).
5. Aktualizuj `wiki/index.md` a append do `wiki/log.md`.
6. Dodrž pravidla: žádné absolutní cesty v `wiki/*.md`, čeština + anglické tech termíny.
7. Po dokončení smaž `.wiki-update-request`.
8. **Povinně** spusť `./scripts/wiki-commit-push.sh` (auto commit + push na origin).
9. Shrň změny v 3–5 bodech.
