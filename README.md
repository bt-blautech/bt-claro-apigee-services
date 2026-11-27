# bt-claro-apigee-services

PoC CI/CD, DevSecOps y Automatización para **Claro CENAM** (RFP migración Apigee OPDK → Apigee X/Hybrid).
Este repo contiene **la API** `poc-customer-v1` y su pipeline de **GitHub Actions** (DEV y QA en Apigee X).
La plataforma (VPC, organización, instancia, LB, certificados, ambientes, vault, backends de prueba) vive en
**[bt-claro-apigee-infrastructure](https://github.com/bt-blautech/bt-claro-apigee-infrastructure)**, que además publica en este repo
las variables y el secreto que usa el pipeline.

## Solución

| Componente | Detalle |
|---|---|
| API proxy | `poc-customer-v1` · basepath `/v1/poc-customer` · GET `/customers`, GET `/customers/{id}`, POST `/customers` |
| Policies obligatorias | VerifyAPIKey (`x-apikey`) · Quota (100/min DEV, 500/min QA) + SpikeArrest 10ps · JSONThreatProtection + límite 2 KB · AssignMessage (`x-correlation-id`) · RaiseFault (404/500 JSON) |
| Recursos de la API como código | Target server `poc-customer-backend` (host `BACKEND_HOST`, TLS exigido con el truststore del ambiente), KVM cifrado `poc-customer-config` (secreto desde el vault), producto `poc-product`, apps `poc-app-dev` / `poc-app-qa` |
| CI/CD | `pr-checks` (gate de PR: validación + preview en DEV con pruebas) · `ci-validate` (validación en push) · `cd-pipeline` (build único + DEV; en tags: guardia de release) · `promote-qa` (gate + mismo artefacto a QA) · `rollback` · `trace-revision` (revisión → commit/run) · `promote-release` (release a staging/prod en org aislada) |

## Variables y secretos (los configura `bt-claro-apigee-infrastructure/scripts/setup_github.sh`)

| Nombre | Tipo | Alcance |
|---|---|---|
| `GCP_SA_KEY` | secret | repo — llave JSON (una línea) de `<name>-cicd`: solo roles de Apigee y lectura del vault |
| `APIGEE_ORG`, `APIGEE_NAME`, `QA_APPROVERS` | variable | repo |
| `APIGEE_HOST`, `BACKEND_HOST` | variable | environments `dev` y `qa` |
| `PREVIEW_APIGEE_HOST` | variable | repo — host de DEV para el preview de PR (el job de PR no usa el environment `dev`) |
| `GCP_SA_KEY` · `APIGEE_ORG`, `APIGEE_NAME`, `APIGEE_HOST`, `BACKEND_HOST` | secret · variables | environments `staging` y `prod` (org aislada; sobreescriben las del repo). Los publica `setup_github.sh` con `ENV_SCOPED=1` |

## Flujo (caso de uso de Claro)

```bash
git checkout -b feature/poc-customer && git commit -m "feat: ..." && git push -u origin feature/poc-customer   # Paso 1-2 (ci-validate)
# PR feature -> develop (pr-checks: validacion + preview /preview/v1/poc-customer + pytest; check requerido)
# PR develop -> main -> cd-pipeline despliega DEV y prueba                                                  # Paso 3-4
# Release: VERSION=X.Y.Z en main + git tag vX.Y.Z (cd-pipeline rechaza tags fuera de main o distintos a VERSION)
gh workflow run promote-qa.yml -f dev_run_id=<ID del run de cd-pipeline> -f confirmacion=PROMOVER-QA       # Paso 5-6
gh workflow run rollback.yml -f environment=dev                                                           # Paso 9
gh workflow run trace-revision.yml -f environment=qa                                                      # C9 inverso
gh workflow run promote-release.yml --ref vX.Y.Z -f release_run_id=<run del tag> -f environment=staging -f confirmacion=PROMOVER-STAGING  # guinda
PROJECT_ID=cs-poc-6k18qfubvs1hrrde4cc8tfs APIGEE_NAME=claro-poc scripts/export_evidence.sh bt-blautech/bt-claro-apigee-services      # Paso 10 (E5)
```

## Mapeo capacidad → archivo / workflow

| Cap. | Capacidad | Implementación |
|---|---|---|
| C1 ★ | Control de versiones | Git (`main`, `develop`, `feature/*`), `.gitignore`, tags `vX.Y.Z`, Conventional Commits |
| C2 | Validación automática | `.github/workflows/pr-checks.yml` (check requerido en PR: validación + preview con pruebas), `.github/workflows/ci-validate.yml` → `scripts/validate.sh`, `scripts/check_bundle.py`, `scripts/check_config.py`, apigeelint |
| C3 ★ | Despliegue DEV | `cd-pipeline.yml` job `deploy-dev` → `scripts/deploy.sh`, auth con `secrets.GCP_SA_KEY` |
| C4 | Invocación | `tests/test_smoke.py` (200, payload, `x-correlation-id`, < 500 ms, 401/404/413/415) |
| C5 ★ | Promoción DEV → QA | `.github/workflows/promote-qa.yml` (manual con el ID del run de DEV): gate = aprobador en `QA_APPROVERS` + confirmación `PROMOVER-QA` + run de DEV en *success*; descarga el **mismo** bundle de ese run, `sha256sum -c`, misma revisión de Apigee (sin reimportar) |
| C6 | Parametrización | `config/dev/env.json` vs `config/qa/env.json` + `BACKEND_HOST`/`APIGEE_HOST` por environment; target server con el truststore del ambiente (TLS exigido); backends, truststores y certificados en bt-claro-apigee-infrastructure |
| C7 | Proxy, policies, KVM, TS, product | `apiproxy/` (14 policies), `scripts/apply_config.sh` (target server, KVM), `scripts/apply_products.sh` (`poc-product`, apps) |
| C8 ★ | Secretos | GitHub Secrets, Secret Manager (vault), KVM cifrado, `private.*`, `::add-mask::`, gitleaks |
| C9 | Trazabilidad | Description `sha=;version=;run=`, `scripts/trace.sh` (comentario en commit + summary), headers `X-Proxy-Revision`/`X-Build-Commit`; inverso: workflow `trace-revision` (revisión → commit, run y deployments) |
| C10 ★ | Rollback | `.github/workflows/rollback.yml` → `scripts/rollback.sh` + pytest con `EXPECTED_REVISION` |
| C11 | Evidencias | job `evidence` → `scripts/evidence.sh` (`REPORTE.md`, tiempos), artefactos `evidence-*`; `scripts/export_evidence.sh` (E5: runs y logs en JSON, estado de Apigee, `index.html`, verificación de secretos) |

★ = capacidad crítica (descalificante).
