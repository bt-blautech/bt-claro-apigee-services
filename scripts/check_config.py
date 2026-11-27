#!/usr/bin/env python3
"""Valida un JSON de configuracion contra un esquema.
Uso: check_config.py <schema.json> <archivo.json>

Con jsonschema instalado aplica el esquema completo. Sin esa dependencia hace una
validacion parcial (requeridos y propiedades extra de primer nivel) y lo advierte.
"""
import json
import sys
from pathlib import Path

schema_path = Path(sys.argv[1])
doc_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text())
doc = json.loads(doc_path.read_text())

errs = []
try:
    import jsonschema

    validator = jsonschema.Draft202012Validator(schema)
    for error in validator.iter_errors(doc):
        location = ".".join(str(p) for p in error.path) or "(raiz)"
        errs.append(f"{location}: {error.message}")
except ImportError:
    print("AVISO: jsonschema no esta instalado; validacion parcial", file=sys.stderr)
    if schema.get("type") == "object":
        for key in schema.get("required", []):
            if key not in doc:
                errs.append(f"falta campo requerido '{key}'")
        if schema.get("additionalProperties") is False:
            allowed = set(schema.get("properties", {}))
            for key in sorted(set(doc) - allowed):
                errs.append(f"propiedad no permitida '{key}'")

if "environment" in doc:
    env_dir = doc_path.parent.name
    if doc["environment"] != env_dir:
        errs.append(
            f"environment='{doc['environment']}' no coincide con la carpeta '{env_dir}'"
        )

for error in errs:
    print(f"ERROR {doc_path}: {error}")
print(f"{doc_path}: {'OK' if not errs else 'FALLA'}")
sys.exit(1 if errs else 0)
