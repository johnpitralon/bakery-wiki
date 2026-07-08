---
title: bakery-onboarding
type: entity
tags: [repo, go, onboarding, mcp, openwebui]
created: 2026-07-08
updated: 2026-07-08
---

Go služba pro **onboardování nových mikroservis** do app repa a [[entities/bakery-gitops]]. Jeden HTTP kontrakt, více LLM klientů (Open WebUI, Claude, Cursor/Codex přes MCP).

## Repozitář

- **URL**: https://github.com/johnpitralon/bakery-onboarding
- **Default branch**: `main`
- **Local clone**: `<workspace>/bakery-onboarding`
- **Go modul**: `github.com/johnpitralon/bakery-onboarding`

## API (kanonický kontrakt)

- `POST /v1/onboard` — strukturovaný JSON (`OnboardRequest`)
- `GET /openapi.json` — Open WebUI tool server
- Health: `/healthz`, `/readyz`

## LLM klienti

| Klient | Adaptér | Tool / příkaz |
|--------|---------|---------------|
| **Open WebUI** | OpenAPI tool server | `onboardService` |
| **Claude Code** | MCP stdio `cmd/mcp-server` | `onboard_service` |
| **Cursor / Codex** | stejný MCP config | `onboard_service` |
| **CLI** | `cmd/onboard-cli` | flags |
| **IDE** | slash command | `/onboard-service` |

Dokumentace v repu: `docs/llm-clients.md`, `plugins/mcp/`.

Env MCP: `ONBOARD_URL` (HTTP proxy) nebo `ONBOARD_MODE=local` (in-process).

## Pipeline

`resolve` → `repo_create` → `deploy_scaffold` → `git_hooks` → `gitops_register`

Výstupy: scaffold, `service-bakery.yaml`, `bakery-gitops/apps/<app>/values.yaml`, 2× PR.

Workflow: vždy **dry_run=true** první, pak `dry_run=false`.

## Deploy

- Namespace: `bakery-agent-infra`
- Argo: ApplicationSet `bakery-apps` z `apps/bakery-onboarding/app.json`
- Image: [[concepts/Image versions|image-versions.env]]
- Secret `bakery-onboarding-secrets` (`gh-token`) — z app `cluster.env`

## Souvislosti

- [[concepts/Service onboarding]]
- [[concepts/Wiki sync policy]]
- [[entities/bakery-gitops]]
