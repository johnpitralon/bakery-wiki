---
title: personal-agents
type: entity
tags: [app, cronjob, kind-desktop, onboarding]
sources: []
created: 2026-11-21
updated: 2026-11-22
---

Aplikace na Platform v2 (stav 🔄 onboarding na `kind-desktop`). Repo `johnpitralon/personal-agents` (privátní) je monorepo osobních jednoúčelových automatizačních agentů majitele.

## Obsah

- První agent `agents/dph` připravuje měsíční české DPH (DPHDP3 + kontrolní hlášení XML, xlsx, zip odeslaný majiteli e-mailem).
- Python 3.12 / uv. LLM běží přes Kytary llm-gateway (viz sekce níže); původní lokální LM Studio na Macu se přehřívalo a shodilo macOS.
- Tato stránka popisuje jen platformní a deployment tvar; žádná daňová data ani hodnoty secretů se do wiki nedávají.

## Deployment

- Cíl: cluster `kind-desktop`, namespace `personal-agents`, Kubernetes **CronJob** z chartu `bakery-app` (viz [[entities/bakery-platform]]). Větev app repa `dev` → kind; `main` zatím nenasazuje nikam.
- Image: per-app Argo CI CronWorkflow (kaniko → `localhost:5001`), poté bump `tag:` v `apps/personal-agents/values.yaml` v [[entities/bakery-gitops]].
- Secrets: k8s Secret `personal-agents-secrets` se vytváří z SOPS/age souboru `deploy/clusters/local/cluster.env.enc` v app repu (úlohy `secrets:decrypt`, `secrets:encrypt`, `secrets:apply`; Keychain odstraněn). `secrets:apply` spouští `apply-app-secrets.sh` s dočasným kubeconfigem, takže nepřepíná kubectl kontext uživatele. Bez DB, tedy bez db-init.
- Persistence: statický PV na `desktop-worker3` v `/persistent-data/personal-agents`, vlastník uid/gid 10001, storage class `local-static`, Retain.

## Registrace v bakery-gitops

Registrace je v `dev` od [[entities/bakery-gitops]] PR #24 (merge `fa5a6d4`, správný re-land po revertu PR #23). CronJob `dph` má `suspend: true` až do akceptačního běhu (jinak by se rozvrh 20–24 spustil 22. 11. za říjen bez secrets). Env CronJobu `PA_LLM_URL=https://llm-gateway.dev.k8s.kytary.cz`, adresa LLM je tedy konfigurovatelná v gitops values.

## LLM přes llm-gateway 🔄

- Agent používá Kytary **llm-gateway** v dev clusteru firmy (LiteLLM, OpenAI-kompatibilní) místo LM Studia na MacBooku.
- Vlastní statický klíč s rolí `LLM/LMStudio/Use`, přidaný do `LITELLM_STATIC_KEYS` dev gateway (GitHub Environment secret, poté workflow `sync-secrets`; ostatní klíče beze změny).
- Model `lmstudio/google/gemma-4-31b`, ověřeno smoke testem se strict json_schema (HTTP 200, 5 s).
- Provider, URL a model jsou v `agent.yaml` → `PA_LLM_PROVIDER` / `PA_LLM_URL` / `PA_LLM_MODEL`.
- Kód je na větvi `feat/llm-gateway` (nemergnuto, v review). Klíč jde do Secretu jako `LLM_API_KEY` (bakery-platform PR #36).

## Maskování osobních údajů 🔄

- Gateway přeposílá na sdílený Mac Studio, jehož LM Studio může logovat celá těla požadavků. Majitel proto rozhodl, že před modelem se tokeny maskují osobní údaje poplatníka (DIČ včetně tvaru rodného čísla, jméno, adresa, PSČ, e-mail, telefon) a VŠECHNY částky.
- Kód tokeny mapuje zpět; kontrola DIČ se dělá v kódu; stránky výpisu hovorů T-Mobile se modelu neposílají.
- Stav: větev `feat/llm-gateway`, v review.

## Stav

- ✅ bakery-platform PR #34, #35 (21. 11.) a #36 (22. 11.) merged
- ✅ personal-agents PR #1 merged do `dev` (merge `03576f6`, CI zelené): DPH agent + SOPS/age secrets
- ✅ Incident v bakery-gitops vyřešen revertem (PR #23); registrace znovu přes PR #24 (`fa5a6d4`)
- ✅ PV `personal-agents-data-pv` Bound; Argo app `personal-agents` Synced/Progressing
- 🔄 PVC `maven-m2-cache` Pending do prvního CI podu (WaitForFirstConsumer)
- 🔄 LLM gateway a maskování (`feat/llm-gateway`, v review)
- ⬜ **OTEVŘENÉ:** CronWorkflow `personal-agents-merge-deploy` existuje, ale do 01:07 CET nevytvořil žádný workflow; prošetřit
- ⬜ Secret `personal-agents-secrets` zatím nevytvořen (čekají přihlašovací údaje majitele)
- ⬜ Akceptační běh a odpárování `suspend` u CronJobu `dph`
