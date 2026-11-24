#!/usr/bin/env bash
# Capacidad 10: rollback a la revision N-1 (o a una revision explicita) en un ambiente.
# Uso: rollback.sh <env> [revision_objetivo]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/apigee.sh
ENV=${1:?ambiente requerido}
TARGET=${2:-}
PROXY=${PROXY_NAME:-poc-customer-v1}

CURRENT=$(deployed_revision "$PROXY" "$ENV")
[[ -n "$CURRENT" ]] || { log "no hay revision desplegada en ${ENV}"; exit 1; }
if [[ -z "$TARGET" ]]; then
  TARGET=$(api GET "/apis/${PROXY}/revisions" | jq -r --argjson c "$CURRENT" '[.[] | tonumber | select(. < $c)] | max // empty')
fi
[[ -n "$TARGET" ]] || { log "no existe revision anterior a ${CURRENT}"; exit 1; }
log "ROLLBACK ${PROXY} en ${ENV}: r${CURRENT} -> r${TARGET}"
EXPECTED_SHA=$(api GET "/apis/${PROXY}/revisions/${TARGET}" | jq -r '.description' | sed -n 's/.*sha=\([^;]*\).*/\1/p')
scripts/deploy.sh "$ENV" "$TARGET" >/dev/null
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  { echo "from_revision=${CURRENT}"; echo "to_revision=${TARGET}"; echo "expected_sha=${EXPECTED_SHA}"; } >> "$GITHUB_OUTPUT"
fi
jq -n --arg env "$ENV" --arg from "$CURRENT" --arg to "$TARGET" --arg sha "$EXPECTED_SHA" \
  '{env:$env, from_revision:$from, to_revision:$to, expected_sha:$sha, at:(now|todate)}' | tee "evidence/rollback-${ENV}.json"
