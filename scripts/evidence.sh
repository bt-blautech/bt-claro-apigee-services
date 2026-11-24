#!/usr/bin/env bash
# Capacidad 11: consolida evidencias del run en evidence/REPORTE.md y en el job summary.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-local}/actions/runs/${GITHUB_RUN_ID:-0}"
R=${RESULTS:-'{}'}
res() { echo "$R" | jq -r --arg j "$1" '.[$j].result // "n/a"'; }
devrev=$(cat evidence/evidence-dev/deploy-dev.json 2>/dev/null | jq -r .revision || echo n/a)
qarev=$(cat evidence/evidence-qa/deploy-qa.json 2>/dev/null | jq -r .revision || echo n/a)

# Tiempos por job desde la API de GitHub (si hay token)
TIMES=""
if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  TIMES=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/jobs" \
    --jq '.jobs[] | select(.completed_at != null) | "| \(.name) | \(.conclusion) | \(((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601)))s |"' || true)
fi

cat > evidence/REPORTE.md <<MD
# Evidencias de ejecucion — ${PROXY_NAME:-poc-customer-v1}

- Commit: \`${GITHUB_SHA:-local}\` · Ref: \`${GITHUB_REF:-local}\` · Run: ${RUN_URL}
- Generado: $(date -u +%FT%TZ)

| # | Capacidad | Resultado | Evidencia |
|---|---|---|---|
| 1 | Control de versiones | Ver repo | historial, branches, tags \`git tag -l\` |
| 2 | Validacion automatica | $(res validate) | evidence-validate/apigeelint.* |
| 3 | Deploy DEV | $(res deploy-dev) | evidence-dev/deploy-dev.json (r${devrev}) |
| 4 | Prueba invocacion | $(res deploy-dev) | evidence-dev/pytest-dev.xml |
| 5 | Promocion DEV->QA | workflow promote-qa | evidence-qa-* (gate + mismo sha256 + misma revision) |
| 6 | Parametrizacion | $(res deploy-dev)/$(res promote-qa) | config/dev vs config/qa |
| 7 | Proxy/policies/KVM/TS/product | $(res deploy-dev) | logs paso "Configuracion" |
| 8 | Secretos | $(res validate) | gitleaks + logs enmascarados (***) |
| 9 | Trazabilidad | $(res deploy-dev) | comentario en commit + summary |
| 10 | Rollback | workflow apigee-rollback | evidence-rollback-* |
| 11 | Evidencias | este reporte | evidence-report-${GITHUB_RUN_ID:-0} |

## Tiempos por job
| Job | Resultado | Duracion |
|---|---|---|
${TIMES}
MD
cat evidence/REPORTE.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat evidence/REPORTE.md
