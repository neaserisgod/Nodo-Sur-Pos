// Clasificación de estados de una orden de Mercado Pago (Fase 12, Orders
// API) — tabla real de `status`/`status_detail` verificada contra la
// documentación (no un supuesto): `processed` es la única familia de
// aprobado; `failed`/`canceled`/`expired` son rechazo definitivo;
// cualquier otra cosa (`created`, `processing`, `action_required`, y
// cualquier valor que la API agregue en el futuro sin que esta lista se
// actualice) se trata como pendiente — seguir consultando, nunca inventar
// un rechazo por un estado que no se reconoce.

/// [confirmarEnTerminal]: la Point le pide algo al cliente (`action_required`, ej. confirmar el monto o elegir la cuenta). Para el
/// cobro es lo mismo que [pendiente] (seguir esperando, [sigueEsperando]); solo cambia lo que se muestra en pantalla.
enum ResultadoOrdenCobro { aprobada, rechazada, pendiente, confirmarEnTerminal }

bool sigueEsperando(ResultadoOrdenCobro r) => r == ResultadoOrdenCobro.pendiente || r == ResultadoOrdenCobro.confirmarEnTerminal;

/// Ritmo del polling de una orden de cobro (Fase 12) — compartido entre el
/// diálogo de escritorio y el de la companion app (Regla 3: un solo lugar
/// para "cada cuánto" y "hasta cuándo", no una copia por pantalla).
const intervaloPollingCobroPosnet = Duration(seconds: 2);

/// Canales de cobro por la Point. En la caja los tres son el mismo medio, "Mercado Pago"; el canal es solo dato del pago.
/// Crédito (etapa C, el dueño 2026-10-04): un botón "Tarjeta" que pregunta Débito o Crédito, y crédito siempre en 1 pago y sin
/// recargo — Mercado Pago solo deja limitar las cuotas si la orden es de crédito (`default_installments`), por eso no hay una
/// opción "tarjeta libre" donde el cliente elija.
const canalQr = 'qr';
const canalDebito = 'debit_card';
const canalCredito = 'credit_card';
const canalesPoint = {canalQr, canalDebito, canalCredito};

bool esCanalTarjeta(String? canal) => canal == canalDebito || canal == canalCredito;

String nombreCanal(String? canal) => switch (canal) {
  canalQr => 'QR',
  canalDebito => 'Débito',
  canalCredito => 'Crédito',
  _ => 'Mercado Pago',
};

/// `config.payment_method` de la orden. Crédito va siempre en 1 pago: con `default_installments: 1` la terminal no muestra la
/// pantalla de cuotas (y con 1 cuota no hace falta `installments_cost`). Misma regla en el sitio (`medioDePagoOrden`).
Map<String, Object> medioDePagoOrden(String canal) =>
    canal == canalCredito ? {'default_type': canalCredito, 'default_installments': 1} : {'default_type': canal};

/// Cuánto vive una orden si nadie la paga (Orders API, `expiration_time`; etapa A, 2026-10-04). Pasado esto Mercado Pago la
/// vence sola: la terminal deja de esperar y la orden queda `expired` (rechazada acá). El sitio usa la misma duración
/// (`VENCIMIENTO_ORDEN`, `functions/_lib/mp_conexion.js`).
const vencimientoOrdenCobroPosnet = Duration(minutes: 2);

/// Se consulta un poco más de lo que vive la orden: así siempre se llega a ver su final (cobrada o vencida) y casi nunca queda
/// el "no sé si se cobró" de antes, que pasaba cuando se dejaba de consultar con la orden todavía viva.
const timeoutPollingCobroPosnet = Duration(minutes: 2, seconds: 20);

/// Una duración en ISO 8601 como la pide Mercado Pago (`PT2M`, `PT1M30S`, `PT1H15M`).
String duracionIso8601(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return 'PT${h > 0 ? '${h}H' : ''}${m > 0 ? '${m}M' : ''}${s > 0 || d == Duration.zero ? '${s}S' : ''}';
}

const _estadosRechazados = {'failed', 'canceled', 'expired'};

/// [status] es el campo de nivel superior de la respuesta de
/// `GET /v1/orders/{id}` — nunca `status_detail` (ese es solo el detalle
/// legible, no el que decide aprobado/rechazado/pendiente).
ResultadoOrdenCobro clasificarEstadoOrden(String status) {
  if (status == 'processed') return ResultadoOrdenCobro.aprobada;
  if (_estadosRechazados.contains(status)) return ResultadoOrdenCobro.rechazada;
  if (status == 'action_required') return ResultadoOrdenCobro.confirmarEnTerminal;
  return ResultadoOrdenCobro.pendiente;
}

/// Lo que el celular lee de la PC (`GET /ventas/posnet/estado`). La PC sigue mandando solo `aprobada`/`rechazada`/`pendiente`
/// (un celular viejo no conoce otro nombre y se rompería) y avisa aparte `enTerminal`. Cualquier cosa desconocida es pendiente:
/// nunca se inventa un cobro ni un rechazo por una versión distinta.
ResultadoOrdenCobro resultadoDesdeRespuesta(String? estado, {bool enTerminal = false}) {
  final r = switch (estado) {
    'aprobada' => ResultadoOrdenCobro.aprobada,
    'rechazada' => ResultadoOrdenCobro.rechazada,
    'confirmarEnTerminal' => ResultadoOrdenCobro.confirmarEnTerminal,
    _ => ResultadoOrdenCobro.pendiente,
  };
  return r == ResultadoOrdenCobro.pendiente && enTerminal ? ResultadoOrdenCobro.confirmarEnTerminal : r;
}
