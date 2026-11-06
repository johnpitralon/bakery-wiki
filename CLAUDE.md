# Bakery Platform — LLM Wiki Schema

> **Kanonické instrukce:** [`AGENTS.md`](AGENTS.md) — čti nejdřív tam.
> Tento soubor = schéma vaultu (struktura, konvence, pravidla).

## Project context

**Bakery** is a generic Kubernetes platform for deploying microservice apps (fake-buster, stock-trader-grabit, …). Platform v2 splits the monolithic **service-bakery** into:

| Repo | Role |
|------|------|
| **bakery-platform** | Initial bootstrap, `bakery-app` Helm chart, CI, `image-versions.env` |
| **bakery-gitops** | Argo CD apps, values, infra addons |
| **bakery-onboarding** | Go HTTP service — onboard new services into app + gitops repos |
| **bakery-wiki** | Obsidian + LLM wiki |
| **App repos** | Application code + `service-bakery.yaml` + `deploy/clusters/` |

Pilot: **fake-buster** on Kind cluster `kind-desktop` coexisting with **Kytary** stack (`infrastructure` namespace).

## Directory structure

```
bakery-wiki/
├── AGENTS.md              ← kanonické instrukce pro všechna LLM
├── WIKI_UPDATE.md         ← krátký prompt / task příkazy
├── CLAUDE.md              ← tento soubor (schéma vaultu)
├── scripts/
│   ├── trigger-wiki-update.sh
│   ├── wiki-update-aider.sh   ← lokální modely (doporučeno)
│   └── run-wiki-update-local.sh  ← fallback (API + apply)
├── raw/                   ← source documents (immutable, LLM never modifies)
│   └── auto-snapshot-latest.md
├── tools/
│   ├── wiki-query.py          ← search / section / related (retrieval)
│   ├── wiki_index.py, wiki_search.py  ← index builder + ranking
│   ├── wiki-integrity-check.py  ← read-only kontrola vaultu
│   ├── tests/                 ← testy retrievalu a integrity checkeru
│   └── bakery-sync/           ← hooky pro synchronizaci wiki (viz níže)
├── .cache/                ← odvozený index (gitignored, staví se z manifestu)
├── wiki/                  ← LLM-maintained wiki
│   ├── index.md
│   ├── log.md
│   ├── overview.md
│   ├── sources/
│   ├── entities/
│   └── concepts/
└── triggers/              ← local-models.env, out/
```

## Page conventions

### Frontmatter (YAML)

Every wiki page MUST have frontmatter:

```yaml
---
title: Page Title
type: entity | concept | domain | source | overview
tags: [relevant, tags]
sources: []
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

### Linking

- Use Obsidian wiki links: `[[Page Name]]` or `[[path/to/page|Display Text]]`
- Entity names: match repo names (`bakery-platform`, `fake-buster`)

### Language

- Write in **Czech** for prose; technical terms in English
- **Never hardcode absolute paths** in `wiki/*.md` — use `<workspace>/<repo>`

## Workflows

Viz `AGENTS.md` — ingest, update, lint.

### Query (otázka → odpověď)

Postup převzatý z Kytary.Wiki; v bakery-wiki není měřený (žádný eval).

1. LLM **MUSÍ nejdřív** spustit `python3 tools/wiki-query.py search "<dotaz>"` a najít kandidátní stránky a sekce.
2. Potom **MUSÍ** číst jen nalezenou sekci: `python3 tools/wiki-query.py section <cesta> <nadpis>`. Celou stránku nečíst jako běžný zdroj odpovědi.
3. `python3 tools/wiki-query.py related <cesta>` jen když je pro odpověď doloženě potřeba další kontext.
4. `wiki/index.md` číst přímo jen jako fallback, když nástroj nebo Python nejsou dostupné.
5. Znovupoužitelnou odpověď (srovnání, rozhodnutí) založ jako novou stránku a aktualizuj index i log.

### Kontrola integrity

```bash
python3 tools/wiki-integrity-check.py          # read-only, bez sítě
python3 tools/wiki_index.py --force            # přestaví index do .cache/
bash tools/tests/wiki-integrity-check.test.sh
bash tools/tests/wiki-query-contract.test.sh
bash tools/tests/wiki-index.test.sh
```

`.githooks/pre-commit` při staged `wiki/*.md` nejdřív zablokuje natvrdo zadané cesty,
pak spustí `wiki-integrity-check.py` a `wiki_index.py --force` (fail-closed). Stránka nad
40 000 znaků potřebuje rozdělit, nebo neprázdný frontmatter klíč `size_exception`
(`wiki/log.md` ho má: append-only chronologie). Hook navíc jen varuje, když nejsou
nainstalované bakery-sync hooky. Zapnutí: `git config core.hooksPath .githooks` (dělá `./setup.sh`).

### Wiki update trigger

```bash
task wiki:update              # příprava
task wiki:aider               # lokální model + Aider (doporučeno)
task wiki:local               # fallback: API bundle + apply
```

## Bakery Wiki sync (blocking rule)

**Povinné pro všechny agenty i vývojáře.** Hooky `tools/bakery-sync/` hlídají, že práce
v bakery repech skončí ve wiki. Spínačem je doslovný řetězec z nadpisu této sekce, takže
v `bakery-wiki` je zapnuto vždy; ostatní bakery repa (bakery-gitops, bakery-onboarding,
bakery-platform, fake-buster, stock-trader-grabit, ...) se zapínají markerem v klonu
(`~/.bakery-sync/hooks/bakery-sync-optin.sh on`, nic se necommituje).

**Proč odděleně od hooků Kytary:** na stroji běží i hooky Kytary.Wiki (`~/.wiki-sync`),
které zapíná marker `.git/info/wiki-sync` nebo spínač Kytary v CLAUDE/AGENTS.md. Kdyby
bakery sdílelo marker či spínač, bakery znalosti by se posílaly do firemní wiki; a
uninstall Kytary maže každou registraci s `wiki-sync-`. Proto má bakery vlastní
`~/.bakery-sync`, `.git/info/bakery-sync` a skripty `bakery-sync-*.sh`.
Do tohoto souboru ani do `AGENTS.md` proto nikdy nepatří spínač Kytary.

Při změně, která mění obsah nebo způsob údržby wiki:

1. Přidej záznam na **konec** `wiki/log.md` (jeden append-only log), formát `## [YYYY-MM-DD] <type> | <title>`.
2. Aktualizuj dotčené stránky, `updated:` a řádek v `wiki/index.md` u nové stránky.
3. Spusť `python3 tools/wiki-integrity-check.py`.
4. Commitni **rovnou do `dev`**: `git add` jen soubory, které jsi editoval ty, **nikdy `-A`**
   (vault sdílí paralelní sessions). Zpráva `docs(wiki): <stručný popis>`.
5. Push dělá `.githooks/post-commit` sám; selhání pushe ohlásí Stop hook.

Změna bez dopadu na obsah se odbyde `~/.bakery-sync/hooks/bakery-sync-ack.sh <session_id>`;
při psaní wiki subagentem zavolej `bakery-sync-delegated.sh <session_id>`.

Hooky se instalují **jednou z hlavního klonu** (`bash tools/bakery-sync/install.sh`, z git
worktree to installer odmítne) a pak se samy aktualizují, pokud klon odpovídá `origin/dev`.
Jednorázová kontrola, zda jsou hooky aktuální:

```bash
grep -q self_update_hooks ~/.bakery-sync/hooks/lib.sh && echo OK || echo "reinstall: bash tools/bakery-sync/install.sh"
```

## Repository mapping (Platform v2)

| Repo | Role | Status |
|------|------|--------|
| bakery-platform | Bootstrap + charts + CI | ✅ Pilot |
| bakery-gitops | Argo CD GitOps + ApplicationSet | ✅ Pilot |
| bakery-onboarding | Service onboarding API | ✅ Pilot |
| bakery-wiki | LLM-maintained Obsidian wiki | ✅ Active |
| service-bakery | Legacy monolith platform | 🔄 Migrating away |
| fake-buster | App (ML fake news) | ✅ Pilot on kind-desktop |
| stock-trader-grabit | App (trading) | ✅ Pilot on v2 |

## Important rules

1. **Never modify `raw/`** (except humans drop sources; auto-snapshot is overwritten)
2. **Always update `index.md` and `log.md`** after wiki changes
3. **Wiki sync policy** — any agent changing bakery-platform/gitops/onboarding/apps **must** update this wiki in the same session (see `wiki/concepts/Wiki sync policy.md`)
4. **Update `updated` in frontmatter** when editing a page
4. **Prefer updating existing pages** over creating new ones
5. **Track status**: ✅ ⬜ 🔄
6. **No absolute paths** in `wiki/*.md` — enforced by `.githooks/pre-commit`
