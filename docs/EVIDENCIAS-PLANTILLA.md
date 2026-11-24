# Evidencias — Sesión de demostración Apigee CI/CD

**Proveedor:** ______  **Fecha:** ______  **Repositorio:** ______  **Org Apigee:** ______
**Evaluador:** ______  **Hora inicio / fin:** ______ / ______

| # | Capacidad | Crítica | Hora | Comando / acción ejecutada | Run ID / Revisión | Duración | Evidencia (archivo / captura) | Resultado |
|---|---|---|---|---|---|---|---|---|
| 1 | Control de versiones | C | | `git log --graph --oneline --all` · `git tag -n` | | | | ☐ Cumple ☐ Parcial ☐ No |
| 2 | Validación automática | C | | push con error inyectado → run rojo; corrección → verde | | | `apigeelint.json` | ☐ ☐ ☐ |
| 3 | Deploy automático DEV | C | | merge a `develop` | run: ___ rev: ___ | | `deploy-dev.json` | ☐ ☐ ☐ |
| 4 | Prueba de invocación | C | | `pytest -v` / `curl -i` | | | `pytest-dev.xml` | ☐ ☐ ☐ |
| 5 | Promoción mismo artefacto | C | | `git push --tags` + aprobación | rev DEV ___ = rev QA ___ · sha256 ___ | | `deploy-qa.json` | ☐ ☐ ☐ |
| 6 | Parametrización por ambiente | | | `diff config/dev/env.json config/qa/env.json` | | | headers `X-Env-Label` | ☐ ☐ ☐ |
| 7 | Proxy, ≥4 policies, KVM, TS, product | | | `terraform output` · log `apply_config.sh` | | | capturas consola | ☐ ☐ ☐ |
| 8 | Secretos seguros | C | | gitleaks · `gh run view --log \| grep -c <secreto>` = 0 | | | logs con `***` | ☐ ☐ ☐ |
| 9 | Trazabilidad | | | comentario commit · `apigeecli apis get --rev N` | sha ___ ↔ run ___ ↔ rev ___ | | | ☐ ☐ ☐ |
| 10 | Rollback + validación | | | `gh workflow run apigee-rollback.yml -f environment=dev` | r___ → r___ | | `rollback-dev.json`, `pytest-rollback.xml` | ☐ ☐ ☐ |
| 11 | Logs y evidencias | | | `gh run download <id>` | | | `REPORTE.md` | ☐ ☐ ☐ |

## Comandos de recolección

```bash
gh run list --limit 20 > evidence/runs.txt
gh run view <RUN_ID> --log > evidence/run-<RUN_ID>.log
gh run download <RUN_ID> -D evidence/run-<RUN_ID>
```

Observaciones: ____________________________________________
