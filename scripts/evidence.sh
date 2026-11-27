#!/usr/bin/env bash
# Capacidad 11: consolida evidencias del run en evidence/REPORTE.md y en el job summary.
# Muestra resultados reales (no texto fijo): ref/VERSION, revision, pruebas y latencia medidas,
# parametrizacion DEV vs QA, links a promote/rollback, comandos ejecutados y tiempos por job.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence
SERVER=${GITHUB_SERVER_URL:-https://github.com}
REPO=${GITHUB_REPOSITORY:-local}
RUN_URL="${SERVER}/${REPO}/actions/runs/${GITHUB_RUN_ID:-0}"
SHA=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo local)}
R=${RESULTS:-'{}'}
res() { echo "$R" | jq -r --arg j "$1" '.[$j].result // "n/a"'; }
icon() { case "$1" in success) echo "✅ success" ;; failure) echo "❌ failure" ;; skipped) echo "⏭️ skipped" ;; *) echo "$1" ;; esac; }

DEV_JSON=$(find evidence -name 'deploy-dev.json' | head -1)
devrev=$([[ -n "$DEV_JSON" ]] && jq -r .revision "$DEV_JSON" || echo n/a)
VERSION=$(cat VERSION 2>/dev/null || echo n/a)
REF_NAME=${GITHUB_REF_NAME:-local}
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  [[ "$REF_NAME" == "v${VERSION}" ]] && C1="✅ tag \`${REF_NAME}\` = VERSION ${VERSION}" || C1="⚠️ tag \`${REF_NAME}\` ≠ VERSION ${VERSION}"
else
  C1="rama \`${REF_NAME}\` · VERSION ${VERSION}"
fi

# C4: resultado de pytest (junit XML) y latencia medida por la prueba
PYTEST_XML=$(find evidence -name 'pytest-dev.xml' | head -1)
TESTS="n/a"
if [[ -n "$PYTEST_XML" ]]; then
  TESTS=$(python3 - "$PYTEST_XML" <<'PY'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
s = r if r.tag == "testsuite" else r.find("testsuite")
t, f, e, k = (int(s.get(a, 0)) for a in ("tests", "failures", "errors", "skipped"))
print(f"{t - f - e - k}/{t} pruebas OK" + (f", {f + e} fallidas" if f + e else ""))
PY
)
fi
LAT_JSON=$(find evidence -name 'latency-dev.json' | head -1)
LAT=$([[ -n "$LAT_JSON" ]] && jq -r '"\(.latency_ms) ms (max \(.max_ms))"' "$LAT_JSON" || echo "n/a")

# C6: diferencias reales entre ambientes (desde config/, la misma fuente que aplica el pipeline)
C6_TABLE=$(for f in config/*/env.json; do
  jq -r '"| \(.environment) | \(.kvm.entries.quota_limit)/min | \(.targetServer.truststoreRef // "-") | \(.app.name) | \(.kvm.entries.env_label) |"' "$f"
done)

# Tiempos por job (requiere permissions: actions: read)
TIMES=""
if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  TIMES=$(gh api "repos/${REPO}/actions/runs/${GITHUB_RUN_ID}/jobs" \
    --jq '.jobs[] | select(.completed_at != null) | "| \(.name) | \(.conclusion) | \(((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601)))s |"' 2>/dev/null || true)
fi
[[ -n "$TIMES" ]] || TIMES="| (sin datos: falta permiso actions: read o token) | | |"

WF="${SERVER}/${REPO}/actions/workflows"
cat > evidence/REPORTE.md <<MD
# Evidencias de ejecucion — ${PROXY_NAME:-poc-customer-v1}

- Commit: [\`${SHA}\`](${SERVER}/${REPO}/commit/${SHA}) · Ref: \`${GITHUB_REF:-local}\` · Run: ${RUN_URL}
- Org Apigee: \`${APIGEE_ORG:-n/a}\` · Generado: $(date -u +%FT%TZ)

| # | Capacidad | Resultado | Evidencia |
|---|---|---|---|
| 1 | Control de versiones | ${C1} | [historial](${SERVER}/${REPO}/commits/main) · [tags](${SERVER}/${REPO}/tags) |
| 2 | Validacion automatica | $(icon "$(res validate)") | artifact evidence-validate-* (apigeelint, schema, bundle, gitleaks) |
| 3 | Deploy DEV | $(icon "$(res deploy-dev)") | **r${devrev}** · evidence-dev/deploy-dev.json |
| 4 | Prueba invocacion | $(icon "$(res deploy-dev)") · ${TESTS} · latencia ${LAT} | evidence-dev/pytest-dev.xml, latency-dev.json |
| 5 | Promocion DEV->QA | siguiente paso (gate manual) | [promote-qa](${WF}/promote-qa.yml) con \`dev_run_id=${GITHUB_RUN_ID:-0}\` |
| 6 | Parametrizacion | ver tabla abajo | config/<env>/env.json + variables por environment |
| 7 | Proxy/policies/KVM/TS/product | $(icon "$(res deploy-dev)") | pasos "Configuracion" y "API product + app" del job deploy-dev |
| 8 | Secretos | $(icon "$(res validate)") | gitleaks + vault -> KVM cifrado + logs enmascarados (***) |
| 9 | Trazabilidad | $(icon "$(res deploy-dev)") | comentario en el commit + summary del job (links a commit, run y consola) |
| 10 | Rollback | bajo demanda | [rollback](${WF}/rollback.yml) (N-1 o revision explicita + pruebas) |
| 11 | Evidencias | este reporte | artifact evidence-report-${GITHUB_RUN_ID:-0} |

## Parametrizacion por ambiente (C6)
| Ambiente | Cuota | Truststore | App | Etiqueta KVM |
|---|---|---|---|---|
${C6_TABLE}

## Comandos ejecutados
\`\`\`
scripts/validate.sh                       # xmllint, check_bundle, schema, consistencia, apigeelint
scripts/build.sh                          # zip determinista + sha256 (build-info.json)
scripts/apply_config.sh dev               # target server + KVM cifrado (vault -> KVM)
scripts/deploy.sh dev                     # apigeecli apis create bundle / apis deploy --ovr --wait
scripts/apply_products.sh dev             # API product + developer + app
pytest tests/ -v                          # invocacion: 200, payload, correlation-id, < 500 ms, errores
scripts/trace.sh dev <revision>           # comentario commit -> run -> revision
\`\`\`

## Tiempos por job
| Job | Resultado | Duracion |
|---|---|---|
${TIMES}
MD
cat evidence/REPORTE.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
cat evidence/REPORTE.md
