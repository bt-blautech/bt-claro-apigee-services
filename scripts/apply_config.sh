#!/usr/bin/env bash
# Capacidades 6, 7 y 8: configuracion de RUNTIME de la API por ambiente (antes del despliegue del proxy).
#  - Target server poc-customer-backend: host = variable BACKEND_HOST (publicada por bt-claro-apigee-infrastructure),
#    TLS exigido con el truststore del ambiente si existe su referencia (ref-ts-backend-<env>)
#  - KVM poc-customer-config: quota_limit, env_label, backend_url y api_secret (desde el vault)
# El API product, el developer y la app van en scripts/apply_products.sh (despues de importar el proxy).
# Uso: apply_config.sh <env>
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/apigee.sh
ENV=${1:?ambiente requerido}
CFG="config/${ENV}/env.json"
PROJECT=${PROJECT_ID:-$APIGEE_ORG}
NAME=${APIGEE_NAME:?APIGEE_NAME requerido (nombre base de la plataforma)}
r() { jq -r "$1" "$CFG"; }

# --- Target server (codigo de la API) ----------------------------------------------
TS=$(r .targetServer.name)
HOST_VAR=$(r .targetServer.hostFrom)
TS_HOST=${!HOST_VAR:-}
[[ -n "$TS_HOST" ]] || { log "falta la variable ${HOST_VAR} (la publica bt-claro-apigee-infrastructure/scripts/setup_github.sh)"; exit 1; }
REF=$(r '.targetServer.truststoreRef // empty')
ENFORCE=false; TRUST=null
if [[ -n "$REF" ]] && api_exists "/environments/${ENV}/references/${REF}"; then ENFORCE=true; TRUST="\"ref://${REF}\""; fi
TS_BODY=$(jq -nc --arg n "$TS" --arg h "$TS_HOST" --argjson p "$(r .targetServer.port)" --argjson tls "$(r .targetServer.tls)" \
  --argjson enf "$ENFORCE" --argjson trust "$TRUST" \
  '{name:$n, host:$h, port:$p, isEnabled:true, protocol:"HTTP", sSLInfo:({enabled:$tls, enforce:$enf} + (if $trust then {trustStore:$trust} else {} end))}')
if api_exists "/environments/${ENV}/targetservers/${TS}"; then
  api PUT "/environments/${ENV}/targetservers/${TS}" "$TS_BODY" >/dev/null; accion=actualizado
else
  api POST "/environments/${ENV}/targetservers" "$TS_BODY" >/dev/null; accion=creado
fi
log "target server ${TS} ${accion}: ${TS_HOST}:$(r .targetServer.port) tls=$(r .targetServer.tls) enforce=${ENFORCE} truststore=${REF:-ninguno}"
BACKEND_URL="https://${TS_HOST}/poc-customers/v0"

# --- KVM ---------------------------------------------------------------------------
KVM=$(r .kvm.name)
api_exists "/environments/${ENV}/keyvaluemaps/${KVM}" \
  || api POST "/environments/${ENV}/keyvaluemaps" "{\"name\":\"${KVM}\",\"encrypted\":true}" >/dev/null

upsert_entry() {  # nunca imprime el valor
  local key=$1 value=$2 body
  body=$(jq -nc --arg n "$key" --arg v "$value" '{name:$n, value:$v}')
  if api_exists "/environments/${ENV}/keyvaluemaps/${KVM}/entries/${key}"; then
    api PUT "/environments/${ENV}/keyvaluemaps/${KVM}/entries/${key}" "$body" >/dev/null
  else
    api POST "/environments/${ENV}/keyvaluemaps/${KVM}/entries" "$body" >/dev/null
  fi
  log "KVM ${KVM}/${key} actualizado"
}
for key in $(r '.kvm.entries | keys[]'); do upsert_entry "$key" "$(r ".kvm.entries[\"$key\"]")"; done
upsert_entry backend_url "$BACKEND_URL"
for key in $(r '.kvm.vaultEntries | keys[]'); do
  secret="${NAME}-${ENV}-$(r ".kvm.vaultEntries[\"$key\"]")"   # ej. poc-dev-api-secret
  val=$(gcloud secrets versions access latest --secret="$secret" --project="$PROJECT")
  [[ -n "$val" ]] || { log "el secreto ${secret} esta vacio en el vault"; exit 1; }
  [[ -n "${GITHUB_ENV:-}" ]] && echo "::add-mask::${val}"
  upsert_entry "$key" "$val"
  log "  (origen: vault Secret Manager ${secret}, valor no mostrado)"
  unset val
done
log "configuracion de runtime de ${ENV} aplicada"
