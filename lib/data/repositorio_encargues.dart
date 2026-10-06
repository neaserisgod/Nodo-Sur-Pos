// Encargues por apartado (El dueño, 2026-10-02): un cliente pide algo que YA está en el local y se lo aparta.
//
//  * Apartar saca el stock en el momento (movimiento AJUSTE con el motivo "Apartado para X", Regla 6): así lo que se
//    prometió no se le vende a otro. Si no alcanza el stock no se aparta nada.
//  * Cancelar lo devuelve, también con rastro, y solo una vez.
//  * Entregar es una venta normal (precios de hoy) que libera lo apartado EN LA MISMA TRANSACCIÓN que la venta
//    (`registrarVenta(encargueId:)`): la venta descuenta el stock de nuevo, así que sin devolver lo apartado se
//    descontaría dos veces. Si el cobro no se completa, nada de esto pasa y el encargue sigue apartado.
//
//  * "Entregar y anotar deuda" (dueño, 2026-10-03: el fiado se unificó con los encargues): el cliente se lleva lo apartado
//    sin pagar. El stock ya estaba descontado al apartar, así que no se mueve de nuevo; el encargue pasa a ser una deuda
//    (`tipo` 'FIADO') por el total a los precios de HOY, que se cobra después con `cobrarFiado`.
//
//  * Seña (dueño, 2026-10-06; `domain/sena.dart`, `docs/PLAN-SENA.md`): entra a la caja con la que se pagó como INGRESO (no es una
//    venta); cancelar la devuelve por la misma caja; al entregar se aplica como un pago de la venta que NO vuelve a mover la caja.
//
// Se guarda en `pendientes` (tipo 'ENCARGUE', ya sincronizada) con las líneas en JSON por `global_id` del producto.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/sena.dart';
import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_gastos.dart' show MedioGasto;
import 'repositorio_ingresos.dart';
import 'repositorio_productos.dart';
import 'repositorio_ventas.dart' show lineaDesdeProducto, verificarSesionAbierta;

/// Lo que se quiere apartar: un producto y, según sea, unidades o gramos.
class LineaEncargueNueva {
  const LineaEncargueNueva({required this.productoId, this.cantidad, this.gramos})
      : assert((cantidad == null) != (gramos == null), 'unidades o gramos, no los dos');
  final int productoId;
  final int? cantidad;
  final int? gramos;
}

/// Lo apartado, tal como queda guardado.
class LineaEncargue {
  const LineaEncargue({required this.productoGlobalId, required this.nombre, this.cantidad, this.gramos});
  final String productoGlobalId;
  final String nombre;
  final int? cantidad;
  final int? gramos;

  Map<String, dynamic> toJson() => {
        'gid': productoGlobalId,
        'nombre': nombre,
        if (cantidad != null) 'cantidad': cantidad,
        if (gramos != null) 'gramos': gramos,
      };

  factory LineaEncargue.desdeJson(Map<String, dynamic> j) => LineaEncargue(
        productoGlobalId: j['gid'] as String,
        nombre: j['nombre'] as String,
        cantidad: (j['cantidad'] as num?)?.toInt(),
        gramos: (j['gramos'] as num?)?.toInt(),
      );

  /// "3 × Galletitas" o "250 g Queso barra".
  String get texto => gramos != null ? '$gramos g $nombre' : '$cantidad × $nombre';
}

class Encargue {
  const Encargue({
    required this.id,
    required this.nombreCliente,
    required this.lineas,
    required this.desde,
    this.senaCentavos = 0,
    this.senaEsEfectivo = true,
  });
  final int id;
  final String nombreCliente;
  final List<LineaEncargue> lineas;
  final DateTime desde;

  /// Lo que el cliente dejó de seña (0 = nada) y por qué caja entró.
  final int senaCentavos;
  final bool senaEsEfectivo;

  String get resumen => lineas.map((l) => l.texto).join(', ');
}

/// No alcanza el stock para apartar [nombreProducto].
class EncargueSinStock implements Exception {
  const EncargueSinStock(this.nombreProducto);
  final String nombreProducto;
  @override
  String toString() => 'No alcanza el stock de $nombreProducto para apartarlo.';
}

/// Lo que se quiere hacer no se puede con un encargue que tiene seña (se explica en [mensaje]).
class EncargueConSena implements Exception {
  const EncargueConSena(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// La seña de un encargue todavía pendiente: cuánto y por qué caja entró. Un encargue que ya no está pendiente (entregado o
/// cancelado) devuelve 0: su seña ya se aplicó o se devolvió, y volver a contarla duplicaría la plata.
Future<({int centavos, bool esEfectivo})> senaPendienteDe(AppDatabase db, int encargueId) async {
  final p = await (db.select(db.pendientes)..where((x) => x.id.equals(encargueId))).getSingleOrNull();
  if (p == null || p.tipo != 'ENCARGUE' || p.estado != 'PENDIENTE') return (centavos: 0, esEfectivo: true);
  return (centavos: p.senaCentavos, esEfectivo: p.senaEsEfectivo);
}

/// La seña vuelve al cliente por la caja por la que entró. Movimiento propio ('DEVOLUCION_SENA'), no un gasto: la rentabilidad y el
/// equilibrio suman los gastos y devolver una seña no le resta ganancia al negocio.
Future<void> registrarDevolucionSena(
  AppDatabase db, {
  required int sesionCajaId,
  required int usuarioId,
  required int montoCentavos,
  required bool esEfectivo,
  required String motivo,
}) async {
  if (montoCentavos <= 0) return;
  await verificarSesionAbierta(db, sesionCajaId);
  final caja = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
  final medioId = cajaDeLaSena(esEfectivo: esEfectivo) == CajaDeSena.mercadoPago
      ? (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id
      : null;
  await db.into(db.movimientosDeCaja).insert(
        MovimientosDeCajaCompanion.insert(
          sesionCajaId: sesionCajaId,
          cajaId: caja.id,
          usuarioId: usuarioId,
          tipo: 'DEVOLUCION_SENA',
          montoCentavos: montoCentavos,
          medioPagoId: Value(medioId),
          nota: Value(motivo),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

List<LineaEncargue> _leerLineas(String? json) {
  if (json == null || json.isEmpty) return const [];
  return [for (final j in jsonDecode(json) as List) LineaEncargue.desdeJson(Map<String, dynamic>.from(j as Map))];
}

/// Mueve el stock de [producto] en [delta] (unidades) o [deltaGramos] y deja el movimiento.
Future<void> _moverStock(
  AppDatabase db, {
  required Producto producto,
  required int usuarioId,
  int? delta,
  int? deltaGramos,
  required String motivo,
}) async {
  final nuevoStock = producto.stock + (delta ?? 0);
  final nuevosGramos = deltaGramos == null ? producto.stockGramos : (producto.stockGramos ?? 0) + deltaGramos;
  await (db.update(db.productos)..where((p) => p.id.equals(producto.id)))
      .write(ProductosCompanion(stock: Value(nuevoStock), stockGramos: Value(nuevosGramos)));
  await registrarAjusteDeStock(
    db,
    productoId: producto.id,
    usuarioId: usuarioId,
    anterior: producto,
    stock: nuevoStock,
    stockGramos: nuevosGramos,
    motivo: motivo,
  );
}

Future<Producto> _productoPorGlobalId(AppDatabase db, String gid) =>
    (db.select(db.productos)..where((p) => p.globalId.equals(gid))).getSingle();

/// Un producto sin identidad de sincronización (anterior a la sync, o cargado por un camino que no se la dio) la recibe
/// acá: el encargue se refiere a él por `global_id`. Se marca como cambiado para que suba con esa identidad.
Future<String> _darIdentidad(AppDatabase db, Producto producto) async {
  final gid = generarGlobalId();
  await (db.update(db.productos)..where((p) => p.id.equals(producto.id)))
      .write(ProductosCompanion(globalId: Value(gid), actualizadoEn: Value(DateTime.now())));
  return gid;
}

/// Aparta [lineas] para [nombreCliente]: baja el stock y deja el encargue pendiente. Todo o nada.
///
/// Con [senaCentavos] > 0 el cliente deja una seña: entra a la caja de [sesionCajaId] (cajón si [senaEsEfectivo], Mercado Pago si no)
/// en la MISMA transacción, así no queda un encargue con seña sin plata ni plata sin encargue. Pide la caja abierta.
Future<int> crearEncargueApartando(
  AppDatabase db, {
  required String nombreCliente,
  required List<LineaEncargueNueva> lineas,
  required int usuarioId,
  int senaCentavos = 0,
  bool senaEsEfectivo = true,
  int? sesionCajaId,
}) {
  final nombre = nombreCliente.trim();
  if (nombre.isEmpty) throw ArgumentError('El encargue necesita el nombre del cliente.');
  if (lineas.isEmpty) throw ArgumentError('El encargue necesita al menos un producto.');
  if (senaCentavos > 0 && sesionCajaId == null) throw ArgumentError('Para tomar una seña hace falta la caja abierta.');
  return db.transaction(() async {
    final guardadas = <LineaEncargue>[];
    final lineasDeVenta = <LineaVenta>[];
    for (final l in lineas) {
      final producto = await (db.select(db.productos)..where((p) => p.id.equals(l.productoId))).getSingle();
      final gramos = l.gramos;
      final unidades = l.cantidad;
      if ((gramos ?? unidades ?? 0) <= 0) throw ArgumentError('La cantidad apartada tiene que ser mayor a cero.');
      final gid = producto.globalId ?? await _darIdentidad(db, producto);
      final alcanza = gramos != null ? (producto.stockGramos ?? 0) >= gramos : producto.stock >= unidades!;
      if (!alcanza) throw EncargueSinStock(producto.nombre);
      await _moverStock(
        db,
        producto: producto,
        usuarioId: usuarioId,
        delta: unidades == null ? null : -unidades,
        deltaGramos: gramos == null ? null : -gramos,
        motivo: 'Apartado para $nombre',
      );
      guardadas.add(LineaEncargue(productoGlobalId: gid, nombre: producto.nombre, cantidad: unidades, gramos: gramos));
      lineasDeVenta.add(lineaDesdeProducto(producto, cantidad: unidades, gramos: gramos));
    }
    final problema = validarSenaNueva(senaCentavos: senaCentavos, estimadoCentavos: Venta(lineas: lineasDeVenta).subtotalCentavos);
    if (problema != null) throw ArgumentError(problema);
    final id = await db.into(db.pendientes).insert(
          PendientesCompanion.insert(
            tipo: 'ENCARGUE',
            nombreLibre: Value(nombre),
            // El tablero y los encargues viejos leen `descripcion`: queda el resumen legible.
            descripcion: Value(guardadas.map((l) => l.texto).join(', ')),
            lineasJson: Value(jsonEncode([for (final l in guardadas) l.toJson()])),
            senaCentavos: Value(senaCentavos),
            senaEsEfectivo: Value(senaEsEfectivo),
            usuarioId: usuarioId,
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
    if (senaCentavos > 0) {
      await registrarIngresoRapido(
        db,
        sesionCajaId: sesionCajaId!,
        usuarioId: usuarioId,
        montoCentavos: senaCentavos,
        medio: cajaDeLaSena(esEfectivo: senaEsEfectivo) == CajaDeSena.cajon ? MedioGasto.cajonNormal : MedioGasto.mercadoPago,
        motivo: 'Seña encargue de $nombre',
      );
    }
    return id;
  });
}

/// Los encargues por apartado todavía sin entregar, el más viejo primero.
Future<List<Encargue>> listarEnarguesPendientes(AppDatabase db) async {
  final filas = await (db.select(db.pendientes)
        ..where((p) => p.tipo.equals('ENCARGUE') & p.estado.equals('PENDIENTE') & p.lineasJson.isNotNull())
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion)]))
      .get();
  return [
    for (final p in filas)
      Encargue(
        id: p.id,
        nombreCliente: p.nombreLibre ?? '',
        lineas: _leerLineas(p.lineasJson),
        desde: p.fechaCreacion,
        senaCentavos: p.senaCentavos,
        senaEsEfectivo: p.senaEsEfectivo,
      ),
  ];
}

/// Devuelve al stock lo apartado por [pendiente] y deja el movimiento con [motivo].
Future<void> _devolverApartado(AppDatabase db, Pendiente pendiente, {required int usuarioId, required String motivo}) async {
  for (final l in _leerLineas(pendiente.lineasJson)) {
    final producto = await _productoPorGlobalId(db, l.productoGlobalId);
    await _moverStock(db, producto: producto, usuarioId: usuarioId, delta: l.cantidad, deltaGramos: l.gramos, motivo: motivo);
  }
}

/// Cancela un encargue pendiente y devuelve lo apartado. Si ya no está pendiente (ya se entregó o ya se canceló) no hace
/// nada: devolver stock dos veces, o stock que ya se vendió, lo inventaría.
///
/// Si tenía seña, se devuelve por la misma caja por la que entró: hace falta [sesionCajaId] (la caja abierta de hoy); sin ella no se
/// cancela, porque la plata no tendría de dónde salir.
Future<void> cancelarEncargue(AppDatabase db, int id, {required int usuarioId, int? sesionCajaId}) {
  return db.transaction(() async {
    final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (p == null || p.tipo != 'ENCARGUE' || p.estado != 'PENDIENTE') return;
    if (p.senaCentavos > 0) {
      if (sesionCajaId == null) throw ArgumentError('Para devolver la seña hace falta la caja abierta.');
      await registrarDevolucionSena(
        db,
        sesionCajaId: sesionCajaId,
        usuarioId: usuarioId,
        montoCentavos: p.senaCentavos,
        esEfectivo: p.senaEsEfectivo,
        motivo: 'Devolución de seña, encargue de ${p.nombreLibre}',
      );
    }
    await _devolverApartado(db, p, usuarioId: usuarioId, motivo: 'Encargue cancelado: ${p.nombreLibre}');
    await (db.update(db.pendientes)..where((x) => x.id.equals(id))).write(PendientesCompanion(
      estado: const Value('CANCELADO'),
      fechaResuelta: Value(DateTime.now()),
      actualizadoEn: Value(DateTime.now()),
    ));
  });
}

/// Las líneas de venta de lo apartado, a los precios de HOY (Regla 4: el precio es el del momento del cobro, no el de
/// cuando se apartó).
Future<List<LineaVenta>> lineasParaEntregar(AppDatabase db, int id) async {
  final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingle();
  final lineas = <LineaVenta>[];
  for (final l in _leerLineas(p.lineasJson)) {
    final producto = await _productoPorGlobalId(db, l.productoGlobalId);
    lineas.add(lineaDesdeProducto(producto, cantidad: l.cantidad, gramos: l.gramos));
  }
  return lineas;
}

/// Lo llama `registrarVenta` dentro de su transacción al cobrar la entrega: devuelve lo apartado (la venta lo descuenta
/// ella) y deja el encargue resuelto con la venta que lo saldó.
Future<void> liberarEncargueEntregado(AppDatabase db, int id, {required int ventaId, required int usuarioId}) async {
  final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingleOrNull();
  if (p == null || p.tipo != 'ENCARGUE' || p.estado != 'PENDIENTE') return;
  await _devolverApartado(db, p, usuarioId: usuarioId, motivo: 'Encargue entregado: ${p.nombreLibre}');
  await (db.update(db.pendientes)..where((x) => x.id.equals(id))).write(PendientesCompanion(
    estado: const Value('RESUELTO'),
    ventaId: Value(ventaId),
    fechaResuelta: Value(DateTime.now()),
    actualizadoEn: Value(DateTime.now()),
  ));
}

/// Entrega lo apartado sin cobrar y deja anotada la deuda; devuelve cuánto se debe (precios de hoy, Regla 4). Si el
/// encargue ya no está pendiente no hace nada y devuelve null: anotar dos veces la misma deuda duplicaría lo adeudado.
Future<int?> entregarEncargueADeuda(AppDatabase db, int id, {required int usuarioId}) {
  return db.transaction(() async {
    final p = await (db.select(db.pendientes)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (p == null || p.tipo != 'ENCARGUE' || p.estado != 'PENDIENTE' || p.lineasJson == null) return null;
    if (p.senaCentavos > 0) {
      throw const EncargueConSena('Este encargue tiene una seña: cobralo (se descuenta la seña) o cancelalo para devolverla.');
    }
    final lineas = _leerLineas(p.lineasJson);
    final total = Venta(lineas: await lineasParaEntregar(db, id)).subtotalCentavos;
    await (db.update(db.pendientes)..where((x) => x.id.equals(id))).write(PendientesCompanion(
      tipo: const Value('FIADO'),
      montoCentavos: Value(total),
      descripcion: Value(lineas.map((l) => l.texto).join(', ')),
      // Ya no hay nada apartado: sin las líneas, cancelar o entregar de nuevo no devolverían stock que ya se fue.
      lineasJson: const Value(null),
      actualizadoEn: Value(DateTime.now()),
    ));
    return total;
  });
}

/// Una deuda anotada (fiado), lista para mostrar.
class Deuda {
  const Deuda({required this.id, required this.nombreCliente, required this.detalle, required this.montoCentavos, required this.desde});
  final int id;
  final String nombreCliente;
  final String detalle;
  final int montoCentavos;
  final DateTime desde;
}

/// Las deudas sin cobrar, la más vieja primero.
Future<List<Deuda>> listarDeudas(AppDatabase db) async {
  final filas = await (db.select(db.pendientes)
        ..where((p) => p.tipo.equals('FIADO') & p.estado.equals('PENDIENTE'))
        ..orderBy([(p) => OrderingTerm.asc(p.fechaCreacion)]))
      .get();
  return [
    for (final p in filas)
      Deuda(
        id: p.id,
        nombreCliente: p.nombreLibre ?? '',
        detalle: p.descripcion ?? '',
        montoCentavos: p.montoCentavos ?? 0,
        desde: p.fechaCreacion,
      ),
  ];
}
