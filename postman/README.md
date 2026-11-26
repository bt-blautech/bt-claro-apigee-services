# Postman · poc-customer-v1

| Archivo | Uso |
|---|---|
| `poc-customer-v1.postman_collection.json` | Colección de la API |
| `poc-customer-v1-dev.postman_environment.json` | Entorno DEV |
| `poc-customer-v1-qa.postman_environment.json` | Entorno QA |

## Importar en Postman u otro editor

La colección usa el formato Postman v2.1, que también pueden importar Insomnia, Bruno y otros clientes HTTP.

1. Abrir el editor (Postman, Insomnia, Bruno, etc.).
2. Buscar la opción **Import**.
3. Seleccionar o arrastrar estos archivos:
   - `poc-customer-v1.postman_collection.json`
   - `poc-customer-v1-dev.postman_environment.json` o `poc-customer-v1-qa.postman_environment.json`
4. Confirmar la importación.
5. Seleccionar el entorno importado.
6. Editar el entorno y completar:
   - `host`: hostname del environment group.
   - `apiKey`: consumer key de la app del ambiente.

## Ejecutar los tests en Postman

1. Seleccionar la colección `poc-customer-v1`.
2. Clic en **Run** (Collection Runner).
3. Elegir el entorno DEV o QA.
4. Clic en **Run poc-customer-v1**.
5. Revisar la pestaña **Tests** de cada request.

## Ejecutar los tests con Newman

Instalar Newman:

```bash
npm install -g newman
```

Ejecutar toda la colección en DEV:

```bash
newman run postman/poc-customer-v1.postman_collection.json \
  -e postman/poc-customer-v1-dev.postman_environment.json
```

Ejecutar toda la colección en QA:

```bash
newman run postman/poc-customer-v1.postman_collection.json \
  -e postman/poc-customer-v1-qa.postman_environment.json
```

Ejecutar solo una carpeta:

```bash
newman run postman/poc-customer-v1.postman_collection.json \
  -e postman/poc-customer-v1-dev.postman_environment.json \
  --folder "Operaciones"
```

Carpetas disponibles: `Operaciones`, `Errores`, `Trazabilidad`.
