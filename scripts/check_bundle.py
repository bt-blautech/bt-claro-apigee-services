#!/usr/bin/env python3
"""Valida coherencia del bundle de Apigee.

Comprueba:
- un unico descriptor
- policies declaradas, existentes y referenciadas en ambos sentidos
- ProxyEndpoint/TargetEndpoint declarados contra archivos y viceversa
- nombre de archivo igual al atributo name
- RouteRule apuntando a un target declarado
- policies obligatorias del caso de uso

Solo usa la libreria estandar.
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else "apiproxy")
errors = []


def declared_names(element, tag):
    if element is None:
        return []
    return [
        node.text.strip()
        for node in element.iter(tag)
        if node.text and node.text.strip()
    ]


descriptors = sorted(root.glob("*.xml"))
if len(descriptors) != 1:
    errors.append(
        f"Debe existir exactamente un descriptor en {root}/*.xml (hay {len(descriptors)})"
    )
descriptor = ET.parse(descriptors[0]).getroot() if len(descriptors) == 1 else None

policy_files = {}
for file in sorted((root / "policies").glob("*.xml")):
    name = ET.parse(file).getroot().get("name")
    if name != file.stem:
        errors.append(f"{file}: atributo name='{name}' no coincide con el archivo")
    policy_files[file.stem] = file

declared_policies = declared_names(descriptor, "Policy")
for name, count in Counter(declared_policies).items():
    if count > 1:
        errors.append(f"Policy declarada mas de una vez: {name}")
declared_policies = set(declared_policies)

proxy_files = {file.stem: file for file in sorted((root / "proxies").glob("*.xml"))}
target_files = {file.stem: file for file in sorted((root / "targets").glob("*.xml"))}

for kind, files in (("ProxyEndpoint", proxy_files), ("TargetEndpoint", target_files)):
    for file in files.values():
        name = ET.parse(file).getroot().get("name")
        if name != file.stem:
            errors.append(f"{file}: atributo name='{name}' no coincide con el archivo")

    names = declared_names(descriptor, kind)
    for name, count in Counter(names).items():
        if count > 1:
            errors.append(f"{kind} declarado mas de una vez: {name}")
    names = set(names)

    for name in sorted(names - set(files)):
        errors.append(f"{kind} declarado sin archivo: {name}")
    for name in sorted(set(files) - names):
        errors.append(f"{kind} sin declarar en el descriptor: {name}")

referenced = set()
for file in list(proxy_files.values()) + list(target_files.values()):
    for step in ET.parse(file).getroot().iter("Step"):
        name = step.findtext("Name")
        if not name or not name.strip():
            errors.append(f"{file}: Step sin Name")
            continue
        name = name.strip()
        referenced.add(name)
        if name not in policy_files:
            errors.append(f"{file}: Step referencia policy inexistente '{name}'")

declared_targets = set(declared_names(descriptor, "TargetEndpoint"))
for file in proxy_files.values():
    for route_rule in ET.parse(file).getroot().iter("RouteRule"):
        target = route_rule.findtext("TargetEndpoint")
        if not target or not target.strip():
            errors.append(f"{file}: RouteRule sin TargetEndpoint")
        elif target.strip() not in declared_targets:
            errors.append(f"{file}: RouteRule apunta a target no declarado '{target.strip()}'")

for name in sorted(declared_policies - set(policy_files)):
    errors.append(f"Policy declarada sin archivo: {name}")
for name in sorted(referenced - declared_policies):
    errors.append(f"Policy referenciada pero no declarada en el descriptor: {name}")
for name in sorted(set(policy_files) - referenced):
    errors.append(f"Policy huerfana (no usada en ningun Step): {name}")

REQUIRED_TYPES = {
    "VerifyAPIKey",
    "Quota",
    "SpikeArrest",
    "JSONThreatProtection",
    "AssignMessage",
    "RaiseFault",
}
used_types = {
    ET.parse(policy_files[name]).getroot().tag
    for name in referenced
    if name in policy_files
}
for policy_type in sorted(REQUIRED_TYPES - used_types):
    errors.append(f"Falta policy obligatoria del caso de uso: {policy_type}")

vak = [
    name
    for name in referenced
    if name in policy_files
    and ET.parse(policy_files[name]).getroot().tag == "VerifyAPIKey"
]
for name in vak:
    ref = ET.parse(policy_files[name]).getroot().find("APIKey").get("ref")
    if ref != "request.header.x-apikey":
        errors.append(f"{name}: la apikey debe leerse de request.header.x-apikey (es {ref})")

for error in errors:
    print(f"ERROR: {error}")
print(
    f"bundle: {len(policy_files)} policies, {len(referenced)} referenciadas, "
    f"{len(errors)} errores"
)
sys.exit(1 if errors else 0)
