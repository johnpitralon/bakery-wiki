---
title: Image versions
type: concept
tags: [versions, ci, docker, maven]
created: 2026-07-08
updated: 2026-07-08
---

Všechny **Docker image tagy** a **CI toolchain verze** žijí v `bakery-platform/image-versions.env` (pravidlo #9 z bakery.mdc).

## Klíčové proměnné

| Skupina | Příklady |
|---------|----------|
| CI Java | `MAVEN_IMAGE`, `JAVA_RUNTIME_IMAGE`, `SPRING_BOOT_VERSION`, `JAVA_VERSION` |
| CI ostatní | `GO_BUILD_IMAGE`, `NODE_IMAGE`, `PYTHON_IMAGE`, `KANIKO_EXECUTOR_IMAGE` |
| Pilot deploy | `BAKERY_ONBOARDING_DEPLOY_IMAGE`, `POSTGRES_CLIENT_TAG` |
| App tags | `IMAGE_TAG`, `LABELER_TAG`, … |

## Propisování

- `bootstrap/initial.sh` → `envsubst` do Argo WorkflowTemplate
- [[entities/bakery-onboarding]] → `ResolveImages()` / `ResolveJava()` + ConfigMap `bakery-image-versions`
- Generované Dockerfiles → ARG preamble z `image-versions.env`

## Maven / Spring (pilot)

- Maven image: `maven:3.9.12-eclipse-temurin-25`
- Spring Boot parent (scaffold + fake_buster parent): `4.0.7`
- Java: `25`

## Souvislosti

- [[entities/bakery-platform]]
- [[entities/fake_buster]]
