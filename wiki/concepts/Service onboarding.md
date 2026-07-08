---
title: Service onboarding
type: concept
tags: [onboarding, automation, mcp, openwebui]
created: 2026-07-08
updated: 2026-07-08
---

Automatické přidání nové mikroservisy přes [[entities/bakery-onboarding]] — **jeden backend, více LLM klientů**.

## Vstup

`POST /v1/onboard` — JSON: `name`, `template`, `target_repo`, `port`, `owner`, `dry_run`, …

Šablony: `go-service`, `java-spring`, `python-service`, `react-frontend`.

## LLM integrace (univerzální)

```
Open WebUI ──OpenAPI──► HTTP /v1/onboard ◄──MCP── Claude / Cursor / Codex
CLI ──in-process──► pipeline
```

- Open WebUI: `deploy/openwebui/tool-server-connections.json`
- MCP: `cmd/mcp-server`, tool `onboard_service`
- Slash: `/onboard-service` (Cursor + Claude Code)

## Kroky pipeline

| Step | Akce |
|------|------|
| resolve | Render context, image repo, health path |
| repo_create | Clone / create GitHub repo |
| deploy_scaffold | Dockerfile, kód, README |
| git_hooks | `.githooks/` (Kytary-style) |
| gitops_register | `service-bakery.yaml` + gitops values + PR |

## Doporučený workflow (všichni klienti)

1. `dry_run=true` → plán uživateli
2. Potvrzení → `dry_run=false` → PR

## Rozdíl oproti Kytary.Onboarding

| | Kytary | Bakery |
|---|--------|--------|
| LLM klient | Cowork plugin | Open WebUI + MCP + IDE |
| Kroky | 15–18 | 5 |
| Keycloak | ano | ne (MVP) |
| GitOps | Kytary.GitOps | bakery-gitops |

## Souvislosti

- [[entities/bakery-onboarding]]
- [[concepts/Platform v2]]
- [[concepts/Wiki sync policy]]
