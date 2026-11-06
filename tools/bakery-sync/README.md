# bakery-sync — hooky pro synchronizaci wiki

Agent-neutrální hooky (Claude Code, Codex CLI, Cursor), které hlídají, že změny v bakery
repech skončí i v `bakery-wiki`: SessionStart (kontext + jednorázová otázka u nového repa),
PostToolUse (zaznamenává editované soubory) a Stop (připomene update, commit a push wiki).

## Původ

Port `tools/wiki-sync/` z Kytary.Wiki (commit `8d12c644`), jen přejmenovaný a zbavený
Kytary-specifických částí. Diff proti upstreamu držíme malý, aby šly opravy přenášet.

## Co se liší a proč

| Oblast | Kytary | Bakery | Proč |
|--------|--------|--------|------|
| Skripty | `wiki-sync-*.sh` | `bakery-sync-*.sh` | Kytary `install.sh --uninstall` maže každou registraci s `wiki-sync-` |
| Instalace | `~/.wiki-sync` | `~/.bakery-sync` | Obě sady hooků běží na jednom stroji vedle sebe |
| Marker | `.git/info/wiki-sync` | `.git/info/bakery-sync` | Marker Kytary nesmí zapnout bakery (a naopak) |
| Spínač v CLAUDE/AGENTS.md | `LLM Wiki sync` | `Bakery Wiki sync` | Jinak by Kytary hooky posílaly bakery znalosti do firemní wiki |
| Env / funkce | `WIKI_SYNC_*`, `wiki_sync_*` | `BAKERY_SYNC_*`, `bakery_sync_*` | Stejný důvod, žádné kolize |
| Org regex | `ITKytaryDevTeam` | `(github.com\|github-johnpitralon)[:/]johnpitralon/` | Remote má tvar `git@github-johnpitralon:johnpitralon/...` |
| Log | měsíční archivy `wiki/log/` | jeden append-only `wiki/log.md` | Záznam se přidává na konec |
| Commit | `log: ...` | `docs(wiki): ...` | Konvence bakery-wiki |
| Migrace legacy | ano | smazána | Sahala by na `~/.claude/state/wiki-sync` a hooky Kytary |
| Windows | `install.ps1`, testy | nenaportováno | Větve v `lib.sh`/`install.sh` zůstávají, jsou neaktivní |

## Instalace

Jednou, z **hlavního klonu** bakery-wiki (z git worktree ji installer odmítne):

```bash
bash tools/bakery-sync/install.sh            # autodetekce agentů
bash tools/bakery-sync/install.sh --dry-run  # jen náhled
bash tools/bakery-sync/install.sh --uninstall
```

Skripty se pak samy aktualizují při startu session, pokud klon odpovídá `origin/dev`.
Codex při příštím startu jednou požádá o schválení změněných hooků.

## Zapnutí v repu (opt-in)

- bakery-wiki: zapnuto spínačem (`## Bakery Wiki sync (blocking rule)` v `CLAUDE.md`).
- Ostatní bakery repa: marker v klonu, nic se necommituje:

```bash
~/.bakery-sync/hooks/bakery-sync-optin.sh on|off|status
```

Nové repo v org `johnpitralon` bez markeru dostane při startu jednorázovou otázku.

## ack / delegated

- `~/.bakery-sync/hooks/bakery-sync-ack.sh <session_id>` — změna wiki nepotřebuje, umlčí aktuální stav.
- `~/.bakery-sync/hooks/bakery-sync-delegated.sh <session_id>` — wiki píše subagent na pozadí,
  Stop hook na chvíli mlčí (Codex: `spawn_agent`, pak delegated, tah hned ukonči).

## Testy

```bash
bash tools/bakery-sync/tests/run-all.sh
```

Každý test běží nad dočasným `HOME`/state a nesahá na skutečné `~/.claude`, `~/.codex`,
`~/.cursor`, `~/.wiki-sync` ani `~/.bakery-sync`. `isolation.test.sh` hlídá souběh s hooky Kytary.

## Port opravy z upstreamu

1. Vezmi změnu v `tools/wiki-sync/` z Kytary.Wiki (jen čtení, nic tam necommituj).
2. Aplikuj stejná přejmenování v tomto pořadí: `WIKI_SYNC_`→`BAKERY_SYNC_`, `wiki_sync_`→`bakery_sync_`,
   `wiki-sync`→`bakery-sync`, `Wiki sync reminder`→`Bakery wiki sync reminder`,
   `LLM Wiki sync`→`Bakery Wiki sync`, `Kytary.Wiki`→`bakery-wiki`, `ITKytaryDevTeam`→`johnpitralon`.
3. Neportuj migrace legacy ani Windows; zprávy ve `bakery-sync-stop.sh` drž u jednoho logu.
4. Spusť `run-all.sh`, v tomto README aktualizuj commit původu.
