#!/usr/bin/env bash
# Importa (si no existe ya una revision para este SHA) y despliega en un ambiente.
# Uso: deploy.sh <env> [revision]
#   - sin revision: build-once -> reutiliza la revision del SHA o importa dist/<proxy>.zip
#   - con revision: despliega exactamente esa revision (promocion / rollback). Nunca reempaqueta.
# Escribe en $GITHUB_OUTPUT: revision, previous_revision
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/apigee.sh
ENV=${1:?ambiente requerido}
REV=${2:-}
PROXY=${PROXY_NAME:-poc-customer-v1}
SHA=${COMMIT_SHA:-${GITHUB_SHA:-$(git rev-parse HEAD)}}
SA_EMAIL=${APIGEE_RUNTIME_SA:-}

PREV=$(deployed_revision "$PROXY" "$ENV" || true)
log "revision actual en ${ENV}: ${PREV:-ninguna}"

if [[ -z "$REV" ]]; then
  REV=$(find_revision_by_sha "$PROXY" "$SHA")
  if [[ -n "$REV" ]]; then
    log "build-once: ya existe la revision ${REV} para sha=${SHA}; no se reimporta"
  else
    test -f "dist/build-info.json" || { log "falta dist/: ejecute build.sh"; exit 1; }
    log "importando dist/${PROXY}.zip con apigeecli"
    REV=$(apigeecli apis create bundle --name "$PROXY" --proxy-zip "dist/${PROXY}.zip" \
            --org "$APIGEE_ORG" --token "$APIGEE_TOKEN" | jq -r '.revision')
    log "revision importada: ${REV}"
  fi
fi

log "desplegando ${PROXY} r${REV} en ${ENV} (override, sin downtime)"
args=(--name "$PROXY" --env "$ENV" --rev "$REV" --ovr --wait --org "$APIGEE_ORG" --token "$APIGEE_TOKEN")
[[ -n "$SA_EMAIL" ]] && args+=(--sa "$SA_EMAIL")
apigeecli apis deploy "${args[@]}" >/dev/null
wait_ready "$PROXY" "$ENV" "$REV"

DESC=$(api GET "/apis/${PROXY}/revisions/${REV}" | jq -r '.description')
log "desplegado: ${PROXY} r${REV} en ${ENV} | ${DESC}"
mkdir -p evidence
jq -n --arg env "$ENV" --arg proxy "$PROXY" --arg rev "$REV" --arg prev "${PREV:-}" --arg desc "$DESC" \
  --arg sha "$SHA" --arg run "${GITHUB_RUN_ID:-local}" \
  '{env:$env, proxy:$proxy, revision:$rev, previous_revision:$prev, revision_description:$desc, git_sha:$sha, run_id:$run, at:(now|todate)}' \
  | tee "evidence/deploy-${ENV}.json"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "revision=${REV}" >> "$GITHUB_OUTPUT"
  echo "previous_revision=${PREV:-}" >> "$GITHUB_OUTPUT"
fi
