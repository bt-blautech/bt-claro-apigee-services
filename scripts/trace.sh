#!/usr/bin/env bash
# Capacidad 9: trazabilidad commit -> run -> revision Apigee (bidireccional).
#  GitHub -> Apigee: comentario en el commit + job summary con la revision.
#  Apigee -> GitHub: Description de la revision contiene sha=...;run=...
# Uso: trace.sh <env> <revision> [etiqueta]
set -euo pipefail
ENV=$1 REV=$2 LABEL=${3:-deploy}
SHA=${COMMIT_SHA:-$GITHUB_SHA}
RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
BODY=$(cat <<MD
### Apigee ${LABEL}: \`${PROXY_NAME:-poc-customer-v1}\` → **${ENV}**
| Commit | Workflow run | Revisión Apigee | Hash bundle |
|---|---|---|---|
| \`${SHA}\` | [${GITHUB_RUN_ID}](${RUN_URL}) (intento ${GITHUB_RUN_ATTEMPT}) | **r${REV}** | \`${BUNDLE_SHA256:-n/a}\` |
MD
)
echo "$BODY" >> "$GITHUB_STEP_SUMMARY"
gh api "repos/${GITHUB_REPOSITORY}/commits/${SHA}/comments" -f body="$BODY" >/dev/null \
  && echo "comentario de trazabilidad publicado en el commit ${SHA}"
