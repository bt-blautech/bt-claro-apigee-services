#!/usr/bin/env bash
# Capacidad 7 / Paso 7 del caso de uso: API product, developer y app como codigo.
#  - poc-product (dev + qa), developer compartido y una app por ambiente (credenciales distintas DEV/QA)
# Requiere que el proxy poc-customer-v1 ya exista (Apigee valida los proxies del producto).
# Uso: apply_products.sh <env>     Exporta APP_API_KEY (enmascarada) a $GITHUB_ENV si existe.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/apigee.sh
ENV=${1:?ambiente requerido}
CFG="config/${ENV}/env.json"
r() { jq -r "$1" "$CFG"; }

# --- API product compartido (org-level) -------------------------------------------
PRODUCT=$(jq -r .name config/shared/product.json)
if api_exists "/apiproducts/${PRODUCT}"; then
  api PUT "/apiproducts/${PRODUCT}" "$(jq -c . config/shared/product.json)" >/dev/null; log "API product ${PRODUCT} actualizado"
else
  api POST "/apiproducts" "$(jq -c . config/shared/product.json)" >/dev/null; log "API product ${PRODUCT} creado"
fi

# --- Developer y app del ambiente -------------------------------------------------
DEV_EMAIL=$(jq -r .email config/shared/developer.json)
api_exists "/developers/${DEV_EMAIL}" || { api POST "/developers" "$(jq -c . config/shared/developer.json)" >/dev/null; log "developer ${DEV_EMAIL} creado"; }
APP=$(r .app.name)
if ! api_exists "/developers/${DEV_EMAIL}/apps/${APP}"; then
  api POST "/developers/${DEV_EMAIL}/apps" "$(jq -nc --arg n "$APP" --arg p "$PRODUCT" --arg e "$ENV" \
    '{name:$n, apiProducts:[$p], attributes:[{name:"environment", value:$e}]}')" >/dev/null
  log "app ${APP} creada con producto ${PRODUCT}"
else
  log "app ${APP} ya existe"
fi

KEY=$(api GET "/developers/${DEV_EMAIL}/apps/${APP}" | jq -r '.credentials[0].consumerKey')
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "::add-mask::${KEY}"
  echo "APP_API_KEY=${KEY}" >> "$GITHUB_ENV"
fi
log "producto y app de ${ENV} aplicados (product ${PRODUCT}, app ${APP})"
