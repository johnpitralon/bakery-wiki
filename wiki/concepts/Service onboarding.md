---
title: Service onboarding
type: concept
tags: [onboarding, automation, mcp]
created: 2026-07-08
updated: 2026-07-08
---

Automatické přidání nové mikroservisy do ekosystému přes [[entities/bakery-onboarding]].

## Vstup

`POST /v1/onboard` — JSON s `name`, `template`, `target_repo`, `port`, `owner`, …

Šablony MVP: `go-service`, `java-spring`, `python-service`, `react-frontend`.

## Kroky pipeline

| Step | Akce |
|------|------|
| resolve | Render context, image repo, health path |
| repo_create | Clone / create GitHub repo |
| deploy_scaffold | Dockerfile, kód, README ze šablon |
| git_hooks | Instalace `.githooks/` (Kytary-style) |
| gitops_register | `service-bakery.yaml` + gitops values + PR |

## Artefakty

- App PR: scaffold + registry entry
- GitOps PR: `genericMicroservices` v `values.yaml`
- `apps-registry.json` bump (budoucí ApplicationSet)

## Rozdíl oproti Kytary.Onboarding

| | Kytary | Bakery MVP |
|---|--------|------------|
| Kroky | 15–18 | 5 |
| Keycloak client | ano | ne (MVP) |
| Monorepo | StockBass/StockTune | ne |
| GitOps target | Kytary.GitOps | bakery-gitops |

## Souvislosti

- [[entities/bakery-onboarding]]
- [[concepts/Platform v2]]
