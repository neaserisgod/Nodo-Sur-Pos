// Pedidos de un local gastronómico en la base (`REGLAS-NEGOCIO.md` §22, `docs/PLAN-GASTRONOMIA.md`). Las reglas (estado
// inicial, pasos, cocina, entrega) son de `domain/pedido_gastronomico.dart`: acá solo se leen y se graban.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/pedido_gastronomico.dart';
import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'numero_venta.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_turnos.dart' show configAgendaActual;

/// La cocina está pausada: el bot no toma pedidos (el mostrador sí, lo decide quien atiende).
class CocinaPausada implements Exception {
  const CocinaPausada();
}

/// Falta algo para tomar el pedido: platos, una forma de entrega que el local tenga, o la dirección y la zona de un envío.
class PedidoIncompleto implements Exception {
  const PedidoIncompleto(this.mensaje);
  final String mensaje;
}

/// El pedido ya tiene su venta, o se cerró sin entregarse (rechazado, cancelado): cobrarlo otra vez metería la misma plata dos
/// veces en la caja.
class PedidoYaCobrado implements Exception {
  const PedidoYaCobrado(this.numero);
  final String numero;
}

/// Un cambio de estado que las reglas no permiten (entregar algo sin hacer, cancelar algo en camino).
class PasoDePedidoInvalido implements Exception {
  const PasoDePedidoInvalido(this.desde, this.hasta);
  final EstadoPedido desde;
  final EstadoPedido hasta;
}

Future<ConfigPedidos> configPedidosActual(AppDatabase db) async {
  final texto = (await configuracionNegocioActual(db)).configPedidos;
  if (texto == null) return const ConfigPedidos();
  try {
    return ConfigPedidos.desdeJson(jsonDecode(texto));
  } on FormatException {
    return const ConfigPedidos();
  }
}

Future<void> guardarConfigPedidos(AppDatabase db, ConfigPedidos config) =>
    escribirConfiguracionNegocio(db, ConfiguracionNegocioTablaCompanion(configPedidos: Value(jsonEncode(config.toJson()))));

Future<EstadoCocina> estadoCocinaActual(AppDatabase db) async =>
    EstadoCocina.desdeClave((await configuracionNegocioActual(db)).estadoCocina);

Future<void> cambiarEstadoCocina(AppDatabase db, EstadoCocina estado) =>
    escribirConfiguracionNegocio(db, ConfiguracionNegocioTablaCompanion(estadoCocina: Value(estado.clave)));

/// Lo pedido de [pedido]. Una línea que no se entiende se saltea (no frena la lista).
List<LineaPedido> lineasDe(PedidoGastronomia pedido) {
  try {
    final crudo = jsonDecode(pedido.lineasJson);
    if (crudo is! List) return const [];
    return [for (final l in crudo) ?LineaPedido.desdeJson(l)];
  } on FormatException {
    return const [];
  }
}

/// Toma un pedido nuevo y devuelve su id. El estado y la hora estimada salen de las reglas y de la cocina de ahora.
Future<int> crearPedido(
  AppDatabase db, {
  required CanalPedido canal,
  required String nombreCliente,
  required List<LineaPedido> lineas,
  required int usuarioId,
  FormaEntrega formaEntrega = FormaEntrega.retiro,
  String? telefono,
  String? direccion,
  ZonaEnvio? zona,
  String? nota,
  bool pagaAdelantado = false,
  int? clienteId,
  String? idRemoto,
  DateTime? ahora,
}) {
  return db.transaction(() async {
    if (lineas.isEmpty) throw const PedidoIncompleto('El pedido no tiene nada.');
    if (nombreCliente.trim().isEmpty) throw const PedidoIncompleto('Falta el nombre.');
    final config = await configPedidosActual(db);
    final cocina = await estadoCocinaActual(db);
    if (cocina == EstadoCocina.pausada && !canal.loCargaElLocal) throw const CocinaPausada();
    if (!config.formasDisponibles.contains(formaEntrega)) {
      throw PedidoIncompleto('El local no tiene "${formaEntrega.etiqueta}".');
    }
    final falta = faltaParaEntrega(formaEntrega, direccion: direccion, zona: zona);
    if (falta.isNotEmpty) throw PedidoIncompleto('Falta ${falta.join(' y ')}.');

    final momento = ahora ?? DateTime.now();
    // Lo que carga el local sale cuando dice la cocina; lo que llega de afuera, además, respeta el horario: fuera de hora queda
    // programado para cuando abre (§22).
    final sale = canal.loCargaElLocal
        ? (hora: horaEstimada(ahora: momento, cocina: cocina, config: config, forma: formaEntrega, zona: zona), programado: false)
        : cuandoSale(
            ahora: momento,
            cocina: cocina,
            config: config,
            forma: formaEntrega,
            zona: zona,
            horario: (await configAgendaActual(db)).horario,
          );
    return db.into(db.pedidosGastronomia).insert(
          PedidosGastronomiaCompanion.insert(
            numero: await siguienteNumeroDePedido(db),
            canal: canal.clave,
            estado: estadoInicial(canal: canal, config: config, pagaAdelantado: pagaAdelantado).clave,
            formaEntrega: Value(formaEntrega.clave),
            clienteId: Value(clienteId),
            nombreCliente: nombreCliente.trim(),
            telefono: Value(telefono),
            direccion: Value(formaEntrega.esEnvio ? direccion!.trim() : null),
            zona: Value(formaEntrega.esEnvio ? zona!.nombre : null),
            costoEnvioCentavos: Value(costoEnvioCentavos(formaEntrega, zona)),
            lineasJson: jsonEncode([for (final l in lineas) l.toJson()]),
            nota: Value(nota),
            horaEstimada: Value(sale?.hora),
            programado: Value(sale?.programado ?? false),
            pagaAdelantado: Value(pagaAdelantado),
            idRemoto: Value(idRemoto),
            fechaCreacion: Value(momento),
            usuarioId: usuarioId,
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(momento),
          ),
        );
  });
}

/// Pasa el pedido [id] a [nuevo], si las reglas lo permiten: el paso siguiente de su forma de entrega, o cancelar mientras no
/// salió.
Future<void> avanzarPedido(AppDatabase db, int id, EstadoPedido nuevo) {
  return db.transaction(() async {
    final pedido = await (db.select(db.pedidosGastronomia)..where((p) => p.id.equals(id))).getSingle();
    final actual = EstadoPedido.desdeClave(pedido.estado);
    final permitido = nuevo == EstadoPedido.cancelado
        ? sePuedeCancelar(actual)
        : siguientesEstados(actual, FormaEntrega.desdeClave(pedido.formaEntrega)).contains(nuevo);
    if (!permitido) throw PasoDePedidoInvalido(actual, nuevo);
    await (db.update(db.pedidosGastronomia)..where((p) => p.id.equals(id))).write(
      PedidosGastronomiaCompanion(estado: Value(nuevo.clave), actualizadoEn: Value(DateTime.now())),
    );
  });
}

/// Llegó el pago adelantado de [id]: queda pagado y sigue como si recién entrara (por confirmar, o por hacer si entra solo).
Future<void> registrarPagoAdelantado(AppDatabase db, int id) {
  return db.transaction(() async {
    final pedido = await (db.select(db.pedidosGastronomia)..where((p) => p.id.equals(id))).getSingle();
    final estado = EstadoPedido.desdeClave(pedido.estado);
    await (db.update(db.pedidosGastronomia)..where((p) => p.id.equals(id))).write(
      PedidosGastronomiaCompanion(
        pagado: const Value(true),
        estado: estado == EstadoPedido.esperandoPago ? Value(estadoAlPagar(await configPedidosActual(db)).clave) : const Value.absent(),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
  });
}

/// La lista de trabajo: lo que sigue abierto, del más viejo al más nuevo (el primero que entró es el primero que sale). Se lee
/// cuando la pantalla lo pide (al abrir y con cada aviso de cambio), como la Agenda.
Future<List<PedidoGastronomia>> pedidosAbiertos(AppDatabase db) {
  final cerrados = [EstadoPedido.entregado.clave, EstadoPedido.rechazado.clave, EstadoPedido.cancelado.clave];
  return (db.select(db.pedidosGastronomia)
        ..where((p) => p.estado.isNotIn(cerrados))
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion), (p) => OrderingTerm.asc(p.id)]))
      .get();
}

/// Lo que se puede pedir: lo activo con precio, sin insumos ni "Varios". Por ahora por unidad: lo que se pesa entra con su
/// propio paso (gramos) más adelante.
Future<List<Producto>> cartaDelLocal(AppDatabase db) => (db.select(db.productos)
      ..where((p) =>
          p.activo.equals(true) &
          p.esInsumo.equals(false) &
          p.esVarios.equals(false) &
          p.esPesable.equals(false) &
          p.precioCentavos.isNotNull() &
          p.globalId.isNotNull())
      ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
    .get();

/// Las líneas de la venta con que se cobra [pedido]: cada plato al precio que se le dijo al cliente (el del pedido) y con el
/// costo de hoy (costo-foto, Regla 4), y el envío como una línea suelta ("Varios", sin stock ni costo). Un plato que ya no
/// está en este equipo (se borró, o no llegó por la sync) frena el cobro: no se cobra algo que no se sabe qué es.
Future<List<LineaVenta>> lineasDeVentaDePedido(AppDatabase db, PedidoGastronomia pedido) async {
  final lineas = <LineaVenta>[];
  for (final l in lineasDe(pedido)) {
    final producto = await (db.select(db.productos)..where((p) => p.globalId.equals(l.gid))).getSingleOrNull();
    if (producto == null) throw PedidoIncompleto('No está "${l.nombre}" en la carta de este equipo.');
    if (l.gramos != null) {
      lineas.add(LineaVentaPesable(
        productoId: '${producto.id}',
        nombreProducto: producto.nombre,
        proveedorId: producto.proveedorId?.toString(),
        gramos: l.gramos!,
        precioPorKiloCentavos: l.precioCentavos,
        costoPorKiloCentavos: producto.costoPorKiloCentavos,
      ));
    } else {
      lineas.add(LineaVentaPorUnidad(
        productoId: '${producto.id}',
        nombreProducto: producto.nombre,
        proveedorId: producto.proveedorId?.toString(),
        cantidad: l.cantidad!,
        tipoCigarrillo: tipoCigarrilloDesde(producto.tipoCigarrillo),
        precioUnitarioCentavos: l.precioCentavos,
        costoUnitarioCentavos: producto.costoCentavos,
      ));
    }
  }
  if (pedido.costoEnvioCentavos > 0) {
    final varios = await _productoVarios(db);
    lineas.add(LineaVentaPorUnidad(
      productoId: '${varios.id}',
      nombreProducto: 'Envío · ${pedido.zona ?? 'sin zona'}',
      proveedorId: null,
      cantidad: 1,
      esVarios: true,
      precioUnitarioCentavos: pedido.costoEnvioCentavos,
    ));
  }
  return lineas;
}

/// "Varios": en la PC lo siembra la base; un celular solo lo recibe por la sync, y uno que trabaja sin PC puede no tenerlo. Se
/// crea con el `global_id` fijo de la PC, así si después llega el de otro equipo es la misma fila.
Future<Producto> _productoVarios(AppDatabase db) async {
  final hay = await (db.select(db.productos)..where((p) => p.esVarios.equals(true))..limit(1)).getSingleOrNull();
  if (hay != null) return hay;
  final id = await db.into(db.productos).insert(ProductosCompanion.insert(
        nombre: 'Varios',
        esVarios: const Value(true),
        globalId: const Value(globalIdProductoVarios),
        origenDispositivo: Value(idDispositivoActual),
        actualizadoEn: Value(DateTime.fromMillisecondsSinceEpoch(0)),
      ));
  return (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
}

/// La venta [ventaId] cobró el pedido [pedidoId]. Se llama DENTRO de la transacción de `registrarVenta`: si el pedido ya tenía
/// venta (o se cerró sin entregarse), tira y la venta no se graba. Un retiro que estaba listo queda entregado (lo retiró y
/// pagó); un envío sigue en la lista hasta que se entrega.
Future<void> marcarPedidoCobrado(AppDatabase db, int pedidoId, {required int ventaId}) async {
  final pedido = await (db.select(db.pedidosGastronomia)..where((p) => p.id.equals(pedidoId))).getSingle();
  final estado = EstadoPedido.desdeClave(pedido.estado);
  if (pedido.ventaId != null || estado == EstadoPedido.rechazado || estado == EstadoPedido.cancelado) {
    throw PedidoYaCobrado(pedido.numero);
  }
  final forma = FormaEntrega.desdeClave(pedido.formaEntrega);
  final entregado = !forma.esEnvio && estado == EstadoPedido.listo;
  await (db.update(db.pedidosGastronomia)..where((p) => p.id.equals(pedidoId))).write(PedidosGastronomiaCompanion(
        ventaId: Value(ventaId),
        estado: entregado ? Value(EstadoPedido.entregado.clave) : const Value.absent(),
        actualizadoEn: Value(DateTime.now()),
      ));
}
