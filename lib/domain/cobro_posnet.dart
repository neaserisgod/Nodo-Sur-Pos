// Clasificación de estados de una orden de Mercado Pago (Fase 12, Orders
// API) — tabla real de `status`/`status_detail` verificada contra la
// documentación (no un supuesto): `processed` es la única familia de
// aprobado; `failed`/`canceled`/`expired` son rechazo definitivo;
// cualquier otra cosa (`created`, `processing`, `action_required`, y
// cualquier valor que la API agregue en el futuro sin que esta lista se
// actualice) se trata como pendiente — seguir consultando, nunca inventar
// un rechazo por un estado que no se reconoce.

enum ResultadoOrdenCobro { aprobada, rechazada, pendiente }

/// Ritmo del polling de una orden de cobro (Fase 12) — compartido entre el
/// diálogo de escritorio y el de la companion app (Regla 3: un solo lugar
/// para "cada cuánto" y "hasta cuándo", no una copia por pantalla).
const intervaloPollingCobroPosnet = Duration(seconds: 2);
const timeoutPollingCobroPosnet = Duration(seconds: 60);

const _estadosRechazados = {'failed', 'canceled', 'expired'};

/// [status] es el campo de nivel superior de la respuesta de
/// `GET /v1/orders/{id}` — nunca `status_detail` (ese es solo el detalle
/// legible, no el que decide aprobado/rechazado/pendiente).
ResultadoOrdenCobro clasificarEstadoOrden(String status) {
  if (status == 'processed') return ResultadoOrdenCobro.aprobada;
  if (_estadosRechazados.contains(status)) return ResultadoOrdenCobro.rechazada;
  return ResultadoOrdenCobro.pendiente;
}
