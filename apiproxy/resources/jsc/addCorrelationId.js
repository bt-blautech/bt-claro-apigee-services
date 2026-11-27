// Agrega correlationId al JSON de las respuestas exitosas (el header x-correlation-id ya lo cubre).
// Las verificaciones de status y Content-Type viven aqui (y no en la Condition del Step) porque las
// condiciones de Apigee no aplican regex de forma fiable sobre variables numericas como
// response.status.code. Si el cuerpo no es un objeto JSON, se deja intacto.
// Resultado visible en Trace: variable correlation.body = added | skipped:<motivo> | error:<mensaje>
function addCorrelationId() {
    "use strict";
    var status = parseInt(context.getVariable("response.status.code"), 10);
    if (!(status >= 200 && status < 300)) {
        return "skipped:status-" + status;
    }
    var contentType = String(context.getVariable("response.header.Content-Type") || "").toLowerCase();
    if (contentType.indexOf("application/json") !== 0) {
        return "skipped:content-type";
    }
    var raw = context.getVariable("response.content");
    if (!raw) {
        return "skipped:empty-body";
    }
    var body = JSON.parse(raw);
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
        return "skipped:not-object";
    }
    body.correlationId = String(context.getVariable("request.header.x-correlation-id") || "");
    context.setVariable("response.content", JSON.stringify(body));
    return "added";
}

try {
    context.setVariable("correlation.body", addCorrelationId());
} catch (e) {
    context.setVariable("correlation.body", "error:" + e);
}
