#!/usr/bin/env python3
"""Valida coherencia del bundle: cada <Step><Name> existe como policy, cada policy
declarada existe como archivo, el nombre del archivo coincide con el atributo name y no
hay policies huerfanas. Solo libreria estandar."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else "apiproxy")
errors = []

descriptors = list(root.glob("*.xml"))
if len(descriptors) != 1:
    errors.append(f"Debe existir exactamente un descriptor en {root}/*.xml (hay {len(descriptors)})")

policy_files = {}
for f in (root / "policies").glob("*.xml"):
    name = ET.parse(f).getroot().get("name")
    if name != f.stem:
        errors.append(f"{f}: atributo name='{name}' no coincide con el archivo")
    policy_files[f.stem] = f

declared = set()
if descriptors:
    declared = {p.text for p in ET.parse(descriptors[0]).getroot().iter("Policy")}

referenced = set()
for f in list((root / "proxies").glob("*.xml")) + list((root / "targets").glob("*.xml")):
    for step in ET.parse(f).getroot().iter("Step"):
        n = step.findtext("Name")
        referenced.add(n)
        if n not in policy_files:
            errors.append(f"{f}: Step referencia policy inexistente '{n}'")

for p in declared - set(policy_files):
    errors.append(f"Policy declarada sin archivo: {p}")
for p in set(policy_files) - referenced:
    errors.append(f"Policy huerfana (no usada en ningun Step): {p}")

# Caso de uso Claro: las 5 policies obligatorias deben estar presentes y en uso
REQUIRED = {"VerifyAPIKey", "Quota", "SpikeArrest", "JSONThreatProtection", "AssignMessage", "RaiseFault"}
used_types = {ET.parse(policy_files[n]).getroot().tag for n in referenced if n in policy_files}
for t in sorted(REQUIRED - used_types):
    errors.append(f"Falta policy obligatoria del caso de uso: {t}")
vak = [n for n in referenced if n in policy_files and ET.parse(policy_files[n]).getroot().tag == "VerifyAPIKey"]
for n in vak:
    ref = ET.parse(policy_files[n]).getroot().find("APIKey").get("ref")
    if ref != "request.header.x-apikey":
        errors.append(f"{n}: la apikey debe leerse de request.header.x-apikey (es {ref})")

for e in errors:
    print(f"ERROR: {e}")
print(f"bundle: {len(policy_files)} policies, {len(referenced)} referenciadas, {len(errors)} errores")
sys.exit(1 if errors else 0)
