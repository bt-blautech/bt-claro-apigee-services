#!/usr/bin/env bash
# Capacidad 7 / Paso 7 del caso de uso: API product, developer y app como codigo.
#  - poc-product (dev + qa), developer compartido y una app por ambiente (credenciales distintas DEV/QA)
# Requiere que el proxy poc-customer-v1 ya exista (Apigee valida los proxies del producto).
# Uso: apply_products.sh <env>     (PRODUCT_FILE / APP_NAME opcionales: preview de PR)  Exporta APP_API_KEY (enmascarada) a $GITHUB_ENV si existe.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/apigee.sh
ENV=${1:?ambiente requerido}
CFG="config/${ENV}/env.json"
r() { jq -r "$1" "$CFG"; }

# --- API product compartido (org-level) -------------------------------------------
PRODUCT_FILE=${PRODUCT_FILE:-config/shared/product.json}
PRODUCT=$(jq -r .name "$PRODUCT_FILE")
# El producto declara todos los ambientes (dev, qa, staging, prod), pero cada org solo tiene los suyos:
# se publican solo los que existen en la org destino (dev/qa en la principal, staging/prod en la aislada).
ORG_ENVS=$(api GET "/environments")
PRODUCT_BODY=$(jq -c --argjson envs "$ORG_ENVS" '.environments |= map(select(. as $e | $envs | index($e)))' "$PRODUCT_FILE")
if api_exists "/apiproducts/${PRODUCT}"; then
  api PUT "/apiproducts/${PRODUCT}" "$PRODUCT_BODY" >/dev/null; log "API product ${PRODUCT} actualizado"
else
  api POST "/apiproducts" "$PRODUCT_BODY" >/dev/null; log "API product ${PRODUCT} creado"
fi

# --- Developer y app del ambiente -------------------------------------------------
DEV_EMAIL=$(jq -r .email config/shared/developer.json)
api_exists "/developers/${DEV_EMAIL}" || { api POST "/developers" "$(jq -c . config/shared/developer.json)" >/dev/null; log "developer ${DEV_EMAIL} creado"; }
APP=${APP_NAME:-$(r .app.name)}
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
