#!/usr/bin/env bash
# Capacidad 9: trazabilidad commit -> run -> revision Apigee (bidireccional).
#  GitHub -> Apigee: comentario en el commit + job summary con la revision.
#  Apigee -> GitHub: Description de la revision contiene sha=...;run=...
# Uso: trace.sh <env> <revision> [etiqueta]
set -euo pipefail
ENV=$1 REV=$2 LABEL=${3:-deploy}
SHA=${COMMIT_SHA:-$GITHUB_SHA}
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
COMMIT_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${SHA}"
CONSOLE_URL="https://console.cloud.google.com/apigee/proxies/${PROXY_NAME:-poc-customer-v1}/overview?project=${APIGEE_ORG}"
BODY=$(cat <<MD
### Apigee ${LABEL}: \`${PROXY_NAME:-poc-customer-v1}\` → **${ENV}** (org \`${APIGEE_ORG}\`)
| Commit | Workflow run | Revisión Apigee | Hash bundle (sha256 del zip desplegado) |
|---|---|---|---|
| [\`${SHA:0:12}\`](${COMMIT_URL}) | [${GITHUB_RUN_ID}](${RUN_URL}) (intento ${GITHUB_RUN_ATTEMPT}) | [**r${REV}**](${CONSOLE_URL}) | \`${BUNDLE_SHA256:-n/a}\` |

Inverso (Apigee → GitHub): la revisión r${REV} tiene \`Description = sha=${SHA:0:12}…;run=…\`; workflow **trace-revision** con \`revision=${REV}\`.
El *digest* que GitHub muestra en Artifacts es del contenedor del artifact; el hash de arriba es el del zip que se desplegó.
MD
)
echo "$BODY" >> "$GITHUB_STEP_SUMMARY"
gh api "repos/${GITHUB_REPOSITORY}/commits/${SHA}/comments" -f body="$BODY" >/dev/null \
  && echo "comentario de trazabilidad publicado en el commit ${SHA}"
