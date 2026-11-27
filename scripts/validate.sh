#!/usr/bin/env bash
# Capacidad 2: validacion automatica del artefacto. Sale con codigo != 0 ante cualquier error.
set -euo pipefail
cd "$(dirname "$0")/.."
REPORT_DIR=${REPORT_DIR:-evidence/validate}
mkdir -p "$REPORT_DIR"
fail=0

echo "==> 1/5 Sintaxis XML de proxy y policies (xmllint)"
if command -v xmllint >/dev/null; then
  find apiproxy -name '*.xml' -print0 | xargs -0 xmllint --noout || fail=1
else  # runners sin libxml2-utils: mismo chequeo de buena formacion con el parser de Python
  python3 -c 'import sys, xml.etree.ElementTree as ET
bad = 0
for f in sys.argv[1:]:
    try: ET.parse(f)
    except ET.ParseError as e: print(f"ERROR XML {f}: {e}"); bad = 1
print(f"{len(sys.argv)-1} archivos XML bien formados" if not bad else "XML invalido"); sys.exit(bad)' $(find apiproxy -name '*.xml') || fail=1
fi

echo "==> 2/5 Estructura del bundle (policies y endpoints declarados vs archivos)"
python3 scripts/check_bundle.py apiproxy || fail=1

echo "==> 3/5 Esquema de configuracion (ambiente y compartida)"
for f in config/*/env.json; do
  python3 scripts/check_config.py config/schema.json "$f" || fail=1
done
python3 scripts/check_config.py config/schema-product.json config/shared/product.json || fail=1
python3 scripts/check_config.py config/schema-developer.json config/shared/developer.json || fail=1

echo "==> 4/5 Coherencia entre config y apiproxy"
python3 scripts/check_consistency.py || fail=1

echo "==> 5/5 apigeelint"
npx --yes apigeelint@2 -s apiproxy -f json.js --profile apigeex > "$REPORT_DIR/apigeelint.json" || true
npx --yes apigeelint@2 -s apiproxy -f table.js --profile apigeex | tee "$REPORT_DIR/apigeelint.txt" || true
errors=$(jq '[.[].errorCount] | add // 0' "$REPORT_DIR/apigeelint.json")
warnings=$(jq '[.[].warningCount] | add // 0' "$REPORT_DIR/apigeelint.json")
echo "apigeelint: errores=${errors} warnings=${warnings}"
[[ "$errors" -gt 0 ]] && fail=1

if [[ $fail -ne 0 ]]; then
  echo "VALIDACION FALLIDA" >&2; exit 1
fi
echo "VALIDACION OK"
