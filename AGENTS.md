# bakery-wiki — instrukce pro AI agenty

Tento soubor čtou automaticky Cursor, Codex, Claude Code, **a lokální stacky** přes prompt bundle.
**Před úpravou `wiki/` vždy přečti také `CLAUDE.md`.**

## Role

Udržuješ **LLM wiki** pro Bakery platformu (Platform v2). Lidské zdroje jsou v `raw/` (neměnit).
Znalostní graf je v `wiki/` (tvoje doména).

## ⚠️ Povinné pravidlo (Wiki sync policy)

**Každá smysluplná změna** v `bakery-platform`, `bakery-gitops`, `bakery-onboarding`, app repech nebo clusteru → **aktualizuj wiki ve stejné session** před ukončením úkolu.

Minimálně: relevantní `wiki/entities/` nebo `wiki/concepts/`, append `wiki/log.md`, `updated:` ve frontmatter.
Viz `wiki/concepts/Wiki sync policy.md`.

Pokud pracuješ v jiném bakery repu (ne v bakery-wiki), na konci úkolu otevři bakery-wiki a proveď update (`task wiki:update` nebo `/wiki-update`).

## Dva způsoby práce

### 1. Agent s file access (IDE)

Cursor, Claude Code, Codex, Aider, Continue — čtou repo přímo.

```bash
task wiki:update
```

### 2. Lokální model (Ollama, LM Studio, LiteLLM, Open WebUI)

Model **nemá** přístup k souborům → dostane `triggers/out/LATEST-prompt.md` (vše v jednom promptu).

```bash
task wiki:local    # nebo wiki:update → wiki:run-local → wiki:apply
```

Konfigurace: `triggers/local-models.env` (z `.example`).

Výstup lokálního modelu: `<wiki-file path="wiki/…">` tagy → `apply-wiki-response.sh`.

## Trigger — kdy aktualizovat

1. `./scripts/trigger-wiki-update.sh` nebo `task wiki:update`
2. Soubor `.wiki-update-request`
3. Uživatel požádá o ingest / update / lint
4. Nový soubor v `raw/`

## Povinný postup

1. Přečti `CLAUDE.md`; fakta hledej search-first: `python3 tools/wiki-query.py search "<dotaz>"`, pak `section <cesta> <nadpis>` (`wiki/index.md` jen jako fallback)
2. Kontext: `raw/auto-snapshot-*.md` nebo `triggers/out/LATEST-prompt.md`
3. Aktualizuj `wiki/`, `index.md`, append `log.md`
4. Žádné `/Users/...` v `wiki/*.md`
5. Smaž `.wiki-update-request` po dokončení
6. Agenti: explicitní `git add <cesty>` (nikdy `-A`) + `git commit` na `dev`; push udělá post-commit.
   `./scripts/wiki-commit-push.sh` (používá `git add -A`) zůstává jen pro pipeline s lokálním modelem.

## Hooky (bakery-sync)

Povinná sekce `## Bakery Wiki sync (blocking rule)` v `CLAUDE.md`. Hooky se instalují jednou
z hlavního klonu (`bash tools/bakery-sync/install.sh`). Jednorázová kontrola:
`grep -q self_update_hooks ~/.bakery-sync/hooks/lib.sh` — když selže, spusť installer znovu.

Detail: `WIKI_UPDATE.md`, `triggers/README.md`
