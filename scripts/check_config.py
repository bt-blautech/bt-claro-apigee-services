#!/usr/bin/env python3
"""Valida config/<env>/env.json contra config/schema.json.
Usa jsonschema si esta instalado; si no, valida campos requeridos (fallback)."""
import json
import sys

schema = json.load(open(sys.argv[1]))
path = sys.argv[2]
doc = json.load(open(path))
try:
    import jsonschema
    errs = [e.message for e in jsonschema.Draft202012Validator(schema).iter_errors(doc)]
except ImportError:
    errs = [f"falta campo requerido '{k}'" for k in schema["required"] if k not in doc]
env_dir = path.split("/")[-2]
if doc.get("environment") != env_dir:
    errs.append(f"environment='{doc.get('environment')}' no coincide con la carpeta '{env_dir}'")
for e in errs:
    print(f"ERROR {path}: {e}")
print(f"{path}: {'OK' if not errs else 'FALLA'}")
sys.exit(1 if errs else 0)
