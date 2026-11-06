---
title: Wiki sync policy
type: concept
tags: [wiki, process, meta]
created: 2026-07-08
updated: 2026-11-06
---

**Povinné pravidlo:** každá smysluplná změna v bakery ekosystému se **projeví v [[entities/bakery-wiki]]** ve stejné session (ne až „někdy“).

## Kdy aktualizovat wiki

| Událost | Co v wiki |
|---------|----------|
| Nový rep / služba / koncept | entity nebo concept stránka |
| Změna deploy modelu, Argo, CI | [[concepts/GitOps workflow]], entity rep |
| Pilot / cluster stav | [[overview]], [[entities/fake-buster]], [[log]] |
| Onboarding / MCP / LLM integrace | [[concepts/Service onboarding]], [[entities/bakery-onboarding]] |
| Rozhodnutí (proč, ne jen co) | příslušný concept + append [[log]] |

## Kdo to dělá

- **LLM agent** pracující v `bakery-platform`, `bakery-gitops`, `bakery-onboarding`, app repech — před ukončením úkolu
- **Člověk** — po merge PR, pokud agent wiki neaktualizoval

## Minimální checklist (každá změna)

1. Relevantní stránky v `wiki/entities/` nebo `wiki/concepts/`
2. `wiki/index.md` — pokud nová stránka
3. **Append** do `wiki/log.md` (datum + co + které stránky)
4. `updated:` ve frontmatter
5. Žádné absolutní cesty v `wiki/*.md`
6. Commit na `dev`: agent použije explicitní `git add <cesty>` (nikdy `-A`) + `git commit`, push udělá `.githooks/post-commit`. `./scripts/wiki-commit-push.sh` (`git add -A`, nebo `task wiki:finish`) zůstává jen pro pipeline s lokálním modelem.

Vypnutí: `WIKI_AUTO_COMMIT=false` nebo `WIKI_AUTO_PUSH=false`.

## Vynucení hooky (bakery-sync)

Od 2026-11-06 policy vynucují hooky `tools/bakery-sync/` (Claude Code, Codex, Cursor):

- **session-start** — zaznamená začátek session, samo aktualizuje hooky, varuje před zastaralou instalací a u nového repa se jednorázově zeptá, zda zapnout sync
- **touched** — po každé editaci zapíše, které soubory session změnila
- **stop** — pokud session editovala zdroje a wiki ne, připomene update, pak commit a push
  (selhaný auto-push ohlásí také Stop hook)
- **ack** (`bakery-sync-ack.sh <session_id>`) — změna wiki nepotřebuje, umlčí aktuální stav
- **delegated** (`bakery-sync-delegated.sh <session_id>`) — wiki píše subagent na pozadí, Stop hook mlčí

Zapnutí: **marker** `.git/info/bakery-sync` v klonu (`bakery-sync-optin.sh on`, nic se necommituje)
nebo **spínač** — sekce `## Bakery Wiki sync (blocking rule)` v `CLAUDE.md`/`AGENTS.md`.
Marker má přednost. Stav: bakery-gitops, bakery-onboarding, bakery-platform, fake-buster,
stock-trader-grabit jsou zapnuté markerem; bakery-wiki spínačem.
Klon `bakery-multi-agent-platform` je neaktuální a bakery-sync je v něm vypnutý (marker `off`); naklonuje se znovu, až bude hotová multi-agent platforma z Kytary workspace, a nový klon dostane obvyklou jednorázovou otázku.
Nové repo v org `johnpitralon` dostane při startu session jednorázovou otázku.

**Proč odděleně od Kytary:** na stejném stroji běží hooky Kytary.Wiki (`~/.wiki-sync`).
Kdyby sdílely marker či spínač, bakery znalosti by končily ve firemní wiki; uninstall Kytary
navíc maže registrace s `wiki-sync-`. Bakery proto má vlastní `~/.bakery-sync`,
`.git/info/bakery-sync`, spínač a skripty `bakery-sync-*.sh`; viz [[concepts/Koexistence s Kytary]].
Instalace: `bash tools/bakery-sync/install.sh` jednou z hlavního klonu, pak se hooky samy aktualizují.

## Jak spustit

```bash
cd <workspace>/bakery-wiki
task wiki:update    # nebo /wiki-update v IDE
```

Viz [[concepts/LLM wiki maintenance]].

## Proč

Wiki je **jediný znalostní graf** Platform v2 — bez sync driftuje od kódu a pilot runbooků.

## Souvislosti

- [[entities/bakery-wiki]]
- [[concepts/LLM wiki maintenance]]
- [[log]]
