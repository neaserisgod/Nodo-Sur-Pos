// Servicios e insumos (`docs/PLAN-SERVICIOS.md`, etapa 2): darlos de alta, comprar y contar insumos, y listarlos con lo
// que cuestan y para cuántos alcanzan. Las cuentas viven en `lib/domain/servicios.dart`; acá solo se leen y se guardan.
//
// Insumo y servicio son productos (`productos.es_insumo` / `es_servicio`, v65): así reusan la sync, las categorías, los
// proveedores, el historial de precios y la baja (`cambiarActivo`). Lo que cambia:
//  - el insumo no tiene precio de venta; su costo es el del ENVASE y su stock va en milésimas (`stock_milesimas`);
//  - el servicio no tiene stock; su receta apunta a los insumos por `global_id` (como `componentesPromo`), para que viaje
//    por la sync, y su costo NO se guarda: depende del precio de hoy de cada insumo y del valor de la hora, así que se
//    calcula al listar. El costo-foto de cada venta llega con la etapa 3 (cobrar servicios).
//
// Todo movimiento del stock de un insumo deja rastro en `movimientos_de_stock` (convención 6), con las milésimas antes y
// después: la sync arma el stock sumando esos deltas, nunca pisándolo (`repositorio_sincronizacion.dart`).

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/servicios.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_productos.dart';

/// Una línea de la receta de un servicio al guardarla: el insumo (por id local) y cuánto usa, en milésimas.
typedef LineaDeReceta = ({int insumoId, int milesimas});

/// Un insumo con sus cuentas, listo para mostrar.
class InsumoListado {
  const InsumoListado({required this.producto, required this.unidad, required this.costoPorUnidadCentavos});

  final Producto producto;
  final UnidadInsumo unidad;

  /// Lo que cuesta una unidad de uso (un ml, un g, una unidad). Null sin costo o sin contenido de envase cargado.
  final int? costoPorUnidadCentavos;

  int get stockMilesimas => producto.stockMilesimas ?? 0;

  /// Por debajo del mínimo que se cargó (0 o null: sin aviso).
  bool get pocoStock => (producto.stockMinimoMilesimas ?? 0) > 0 && stockMilesimas <= producto.stockMinimoMilesimas!;

  InsumoParaCalculo get paraCalculo => InsumoParaCalculo(
        costoEnvaseCentavos: producto.costoCentavos ?? 0,
        contenidoEnvaseMilesimas: producto.contenidoEnvaseMilesimas ?? 0,
        stockMilesimas: stockMilesimas,
      );
}

/// Una línea de la receta ya resuelta contra la base.
class UsoListado {
  const UsoListado({required this.insumo, required this.milesimas});

  final InsumoListado insumo;
  final int milesimas;
}

/// Un servicio con su costo de hoy, el precio sugerido y para cuántos alcanza.
class ServicioListado {
  const ServicioListado({
    required this.producto,
    required this.receta,
    required this.faltantes,
    required this.costo,
    required this.precioSugeridoCentavos,
    required this.alcanzaPara,
    required this.seAcabaPrimero,
  });

  final Producto producto;
  final List<UsoListado> receta;

  /// Insumos de la receta que todavía no llegaron por la sync (o se borraron a mano): sin ellos el costo no está completo.
  final int faltantes;
  final CostoDeServicio costo;
  final int precioSugeridoCentavos;

  /// Null: la receta está vacía (no usa insumos).
  final int? alcanzaPara;

  /// El insumo que se acaba primero, o null.
  final InsumoListado? seAcabaPrimero;

  int get gananciaBuscadaBp => producto.gananciaBuscadaBp ?? gananciaBuscadaPorDefectoBp;
}

void _validarNombre(String nombre) {
  if (nombre.trim().isEmpty) throw ArgumentError('Falta el nombre');
}

void _validarInsumo({required int contenidoEnvaseMilesimas, required int costoEnvaseCentavos}) {
  if (contenidoEnvaseMilesimas <= 0) throw ArgumentError('El envase tiene que traer algo (contenido mayor a 0)');
  if (costoEnvaseCentavos < 0) throw ArgumentError('El costo del envase no puede ser negativo');
}

void _validarServicio({required int precioCentavos, required int duracionMinutos, required List<LineaDeReceta> receta, int? gananciaBuscadaBp}) {
  if (precioCentavos < 0) throw ArgumentError('El precio no puede ser negativo');
  if (duracionMinutos <= 0) throw ArgumentError('El servicio tiene que durar algo');
  if (gananciaBuscadaBp != null && (gananciaBuscadaBp < 0 || gananciaBuscadaBp >= 10000)) {
    throw ArgumentError('La ganancia buscada va de 0 a menos de 100 %');
  }
  final vistos = <int>{};
  for (final l in receta) {
    if (l.milesimas <= 0) throw ArgumentError('Cada insumo de la receta tiene que usar algo');
    if (!vistos.add(l.insumoId)) throw ArgumentError('Un insumo está dos veces en la receta');
  }
}

Future<Producto> _producto(AppDatabase db, int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

// --- Insumos ------------------------------------------------------------------------------------------------------------

/// Alta de un insumo. Arranca con stock 0: lo que hay se carga con [cargarCompraDeInsumo] o [contarInsumo], que dejan rastro.
Future<int> crearInsumo(
  AppDatabase db, {
  required String nombre,
  required UnidadInsumo unidad,
  required int contenidoEnvaseMilesimas,
  required int costoEnvaseCentavos,
  int? proveedorId,
  int? categoriaId,
  int? stockMinimoMilesimas,
  required int usuarioId,
}) {
  _validarNombre(nombre);
  _validarInsumo(contenidoEnvaseMilesimas: contenidoEnvaseMilesimas, costoEnvaseCentavos: costoEnvaseCentavos);
  return db.transaction(() async {
    final id = await crearProducto(
      db,
      nombre: nombre.trim(),
      categoriaId: categoriaId,
      proveedorId: proveedorId,
      costoCentavos: costoEnvaseCentavos,
      usuarioId: usuarioId,
    );
    await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
      ProductosCompanion(
        esInsumo: const Value(true),
        unidadInsumo: Value(unidad.clave),
        contenidoEnvaseMilesimas: Value(contenidoEnvaseMilesimas),
        stockMilesimas: const Value(0),
        stockMinimoMilesimas: Value(stockMinimoMilesimas),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    return id;
  });
}

/// Edición de un insumo (sin el stock: eso es [contarInsumo]). Un cambio del costo del envase queda en el historial.
Future<void> editarInsumo(
  AppDatabase db, {
  required int id,
  required String nombre,
  required UnidadInsumo unidad,
  required int contenidoEnvaseMilesimas,
  required int costoEnvaseCentavos,
  int? proveedorId,
  int? categoriaId,
  int? stockMinimoMilesimas,
  required int usuarioId,
}) {
  _validarNombre(nombre);
  _validarInsumo(contenidoEnvaseMilesimas: contenidoEnvaseMilesimas, costoEnvaseCentavos: costoEnvaseCentavos);
  return db.transaction(() async {
    final anterior = await _producto(db, id);
    if (!anterior.esInsumo) throw ArgumentError('"${anterior.nombre}" no es un insumo');
    await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
      ProductosCompanion(
        nombre: Value(nombre.trim()),
        unidadInsumo: Value(unidad.clave),
        contenidoEnvaseMilesimas: Value(contenidoEnvaseMilesimas),
        costoCentavos: Value(costoEnvaseCentavos),
        proveedorId: Value(proveedorId),
        categoriaId: Value(categoriaId),
        stockMinimoMilesimas: Value(stockMinimoMilesimas),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    await registrarCambioDePrecio(
      db,
      productoId: id,
      usuarioId: usuarioId,
      anterior: anterior,
      precioCentavos: anterior.precioCentavos,
      costoCentavos: costoEnvaseCentavos,
      precioPorKiloCentavos: anterior.precioPorKiloCentavos,
      costoPorKiloCentavos: anterior.costoPorKiloCentavos,
    );
  });
}

/// Mueve el stock de un insumo a [posterior] y deja el movimiento. Única forma de tocar `stock_milesimas` (convención 6).
Future<void> _moverStockDeInsumo(
  AppDatabase db, {
  required Producto insumo,
  required int posterior,
  required int milesimas,
  required int usuarioId,
  required String motivo,
}) async {
  final anterior = insumo.stockMilesimas ?? 0;
  await (db.update(db.productos)..where((p) => p.id.equals(insumo.id))).write(
    ProductosCompanion(stockMilesimas: Value(posterior), actualizadoEn: Value(DateTime.now())),
  );
  await db.into(db.movimientosDeStock).insert(
        MovimientosDeStockCompanion.insert(
          productoId: insumo.id,
          usuarioId: usuarioId,
          tipo: 'AJUSTE',
          milesimas: Value(milesimas),
          milesimasAnterior: Value(anterior),
          milesimasPosterior: Value(posterior),
          motivo: Value(motivo),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Una compra de [envases] envases: suma su contenido al stock. Con [costoEnvaseCentavos] distinto al de hoy, el costo
/// pasa a ser ese (y queda en el historial): lo que vale reponerlo es lo último que se pagó, como en el almacén.
Future<void> cargarCompraDeInsumo(
  AppDatabase db, {
  required int insumoId,
  required int envases,
  int? costoEnvaseCentavos,
  required int usuarioId,
}) {
  if (costoEnvaseCentavos != null && costoEnvaseCentavos < 0) throw ArgumentError('El costo del envase no puede ser negativo');
  return db.transaction(() async {
    final insumo = await _producto(db, insumoId);
    if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
    final entra = milesimasDeCompra(envases: envases, contenidoEnvaseMilesimas: insumo.contenidoEnvaseMilesimas ?? 0);
    await _moverStockDeInsumo(
      db,
      insumo: insumo,
      posterior: (insumo.stockMilesimas ?? 0) + entra,
      milesimas: entra,
      usuarioId: usuarioId,
      motivo: envases == 1 ? 'Compra de 1 envase' : 'Compra de $envases envases',
    );
    if (costoEnvaseCentavos != null && costoEnvaseCentavos != insumo.costoCentavos) {
      await (db.update(db.productos)..where((p) => p.id.equals(insumoId))).write(
        ProductosCompanion(costoCentavos: Value(costoEnvaseCentavos), actualizadoEn: Value(DateTime.now())),
      );
      await registrarCambioDePrecio(
        db,
        productoId: insumoId,
        usuarioId: usuarioId,
        anterior: insumo,
        precioCentavos: insumo.precioCentavos,
        costoCentavos: costoEnvaseCentavos,
        precioPorKiloCentavos: insumo.precioPorKiloCentavos,
        costoPorKiloCentavos: insumo.costoPorKiloCentavos,
      );
    }
  });
}

/// Conteo físico: el stock pasa a ser [stockMilesimas]. Sin cambio no deja movimiento (no hubo nada que corregir).
Future<void> contarInsumo(AppDatabase db, {required int insumoId, required int stockMilesimas, required int usuarioId}) {
  if (stockMilesimas < 0) throw ArgumentError('Lo contado no puede ser negativo');
  return db.transaction(() async {
    final insumo = await _producto(db, insumoId);
    if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
    final anterior = insumo.stockMilesimas ?? 0;
    if (anterior == stockMilesimas) return;
    await _moverStockDeInsumo(
      db,
      insumo: insumo,
      posterior: stockMilesimas,
      milesimas: stockMilesimas - anterior,
      usuarioId: usuarioId,
      motivo: 'Conteo físico',
    );
  });
}

// --- Servicios ----------------------------------------------------------------------------------------------------------

/// La receta como viaja por la sync: por `global_id`. Un insumo viejo sin `global_id` recibe uno (como en las promos).
Future<String> _recetaEnJson(AppDatabase db, List<LineaDeReceta> receta) async {
  final lista = <Map<String, Object>>[];
  for (final l in receta) {
    final insumo = await _producto(db, l.insumoId);
    if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
    var gid = insumo.globalId;
    if (gid == null) {
      gid = generarGlobalId();
      await (db.update(db.productos)..where((p) => p.id.equals(insumo.id))).write(
        ProductosCompanion(globalId: Value(gid), origenDispositivo: Value(idDispositivoActual), actualizadoEn: Value(DateTime.now())),
      );
    }
    lista.add({'gid': gid, 'milesimas': l.milesimas});
  }
  return jsonEncode(lista);
}

/// Alta de un servicio. Sin [gananciaBuscadaBp] usa la de arranque (60 %, `gananciaBuscadaPorDefectoBp`).
Future<int> crearServicio(
  AppDatabase db, {
  required String nombre,
  required int precioCentavos,
  required int duracionMinutos,
  List<LineaDeReceta> receta = const [],
  bool sumaManoDeObra = false,
  int? gananciaBuscadaBp,
  int? categoriaId,
  required int usuarioId,
}) {
  _validarNombre(nombre);
  _validarServicio(precioCentavos: precioCentavos, duracionMinutos: duracionMinutos, receta: receta, gananciaBuscadaBp: gananciaBuscadaBp);
  return db.transaction(() async {
    final id = await crearProducto(
      db,
      nombre: nombre.trim(),
      categoriaId: categoriaId,
      precioCentavos: precioCentavos,
      usuarioId: usuarioId,
    );
    await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
      ProductosCompanion(
        esServicio: const Value(true),
        duracionMinutos: Value(duracionMinutos),
        recetaServicio: Value(await _recetaEnJson(db, receta)),
        sumaManoDeObra: Value(sumaManoDeObra),
        gananciaBuscadaBp: Value(gananciaBuscadaBp),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    return id;
  });
}

/// Edición de un servicio. Un cambio de precio queda en el historial.
Future<void> editarServicio(
  AppDatabase db, {
  required int id,
  required String nombre,
  required int precioCentavos,
  required int duracionMinutos,
  List<LineaDeReceta> receta = const [],
  bool sumaManoDeObra = false,
  int? gananciaBuscadaBp,
  int? categoriaId,
  required int usuarioId,
}) {
  _validarNombre(nombre);
  _validarServicio(precioCentavos: precioCentavos, duracionMinutos: duracionMinutos, receta: receta, gananciaBuscadaBp: gananciaBuscadaBp);
  return db.transaction(() async {
    final anterior = await _producto(db, id);
    if (!anterior.esServicio) throw ArgumentError('"${anterior.nombre}" no es un servicio');
    await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
      ProductosCompanion(
        nombre: Value(nombre.trim()),
        precioCentavos: Value(precioCentavos),
        duracionMinutos: Value(duracionMinutos),
        recetaServicio: Value(await _recetaEnJson(db, receta)),
        sumaManoDeObra: Value(sumaManoDeObra),
        gananciaBuscadaBp: Value(gananciaBuscadaBp),
        categoriaId: Value(categoriaId),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    await registrarCambioDePrecio(
      db,
      productoId: id,
      usuarioId: usuarioId,
      anterior: anterior,
      precioCentavos: precioCentavos,
      costoCentavos: anterior.costoCentavos,
      precioPorKiloCentavos: anterior.precioPorKiloCentavos,
      costoPorKiloCentavos: anterior.costoPorKiloCentavos,
    );
  });
}

// --- Listados -----------------------------------------------------------------------------------------------------------

InsumoListado _insumoListado(Producto p) {
  final unidad = UnidadInsumo.desdeClave(p.unidadInsumo) ?? UnidadInsumo.u;
  final contenido = p.contenidoEnvaseMilesimas ?? 0;
  final costo = p.costoCentavos;
  return InsumoListado(
    producto: p,
    unidad: unidad,
    costoPorUnidadCentavos: costo == null || contenido <= 0
        ? null
        : costoPorUnidadCentavos(InsumoParaCalculo(costoEnvaseCentavos: costo, contenidoEnvaseMilesimas: contenido, stockMilesimas: 0)),
  );
}

/// Los insumos, por nombre. [incluirInactivos] para la pantalla de gestión (los dados de baja se pueden reactivar).
Future<List<InsumoListado>> listarInsumos(AppDatabase db, {bool incluirInactivos = false}) async {
  final q = db.select(db.productos)
    ..where((p) => p.esInsumo.equals(true) & (incluirInactivos ? const Constant(true) : p.activo.equals(true)))
    ..orderBy([(p) => OrderingTerm.asc(p.nombre)]);
  return [for (final p in await q.get()) _insumoListado(p)];
}

/// Los servicios con su costo de hoy. La mano de obra entra solo si el servicio la suma, el módulo está prendido
/// ([conManoDeObra]) y el negocio cargó el valor de la hora.
Future<List<ServicioListado>> listarServicios(AppDatabase db, {bool incluirInactivos = false, required bool conManoDeObra}) async {
  final config = await db.select(db.configuracionNegocioTabla).getSingleOrNull();
  final valorHora = conManoDeObra ? config?.valorHoraCentavos : null;

  final insumosPorGid = {
    for (final p in await (db.select(db.productos)..where((p) => p.esInsumo.equals(true) & p.globalId.isNotNull())).get())
      p.globalId!: _insumoListado(p),
  };

  final q = db.select(db.productos)
    ..where((p) => p.esServicio.equals(true) & (incluirInactivos ? const Constant(true) : p.activo.equals(true)))
    ..orderBy([(p) => OrderingTerm.asc(p.nombre)]);

  final resultado = <ServicioListado>[];
  for (final s in await q.get()) {
    final receta = <UsoListado>[];
    var faltantes = 0;
    for (final l in recetaDesdeJson(s.recetaServicio)) {
      final insumo = insumosPorGid[l.gid];
      if (insumo == null) {
        faltantes++;
      } else {
        receta.add(UsoListado(insumo: insumo, milesimas: l.milesimas));
      }
    }
    // Un insumo sin contenido de envase (dato roto) no se puede calcular: cuenta como faltante en vez de tirar la lista.
    final calculables = [for (final u in receta) if ((u.insumo.producto.contenidoEnvaseMilesimas ?? 0) > 0) u];
    faltantes += receta.length - calculables.length;
    final usos = [for (final u in calculables) UsoDeInsumo(insumo: u.insumo.paraCalculo, cantidadMilesimas: u.milesimas)];
    final costo = costoDeServicio(
      receta: usos,
      duracionMinutos: s.duracionMinutos ?? 0,
      valorHoraCentavos: s.sumaManoDeObra ? valorHora : null,
    );
    final primero = seAcabaPrimero(usos);
    resultado.add(
      ServicioListado(
        producto: s,
        receta: receta,
        faltantes: faltantes,
        costo: costo,
        precioSugeridoCentavos: precioSugeridoCentavos(
          costoCentavos: costo.totalCentavos,
          gananciaBuscadaBp: s.gananciaBuscadaBp ?? gananciaBuscadaPorDefectoBp,
        ),
        alcanzaPara: alcanzaPara(usos),
        seAcabaPrimero: primero == null ? null : calculables[primero].insumo,
      ),
    );
  }
  return resultado;
}

/// La receta guardada (`productos.receta_servicio`). Un JSON roto o vacío es una receta vacía: listar nunca se corta por
/// un dato raro que llegó por la sync.
List<({String gid, int milesimas})> recetaDesdeJson(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final lista = jsonDecode(json);
    if (lista is! List) return const [];
    return [
      for (final e in lista)
        if (e is Map && e['gid'] is String && e['milesimas'] is num) (gid: e['gid'] as String, milesimas: (e['milesimas'] as num).toInt()),
    ];
  } on FormatException {
    return const [];
  }
}
