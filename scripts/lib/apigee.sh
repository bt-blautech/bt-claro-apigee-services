#!/usr/bin/env bash
# Funciones comunes para la API de Apigee X (REST v1).
# Requiere: APIGEE_ORG y APIGEE_TOKEN en el entorno. Nunca imprime el token.
set -euo pipefail

APIGEE_API="https://apigee.googleapis.com/v1/organizations/${APIGEE_ORG:?APIGEE_ORG requerido}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# api METHOD PATH [JSON_BODY] -> imprime body, falla si HTTP >= 400 (sin volcar headers)
api() {
  local method=$1 path=$2 body=${3:-}
  local out code
  out=$(mktemp)
  if [[ -n "$body" ]]; then
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${APIGEE_API}${path}" \
      -H "Authorization: Bearer ${APIGEE_TOKEN:?}" -H 'Content-Type: application/json' -d "$body")
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "${APIGEE_API}${path}" \
      -H "Authorization: Bearer ${APIGEE_TOKEN:?}")
  fi
  if [[ "$code" -ge 400 ]]; then
    log "ERROR HTTP $code en $method $path"; jq -c '.error // .' "$out" >&2 || cat "$out" >&2
    rm -f "$out"; return 1
  fi
  cat "$out"; rm -f "$out"
}

# api_exists PATH -> 0 si existe (HTTP 200)
api_exists() {
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' "${APIGEE_API}$1" -H "Authorization: Bearer ${APIGEE_TOKEN:?}")
  [[ "$code" == "200" ]]
}

# Revision desplegada actualmente de un proxy en un ambiente (vacio si no hay)
deployed_revision() {
  local proxy=$1 env=$2
  api GET "/environments/${env}/apis/${proxy}/deployments" 2>/dev/null \
    | jq -r '[.deployments[]?.revision] | max // empty'
}

# Busca la revision cuyo Description contiene sha=<SHA> (build-once / trazabilidad inversa)
find_revision_by_sha() {
  local proxy=$1 sha=$2 rev
  api_exists "/apis/${proxy}" || return 0
  for rev in $(api GET "/apis/${proxy}/revisions" | jq -r '.[]' | sort -n -r); do
    if api GET "/apis/${proxy}/revisions/${rev}" | jq -e --arg s "sha=${sha};" '.description // "" | contains($s)' >/dev/null; then
      echo "$rev"; return 0
    fi
  done
}

# Espera a que la revision quede READY en el ambiente
wait_ready() {
  local proxy=$1 env=$2 rev=$3 state i
  for i in $(seq 1 60); do
    state=$(api GET "/environments/${env}/apis/${proxy}/revisions/${rev}/deployments" | jq -r '.state // "UNKNOWN"')
    log "estado despliegue ${proxy} r${rev} en ${env}: ${state}"
    [[ "$state" == "READY" ]] && return 0
    [[ "$state" == "ERROR" ]] && return 1
    sleep 5
  done
  return 1
}
