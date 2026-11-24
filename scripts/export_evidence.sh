#!/usr/bin/env bash
# Entregable E5 / Cap. 11: exporta las evidencias de la PoC a evidence/export-<fecha>/
#   - runs.json y, por run: run-<id>.json (jobs, pasos, tiempos, conclusion) y run-<id>.log (log completo)
#   - apigee/*.json: revisiones, despliegues por ambiente, target servers, KVM (solo nombres), producto y apps
#     (sin consumer keys ni valores de KVM)
#   - index.html: resumen navegable (capacidad -> run -> resultado) para adjuntar al formulario E1
# Uso: PROJECT_ID=mi-proyecto scripts/export_evidence.sh <owner/repo> [cantidad_de_runs=15]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
REPO=${1:?uso: export_evidence.sh <owner/repo> [n]}; N=${2:-15}
ORG=${PROJECT_ID:?PROJECT_ID requerido}; PROXY=${PROXY_NAME:-poc-customer-v1}
OUT="evidence/export-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT/runs" "$OUT/apigee"
A="https://apigee.googleapis.com/v1/organizations/${ORG}"; T=$(gcloud auth print-access-token)
get() { curl -s -H "Authorization: Bearer $T" "$A$1"; }

echo "==> Runs de GitHub Actions (${REPO})"
gh run list -R "$REPO" --limit "$N" --json databaseId,workflowName,headBranch,headSha,event,status,conclusion,createdAt,updatedAt,url > "$OUT/runs.json"
for id in $(jq -r '.[].databaseId' "$OUT/runs.json"); do
  gh run view "$id" -R "$REPO" --json databaseId,workflowName,headBranch,headSha,event,conclusion,createdAt,updatedAt,url,jobs > "$OUT/runs/run-$id.json"
  gh run view "$id" -R "$REPO" --log > "$OUT/runs/run-$id.log" 2>/dev/null || echo "(log no disponible)" > "$OUT/runs/run-$id.log"
  echo "  run $id: $(jq -r '"\(.workflowName) \(.headBranch) -> \(.conclusion)"' "$OUT/runs/run-$id.json")"
done

echo "==> Estado de Apigee (${ORG})"
get "/apis/${PROXY}/revisions" > "$OUT/apigee/revisions.json"
for r in $(jq -r '.[]' "$OUT/apigee/revisions.json"); do get "/apis/${PROXY}/revisions/$r" | jq '{revision, description, createdAt, policies, proxies, targets}' > "$OUT/apigee/revision-$r.json"; done
get "/apis/${PROXY}/deployments" > "$OUT/apigee/deployments.json"
for E in $(get "/environments" | jq -r '.[]'); do
  get "/environments/$E/targetservers/poc-customer-backend" | jq '{name, host, port, sSLInfo}' > "$OUT/apigee/targetserver-$E.json" 2>/dev/null || true
  get "/environments/$E/keyvaluemaps/poc-customer-config/entries" | jq '{env: "'"$E"'", keys: [.keyValueEntries[]?.name], nota: "valores omitidos"}' > "$OUT/apigee/kvm-$E.json" 2>/dev/null || true
done
get "/apiproducts/poc-product" > "$OUT/apigee/apiproduct.json"
get "/developers/poc-tester@blautech.example/apps?expand=true" | jq '[.app[]? | {name, status, apiProducts: [.credentials[0].apiProducts[]?.apiproduct], attributes, nota: "consumer keys omitidas"}]' > "$OUT/apigee/apps.json"

echo "==> Verificacion de secretos: ningun valor del vault ni consumer key en lo exportado"
leaks=0
for E in dev qa; do
  S=$(gcloud secrets versions access latest --secret="${APIGEE_NAME:-poc}-${E}-api-secret" --project="$ORG" 2>/dev/null || true)
  K=$(get "/developers/poc-tester@blautech.example/apps/poc-app-$E" | jq -r '.credentials[0].consumerKey // empty')
  for v in "$S" "$K"; do [[ -n "$v" ]] && grep -rqF -- "$v" "$OUT" && leaks=$((leaks+1)); done
  unset S K
done
echo "  coincidencias: $leaks" | tee "$OUT/secret-scan.txt"

echo "==> index.html"
python3 - "$OUT" "$REPO" <<'PY'
import json, sys, html, glob, os, datetime
out, repo = sys.argv[1], sys.argv[2]
runs = json.load(open(f"{out}/runs.json"))
deps = json.load(open(f"{out}/apigee/deployments.json")).get("deployments", [])
leaks = open(f"{out}/secret-scan.txt").read().strip()
def dur(r):
    try:
        a = datetime.datetime.fromisoformat(r["createdAt"].replace("Z", "+00:00")); b = datetime.datetime.fromisoformat(r["updatedAt"].replace("Z", "+00:00"))
        return f"{int((b-a).total_seconds()//60)}m {int((b-a).total_seconds()%60)}s"
    except Exception: return "-"
caps = {"ci-validate": "C2", "cd-pipeline": "C2 · C3 · C4 · C6 · C7 · C8 · C9 · C11", "promote-qa": "C5 · C6 · C9", "rollback": "C10", "infra-terraform": "IaC"}
rows = "".join(
    f"<tr class='{html.escape(r.get('conclusion') or 'pending')}'><td><a href='{r['url']}'>{r['databaseId']}</a></td><td>{html.escape(r['workflowName'])}</td>"
    f"<td>{caps.get(r['workflowName'], '')}</td><td>{html.escape(r['headBranch'])}</td><td><code>{r['headSha'][:7]}</code></td>"
    f"<td>{html.escape(r.get('conclusion') or r['status'])}</td><td>{r['createdAt'][:16].replace('T', ' ')}</td><td>{dur(r)}</td>"
    f"<td><a href='runs/run-{r['databaseId']}.json'>json</a> · <a href='runs/run-{r['databaseId']}.log'>log</a></td></tr>" for r in runs)
def ts(ms):
    try: return datetime.datetime.fromtimestamp(int(ms) / 1000, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    except Exception: return "-"
drows = "".join(f"<tr><td>{d['environment']}</td><td>r{d['revision']}</td><td>{ts(d.get('deployStartTime'))}</td></tr>" for d in deps)
files = "".join(f"<li><a href='apigee/{os.path.basename(f)}'>{os.path.basename(f)}</a></li>" for f in sorted(glob.glob(f"{out}/apigee/*.json")))
doc = f"""<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Evidencias PoC Apigee</title>
<style>body{{font-family:Arial,sans-serif;margin:24px;color:#202124}}table{{border-collapse:collapse;width:100%;margin:12px 0}}
td,th{{border:1px solid #dadce0;padding:6px 8px;font-size:13px;text-align:left}}th{{background:#1a3d6e;color:#fff}}
tr.success td:nth-child(6){{color:#188038;font-weight:bold}}tr.failure td:nth-child(6){{color:#c5221f;font-weight:bold}}code{{font-size:12px}}</style></head><body>
<h1>Evidencias de ejecución — PoC CI/CD Apigee (Claro CENAM)</h1>
<p>Repositorio: <a href="https://github.com/{repo}">{repo}</a> · Generado: {datetime.datetime.now():%Y-%m-%d %H:%M} · Verificación de secretos en lo exportado: <b>{html.escape(leaks)}</b></p>
<h2>Runs de GitHub Actions</h2><table><tr><th>Run</th><th>Workflow</th><th>Capacidades</th><th>Rama/tag</th><th>Commit</th><th>Resultado</th><th>Inicio (UTC)</th><th>Duración</th><th>Archivos</th></tr>{rows}</table>
<h2>Revisiones desplegadas en Apigee</h2><table><tr><th>Ambiente</th><th>Revisión</th><th>Despliegue</th></tr>{drows}</table>
<h2>Estado de Apigee (JSON)</h2><ul>{files}</ul></body></html>"""
open(f"{out}/index.html", "w").write(doc)
PY
echo "LISTO: $OUT/index.html"
