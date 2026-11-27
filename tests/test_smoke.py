"""Capacidad 4 (Paso 4 y 6 del caso de uso) y validacion post-rollback (Cap. 10).

Variables de entorno:
  APIGEE_ENV         dev | qa
  APIGEE_HOST        hostname del environment group (ej. dev.<IP-del-LB>.nip.io; ver terraform output hostnames)
  APP_API_KEY        consumer key de la app del ambiente (enmascarada en logs)
  EXPECTED_REVISION  (opcional) revision que debe responder (rollback)
  EXPECTED_SHA       (opcional) commit que debe responder (por defecto GITHUB_SHA)
"""
import json
import os
import time
import uuid
from pathlib import Path

import pytest
import requests

ENV = os.environ["APIGEE_ENV"]
HOST = os.environ["APIGEE_HOST"]
KEY = os.environ["APP_API_KEY"]
CFG = json.loads(Path(__file__).parents[1].joinpath("config", ENV, "env.json").read_text())
BASE = f"https://{HOST}{CFG['smoke']['path']}"
MAX_MS = CFG["smoke"]["maxLatencyMs"]
# Sesion HTTP con keep-alive: mide la latencia del API (Apigee + backend) y no el saludo TCP/TLS
# de cada conexion nueva, que depende de la distancia entre quien ejecuta la prueba y Google.
SESSION = requests.Session()
PAYLOAD = {"nombre": "Cliente POC", "documento": "12345678", "segmento": "CENAM", "correo": "poc@cenam.claro.com"}


def call(method, url, **kw):
    """Reintenta mientras la configuracion propaga (KVM con cache de 60 s, app recien creada)."""
    kw.setdefault("timeout", 15)
    last = None
    for _ in range(10):
        last = SESSION.request(method, url, **kw)
        if last.status_code not in (401, 403, 502, 503) or "headers" in kw and "x-apikey" not in kw["headers"]:
            break
        time.sleep(6)
    print(f"{method} {url} -> {last.status_code} {last.elapsed.total_seconds()*1000:.0f} ms "
          f"rev={last.headers.get('X-Proxy-Revision')} env={last.headers.get('X-Environment')} "
          f"cid={last.headers.get('x-correlation-id')}")
    return last


@pytest.fixture(scope="module")
def listado():
    for _ in range(3):  # calentamiento: KVM (cache 60 s), cuota y conexion keep-alive
        call("GET", BASE + "/customers", headers={"x-apikey": KEY})
    return call("GET", BASE + "/customers?page=1&size=2", headers={"x-apikey": KEY})


# ---------- Paso 4 / C4: GET /customers con apikey valida -----------------------------
def test_listado_200(listado):
    assert listado.status_code == 200, listado.text[:300]


def test_listado_payload_paginado(listado):
    body = listado.json()
    assert isinstance(body["items"], list) and len(body["items"]) <= 2
    assert body["page"] == 1 and body["size"] == 2 and body["total"] >= 1


def test_listado_correlation_id(listado):
    cid = listado.headers.get("x-correlation-id", "")
    assert len(cid) >= 32, "falta x-correlation-id (uuid)"


def test_listado_correlation_id_en_body(listado):
    cid = listado.headers.get("x-correlation-id", "")
    body_cid = listado.json().get("correlationId")
    assert body_cid == cid, (
        f"el body 2xx debe incluir el mismo correlationId "
        f"(body={body_cid!r}, header={cid!r}, rev={listado.headers.get('X-Proxy-Revision')!r})"
    )


def test_listado_latencia_menor_500ms(listado):
    assert listado.elapsed.total_seconds() * 1000 < MAX_MS


# ---------- Paso 6 / C6: el ambiente usa su propio target/KVM -------------------------
def test_backend_y_kvm_del_ambiente(listado):
    assert listado.json()["environment"] == ENV, "el backend (target server) no corresponde al ambiente"
    assert listado.headers.get("X-Environment") == ENV
    assert listado.headers.get("X-Env-Label") == CFG["kvm"]["entries"]["env_label"]


def test_no_expone_secretos(listado):
    hdrs = {k.lower() for k in listado.headers}
    assert "x-api-secret" not in hdrs and "x-apikey" not in hdrs


# ---------- Operaciones del caso de uso ------------------------------------------------
def test_get_por_id():
    r = call("GET", BASE + "/customers/1", headers={"x-apikey": KEY})
    assert r.status_code == 200 and r.json()["id"] == "1"
    assert r.json().get("correlationId") == r.headers.get("x-correlation-id")


def test_post_crea_cliente():
    r = call("POST", BASE + "/customers", headers={"x-apikey": KEY}, json=PAYLOAD)
    assert r.status_code == 201, r.text[:300]
    assert r.json()["documento"] == PAYLOAD["documento"]
    assert r.json().get("correlationId") == r.headers.get("x-correlation-id")


def test_correlation_id_del_cliente_se_conserva():
    cid = str(uuid.uuid4())
    r = call("GET", BASE + "/customers/1", headers={"x-apikey": KEY, "x-correlation-id": cid})
    assert r.headers.get("x-correlation-id") == cid
    assert r.json().get("correlationId") == cid


# ---------- Seguridad y manejo de errores (policies obligatorias) ----------------------
def test_sin_apikey_401_json():
    r = call("GET", BASE + "/customers", headers={})
    assert r.status_code == 401
    assert "error" in r.json() and r.json()["error"]["correlationId"]


def test_payload_mayor_2kb_413():
    big = dict(PAYLOAD, nombre="x" * 250, extra="y" * 2200)
    r = call("POST", BASE + "/customers", headers={"x-apikey": KEY}, json=big)
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "payload_too_large"


def test_content_type_no_json_415():
    r = call("POST", BASE + "/customers",
             headers={"x-apikey": KEY, "Content-Type": "text/plain"},
             data='{"nombre":"Cliente POC","documento":"12345678"}')
    assert r.status_code == 415, r.text[:300]
    assert r.json()["error"]["code"] == "unsupported_media_type"


def test_json_malicioso_rechazado():
    deep = {"a": {"b": {"c": {"d": {"e": {"f": {"g": 1}}}}}}}
    r = call("POST", BASE + "/customers", headers={"x-apikey": KEY}, json=deep)
    assert r.status_code == 400 and r.json()["error"]["code"] == "invalid_payload"


def test_ruta_inexistente_404_json():
    r = call("GET", BASE + "/no-existe", headers={"x-apikey": KEY})
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"


# ---------- Trazabilidad y rollback (C9, C10) -----------------------------------------
def test_revision_esperada(listado):
    exp = os.environ.get("EXPECTED_REVISION")
    if exp:
        assert listado.headers.get("X-Proxy-Revision") == exp


def test_commit_esperado(listado):
    exp = os.environ.get("EXPECTED_SHA") or os.environ.get("GITHUB_SHA")
    if exp:
        assert listado.headers.get("X-Build-Commit") == exp
