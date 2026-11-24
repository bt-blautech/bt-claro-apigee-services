#!/usr/bin/env bash
# Empaqueta el bundle UNA sola vez por commit, estampando sha/version/run para trazabilidad.
# Salida: dist/poc-customer-v1.zip y dist/build-info.json (con sha256 del zip)
set -euo pipefail
cd "$(dirname "$0")/.."
PROXY=${PROXY_NAME:-poc-customer-v1}
SHA=${GITHUB_SHA:-$(git rev-parse HEAD)}
VERSION=$(cat VERSION)
RUN_ID=${GITHUB_RUN_ID:-local}

rm -rf dist && mkdir -p dist/stage
cp -R apiproxy dist/stage/apiproxy
# Estampado de metadatos (solo en la copia de build, nunca en el codigo fuente)
grep -rl '@@' dist/stage/apiproxy | while read -r f; do
  sed -i.bak -e "s/@@GIT_SHA@@/${SHA}/g" -e "s/@@VERSION@@/${VERSION}/g" -e "s/@@RUN_ID@@/${RUN_ID}/g" "$f" && rm -f "$f.bak"
done
# zip determinista: orden fijo y fechas normalizadas
(cd dist/stage && find apiproxy -exec touch -t 202601010000 {} + && find apiproxy -type f | LC_ALL=C sort | zip -X -q "../${PROXY}.zip" -@)
rm -rf dist/stage

HASH=$(sha256sum "dist/${PROXY}.zip" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "dist/${PROXY}.zip" | cut -d' ' -f1)
jq -n --arg proxy "$PROXY" --arg sha "$SHA" --arg version "$VERSION" --arg run "$RUN_ID" --arg hash "$HASH" \
  '{proxy:$proxy, git_sha:$sha, version:$version, build_run_id:$run, bundle_sha256:$hash, built_at:(now|todate)}' \
  > dist/build-info.json
cat dist/build-info.json
