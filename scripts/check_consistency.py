#!/usr/bin/env python3
"""Valida coherencia entre config/ y apiproxy/.

Compara base path, target server, KVM y cuota de cada ambiente con lo declarado
en el bundle, y verifica que el API product apunte al proxy y a los ambientes reales.

Solo usa la libreria estandar.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
errors = []


def load_json(path):
    return json.loads(path.read_text())


env_files = sorted((root / "config").glob("*/env.json"))
env_configs = {path.parent.name: load_json(path) for path in env_files}
if not env_configs:
    errors.append("No se encontro ningun config/<env>/env.json")

base_paths = set()
api_names = set()
for path in sorted((root / "apiproxy").glob("*.xml")):
    name = ET.parse(path).getroot().get("name")
    if name:
        api_names.add(name)
for path in sorted((root / "apiproxy" / "proxies").glob("*.xml")):
    element = ET.parse(path).getroot()
    base_path = element.findtext("./HTTPProxyConnection/BasePath")
    if base_path:
        base_paths.add(base_path.strip())
    else:
        errors.append(f"{path}: falta HTTPProxyConnection/BasePath")

target_servers = set()
for path in sorted((root / "apiproxy" / "targets").glob("*.xml")):
    for server in ET.parse(path).getroot().iter("Server"):
        name = server.get("name")
        if name:
            target_servers.add(name)

kvm_names = set()
kvm_policy = root / "apiproxy" / "policies" / "KVM-GetConfig.xml"
if kvm_policy.exists():
    kvm_name = ET.parse(kvm_policy).getroot().get("mapIdentifier")
    if kvm_name:
        kvm_names.add(kvm_name)
    else:
        errors.append(f"{kvm_policy}: falta mapIdentifier")
else:
    errors.append(f"{kvm_policy}: no existe")

for env, config in env_configs.items():
    smoke_path = config.get("smoke", {}).get("path")
    if smoke_path not in base_paths:
        errors.append(
            f"{env}: smoke.path='{smoke_path}' no coincide con ningun BasePath {sorted(base_paths)}"
        )

    target_name = config.get("targetServer", {}).get("name")
    if target_name not in target_servers:
        errors.append(
            f"{env}: targetServer.name='{target_name}' no existe en los targets {sorted(target_servers)}"
        )

    config_kvm = config.get("kvm", {}).get("name")
    if config_kvm not in kvm_names:
        errors.append(
            f"{env}: kvm.name='{config_kvm}' no coincide con mapIdentifier {sorted(kvm_names)}"
        )

    try:
        quota = int(config["kvm"]["entries"]["quota_limit"])
        expected = int(config["smoke"]["expectedQuota"])
    except (KeyError, TypeError, ValueError) as error:
        errors.append(f"{env}: no se pudo comparar la cuota ({error})")
    else:
        if quota != expected:
            errors.append(
                f"{env}: quota_limit={quota} no coincide con smoke.expectedQuota={expected}"
            )

product_path = root / "config" / "shared" / "product.json"
if product_path.exists():
    product = load_json(product_path)
    product_envs = set(product.get("environments", []))
    if product_envs != set(env_configs):
        errors.append(
            f"product.json: environments={sorted(product_envs)} no coincide con config/ {sorted(env_configs)}"
        )
    product_proxies = set(product.get("proxies", []))
    if product_proxies != api_names:
        errors.append(
            f"product.json: proxies={sorted(product_proxies)} no coincide con las APIs {sorted(api_names)}"
        )
else:
    errors.append(f"{product_path}: no existe")

for error in errors:
    print(f"ERROR: {error}")
print(f"consistency: {len(env_configs)} ambientes, {len(errors)} errores")
sys.exit(1 if errors else 0)
