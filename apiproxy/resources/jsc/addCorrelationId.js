// Agrega correlationId al JSON de las respuestas exitosas (el header x-correlation-id ya lo cubre).
// Si el cuerpo no es un objeto JSON, se deja intacto para no alterar el contrato del backend.
try {
    var raw = context.getVariable("response.content");
    if (raw) {
        var body = JSON.parse(raw);
        if (body !== null && typeof body === "object" && !Array.isArray(body)) {
            body.correlationId = context.getVariable("request.header.x-correlation-id");
            context.setVariable("response.content", JSON.stringify(body));
        }
    }
} catch (e) {
    // Cuerpo no-JSON: la trazabilidad sigue garantizada por el header de respuesta.
}
