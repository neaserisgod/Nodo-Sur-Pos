// La comanda de un pedido de gastronomía, impresa en la terminal Point (El dueño, 2026-10-24: "como si fuese una comandera… la
// misma función que tiene almacén"; "cuando un pedido se confirma como tal, debe imprimir la comanda", también los del bot). Es
// para la cocina: qué hacer, para quién y para cuándo; los precios no, solo lo que falta cobrar (lo necesita quien entrega).
//
// Funciones puras: qué pedidos imprimir y el texto en el lenguaje de tags de la API de Terminals (`domain/ticket.dart`).

import 'dinero.dart';
import 'pedido_gastronomico.dart';

/// Lo que va en la comanda de un pedido.
class DatosComanda {
  const DatosComanda({
    required this.numero,
    required this.canal,
    required this.forma,
    required this.nombreCliente,
    required this.lineas,
    required this.fecha,
    this.telefono,
    this.direccion,
    this.zona,
    this.nota,
    this.horaEstimada,
    this.programado = false,
    this.pagado = false,
    this.totalCentavos = 0,
  });

  final String numero;
  final CanalPedido canal;
  final FormaEntrega forma;
  final String nombreCliente;
  final List<LineaPedido> lineas;

  /// Cuándo entró el pedido.
  final DateTime fecha;
  final String? telefono;
  final String? direccion;
  final String? zona;
  final String? nota;
  final DateTime? horaEstimada;
  final bool programado;
  final bool pagado;

  /// Lo que vale el pedido con el envío ([totalPedidoCentavos]): si no está pagado, es lo que se cobra al entregar.
  final int totalCentavos;
}

/// Un pedido visto por la comandera: con qué estado y desde cuándo (`actualizado_en`, o la creación si no tiene).
typedef PedidoParaComanda = ({String gid, EstadoPedido estado, DateTime momento});

/// La comanda sale cuando el pedido queda confirmado: "por hacer", llegue como llegue (lo cargó el local, lo aceptó, entró solo
/// del bot o pagado por Mercado Pago, o vino por la sync de otro equipo).
bool comandaPendiente(EstadoPedido estado) => estado == EstadoPedido.porHacer;

/// Hasta cuánto atrás se imprime lo confirmado mientras la comandera estaba apagada (la app cerrada, sin internet): un turno.
/// Más viejo que eso, la cocina ya lo sabe por la pantalla.
const ventanaComanda = Duration(hours: 12);

/// Lo impreso se recuerda unos días, para no repetir una comanda al abrir la app de nuevo.
const recuerdoComandas = Duration(days: 3);

/// Los `gid` de [pedidos] a imprimir ahora: confirmados, sin comanda en este equipo ([impresas]) y dentro de [ventana].
List<String> comandasPorImprimir(
  Iterable<PedidoParaComanda> pedidos, {
  required Set<String> impresas,
  required DateTime ahora,
  Duration ventana = ventanaComanda,
}) => [
      for (final p in pedidos)
        if (comandaPendiente(p.estado) && !impresas.contains(p.gid) && ahora.difference(p.momento) <= ventana) p.gid,
    ];

/// Saca de lo impreso ([impresas]: gid → milisegundos de cuándo salió) lo que ya no puede volver a pedirse.
Map<String, int> podarComandas(Map<String, int> impresas, {required DateTime ahora, Duration recuerdo = recuerdoComandas}) => {
      for (final e in impresas.entries)
        if (ahora.difference(DateTime.fromMillisecondsSinceEpoch(e.value)) <= recuerdo) e.key: e.value,
    };

/// Las llaves sueltas romperían los tags de la terminal: lo que escribió una persona (nombre, nota, dirección) va sin ellas.
String _limpio(String texto) => texto.replaceAll(RegExp(r'[{}]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

String _dos(int n) => n.toString().padLeft(2, '0');
String _hora(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}';
String _dia(DateTime d) => '${_dos(d.day)}/${_dos(d.month)}';

const _raya = '--------------------------------{br}';

/// Cuántos caracteres entran en un renglón con `{w}`: "COMANDA BD-P0007" (16) llena el ancho en una Point real.
const anchoLetraGrande = 16;

/// El nombre del plato sin la descripción entre paréntesis (El dueño, 2026-10-24: "sin descripción mejor"): la cocina ya sabe
/// qué lleva una "Bacon Cheese". Si el nombre es todo paréntesis, va entero.
String nombreParaComanda(String nombre) {
  final limpio = _limpio(nombre);
  final i = limpio.indexOf('(');
  final corto = i < 0 ? limpio : limpio.substring(0, i).trim();
  return corto.isEmpty ? limpio : corto;
}

/// El contenido para `POST /terminals/v1/actions` (type "print"). Sin la hora de ahora adentro: el mismo pedido da siempre el
/// mismo texto, así el reintento con la misma clave de idempotencia es el mismo pedido para Mercado Pago.
String contenidoComandaPosnetMp(DatosComanda c, {String encabezadoNegocio = ''}) {
  final b = StringBuffer();
  final local = _limpio(encabezadoNegocio.split('\n').first);
  if (local.isNotEmpty) b.write('{center}{s}$local{/s}{/center}{br}');
  b.write('{center}{w}COMANDA ${_limpio(c.numero)}{/w}{/center}{br}');
  b.write('{center}{b}${c.forma.esEnvio ? 'ENVIO' : 'RETIRA EN EL LOCAL'}{/b}{/center}{br}');
  // Guion y no "·": la Point no tiene ese carácter y deja un hueco (visto en una Point real, 2026-10-24).
  b.write('{center}{s}${c.canal.etiqueta} - entró ${_dia(c.fecha)} ${_hora(c.fecha)}{/s}{/center}{br}');
  final hora = c.horaEstimada;
  if (hora != null) {
    b.write(c.programado
        ? '{center}{w}PROGRAMADO ${_dia(hora)} ${_hora(hora)}{/w}{/center}{br}'
        : '{center}{b}Para las ${_hora(hora)}{/b}{/center}{br}');
  }
  b.write(_raya);
  for (final l in c.lineas) {
    final cuanto = l.gramos != null ? '${l.gramos} g' : '${l.cantidad} x';
    final renglon = '$cuanto ${nombreParaComanda(l.nombre)}';
    // En grande entran pocos caracteres: un renglón más largo la Point lo achica, y quedaba más chico que el resto.
    b.write(renglon.length <= anchoLetraGrande ? '{w}$renglon{/w}{br}' : '{b}$renglon{/b}{br}');
  }
  b.write(_raya);
  final nota = c.nota == null ? '' : _limpio(c.nota!);
  if (nota.isNotEmpty) b.write('{b}NOTA:{/b} $nota{br}');
  b.write('{b}Cliente:{/b} ${_limpio(c.nombreCliente)}{br}');
  if (c.forma.esEnvio) {
    final direccion = c.direccion == null ? '' : _limpio(c.direccion!);
    final zona = c.zona == null ? '' : _limpio(c.zona!);
    if (direccion.isNotEmpty) b.write('{b}Dirección:{/b} $direccion${zona.isEmpty ? '' : ' ($zona)'}{br}');
  }
  final telefono = c.telefono == null ? '' : _limpio(c.telefono!);
  if (telefono.isNotEmpty) b.write('{b}Tel.:{/b} $telefono{br}');
  b.write(_raya);
  b.write(c.pagado ? '{center}{b}PAGADO{/b}{/center}{br}' : '{center}{b}A COBRAR ${formatearARS(c.totalCentavos)}{/b}{/center}{br}');
  return b.toString();
}
