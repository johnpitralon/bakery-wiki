# Auto snapshot — 2026-07-08 09:27

Generováno: `scripts/collect-context.sh` (LLM wiki trigger)

## Workspace

- `BAKERY_WORKSPACE`: `/Users/deniskalna/workspace`

## Git stav (sibling repos)

### bakery-platform
- branch: `main`
- last commit: `76ba3ae Fix db-writer pilot: DB_HOST env, health probes, pullPolicy.`
- uncommitted files: 13

### bakery-gitops
- branch: `main`
- last commit: `707b314 Avoid namespace conflict: exclude bakery-onboarding from gitops root.`
- uncommitted files: 4

### bakery-onboarding
- branch: `main`
- last commit: `c573c26 Platform v2 pilot skeleton.`
- uncommitted files: 16

### bakery-wiki
- branch: `main`
- last commit: `998319a Initial commit: Obsidian wiki for Bakery platform.`
- uncommitted files: 24

### fake_buster
- branch: `feature/fix-kind-deploy-align-ci-image-prefix-and-validate-frontend-standalone-build`
- last commit: `08c2f26 Fix Kind deploy: inference JAR name, frontend .dockerignore, labeler JWT env.`
- uncommitted files: 3

### service-bakery
- branch: `feature/chore-release-v1-0-155`
- last commit: `be48770 Fix CI image prefix override and disable Kaniko cache for Next.js builds.`
- uncommitted files: 1

## Kubernetes (pokud dostupné)

### Argo CD Applications (bakery)
```
bakery-gitops-root                                                                               Synced        Healthy
bakery-onboarding                                                                                Synced        Healthy
fake-buster                                                                                      Synced        Healthy
service-bakery                                                                                   Unknown       Healthy
```

### fake-buster namespace
```
NAME                                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/fake-buster-db-writer   1/1     1            1           29m
deployment.apps/fake-buster-frontend    2/2     2            2           29m
deployment.apps/fake-buster-inference   1/1     1            1           29m
deployment.apps/fake-buster-labeler     1/1     1            1           29m

NAME                                         READY   STATUS    RESTARTS   AGE
pod/fake-buster-db-writer-7b5f55d9d8-685qb   1/1     Running   0          17m
pod/fake-buster-frontend-b775896d8-4jr4k     1/1     Running   0          29m
pod/fake-buster-frontend-b775896d8-nsk4c     1/1     Running   0          29m
pod/fake-buster-inference-cd5655887-ttn7s    1/1     Running   0          29m
pod/fake-buster-labeler-964c6c959-4fmrw      1/1     Running   0          29m
```

### Helm fake-buster
```
NAME: fake-buster
LAST DEPLOYED: Wed Jul  8 09:23:53 2026
NAMESPACE: bakery-infrastructure
STATUS: deployed
REVISION: 15
DESCRIPTION: Upgrade complete
RESOURCES:
==> v1/Service
NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
fake-buster-labeler   ClusterIP   10.96.21.127   <none>        8081/TCP   36h
fake-buster-inference   ClusterIP   10.96.33.245   <none>   8080/TCP   36h
fake-buster-db-writer   ClusterIP   10.96.229.189   <none>   8084/TCP   36h
```
