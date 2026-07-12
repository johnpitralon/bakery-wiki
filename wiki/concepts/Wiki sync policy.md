---
title: Wiki sync policy
type: concept
tags: [wiki, process, meta]
created: 2026-07-08
updated: 2026-07-08
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
6. **`./scripts/wiki-commit-push.sh`** — auto commit + push (nebo `task wiki:finish`)

Vypnutí: `WIKI_AUTO_COMMIT=false` nebo `WIKI_AUTO_PUSH=false`.

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
