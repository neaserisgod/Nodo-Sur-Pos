// Servicios e insumos (`docs/PLAN-SERVICIOS.md`, etapa 2): darlos de alta, comprar y contar insumos, y listar cada servicio
// con lo que cuesta hoy y para cuántos alcanza. Las cuentas viven en `domain/servicios.dart`; acá solo se leen y guardan.
//
// Insumo y servicio son filas de `productos` (con `esInsumo` / `esServicio`), así heredan la sync, el historial de precios,
// el proveedor y las categorías sin nada nuevo. El stock de un insumo va en milésimas (`stock_milesimas`) y cada cambio deja
// su movimiento con `milesimas_anterior/posterior` (convención 6): la sync arma el número con esos deltas, nunca pisándolo,
// igual que el stock en gramos de un pesable.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/modulos.dart';
import '../domain/servicios.dart';
import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_configuracion.dart';
import 'repositorio_productos.dart' show cambiarActivo, registrarCambioDePrecio;

/// Un insumo con lo que hace falta para las cuentas del dominio.
InsumoParaCalculo insumoParaCalculo(Producto insumo) => InsumoParaCalculo(
      costoEnvaseCentavos: insumo.costoCentavos ?? 0,
      contenidoEnvaseMilesimas: insumo.contenidoEnvaseMilesimas ?? 0,
      stockMilesimas: insumo.stockMilesimas ?? 0,
    );

String _nombreValido(String nombre) {
  final limpio = nombre.trim();
  if (limpio.isEmpty) throw ArgumentError('Falta el nombre');
  return limpio;
}

void _validarEnvase({required int contenidoEnvaseMilesimas, required int costoEnvaseCentavos}) {
  if (contenidoEnvaseMilesimas <= 0) throw ArgumentError('El envase tiene que traer algo (contenido mayor a 0)');
  if (costoEnvaseCentavos < 0) throw ArgumentError('El costo del envase no puede ser negativo');
}

Future<Producto> _producto(AppDatabase db, int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();

/// Deja el rastro de un cambio de stock de un insumo (convención 6). Sin cambio, nada.
Future<void> _movimientoDeInsumo(
  AppDatabase db, {
  required int insumoId,
  required int usuarioId,
  required int anterior,
  required int posterior,
  required String motivo,
}) async {
  if (anterior == posterior) return;
  await db.into(db.movimientosDeStock).insert(
        MovimientosDeStockCompanion.insert(
          productoId: insumoId,
          usuarioId: usuarioId,
          tipo: 'AJUSTE',
          milesimas: Value(posterior - anterior),
          milesimasAnterior: Value(anterior),
          milesimasPosterior: Value(posterior),
          motivo: Value(motivo),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
        ),
      );
}

/// Alta de un insumo. [costoEnvaseCentavos] es lo que se paga por un envase (va a `costo_centavos`, con su historial) y
/// [stockMilesimas] lo que hay al darlo de alta.
Future<int> crearInsumo(
  AppDatabase db, {
  required String nombre,
  required UnidadInsumo unidad,
  required int contenidoEnvaseMilesimas,
  required int costoEnvaseCentavos,
  int stockMilesimas = 0,
  int? stockMinimoMilesimas,
  int? proveedorId,
  int? categoriaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final nombreLimpio = _nombreValido(nombre);
    _validarEnvase(contenidoEnvaseMilesimas: contenidoEnvaseMilesimas, costoEnvaseCentavos: costoEnvaseCentavos);
    if (stockMilesimas < 0) throw ArgumentError('El stock no puede ser negativo');

    final id = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: nombreLimpio,
            esInsumo: const Value(true),
            unidadInsumo: Value(unidad.clave),
            contenidoEnvaseMilesimas: Value(contenidoEnvaseMilesimas),
            costoCentavos: Value(costoEnvaseCentavos),
            // El stock inicial va en el alta, sin movimiento, como `crearProducto`: la fila nueva viaja con él y un movimiento
            // además lo contaría dos veces en el otro equipo.
            stockMilesimas: Value(stockMilesimas),
            stockMinimoMilesimas: Value(stockMinimoMilesimas),
            proveedorId: Value(proveedorId),
            categoriaId: Value(categoriaId),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
    await registrarCambioDePrecio(
      db,
      productoId: id,
      usuarioId: usuarioId,
      anterior: null,
      precioCentavos: null,
      costoCentavos: costoEnvaseCentavos,
      precioPorKiloCentavos: null,
      costoPorKiloCentavos: null,
    );
    return id;
  });
}

/// Edición de un insumo (no toca el stock: eso es [cargarCompraDeInsumo] o [contarInsumo]). Cambiar el costo del envase
/// deja su historial de precios.
Future<void> editarInsumo(
  AppDatabase db, {
  required int insumoId,
  required String nombre,
  required UnidadInsumo unidad,
  required int contenidoEnvaseMilesimas,
  required int costoEnvaseCentavos,
  int? stockMinimoMilesimas,
  int? proveedorId,
  int? categoriaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final nombreLimpio = _nombreValido(nombre);
    _validarEnvase(contenidoEnvaseMilesimas: contenidoEnvaseMilesimas, costoEnvaseCentavos: costoEnvaseCentavos);
    final anterior = await _producto(db, insumoId);
    if (!anterior.esInsumo) throw ArgumentError('"${anterior.nombre}" no es un insumo');

    await (db.update(db.productos)..where((p) => p.id.equals(insumoId))).write(
      ProductosCompanion(
        nombre: Value(nombreLimpio),
        unidadInsumo: Value(unidad.clave),
        contenidoEnvaseMilesimas: Value(contenidoEnvaseMilesimas),
        costoCentavos: Value(costoEnvaseCentavos),
        stockMinimoMilesimas: Value(stockMinimoMilesimas),
        proveedorId: Value(proveedorId),
        categoriaId: Value(categoriaId),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    await registrarCambioDePrecio(
      db,
      productoId: insumoId,
      usuarioId: usuarioId,
      anterior: anterior,
      precioCentavos: anterior.precioCentavos,
      costoCentavos: costoEnvaseCentavos,
      precioPorKiloCentavos: anterior.precioPorKiloCentavos,
      costoPorKiloCentavos: anterior.costoPorKiloCentavos,
    );
  });
}

/// Una compra de [envases] envases del insumo: suma su contenido al stock. Con [costoEnvaseCentavos], ese es el costo nuevo
/// del envase (con su historial, como una factura que trae otro precio).
Future<void> cargarCompraDeInsumo(
  AppDatabase db, {
  required int insumoId,
  required int envases,
  int? costoEnvaseCentavos,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final insumo = await _producto(db, insumoId);
    if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
    final entra = milesimasDeCompra(envases: envases, contenidoEnvaseMilesimas: insumo.contenidoEnvaseMilesimas ?? 0);
    final anterior = insumo.stockMilesimas ?? 0;
    final costoNuevo = costoEnvaseCentavos ?? insumo.costoCentavos;
    if (costoNuevo != null && costoNuevo < 0) throw ArgumentError('El costo del envase no puede ser negativo');

    await (db.update(db.productos)..where((p) => p.id.equals(insumoId))).write(
      ProductosCompanion(
        stockMilesimas: Value(anterior + entra),
        costoCentavos: Value(costoNuevo),
        actualizadoEn: Value(DateTime.now()),
      ),
    );
    await _movimientoDeInsumo(
      db,
      insumoId: insumoId,
      usuarioId: usuarioId,
      anterior: anterior,
      posterior: anterior + entra,
      motivo: 'Compra · $envases ${envases == 1 ? 'envase' : 'envases'}',
    );
    await registrarCambioDePrecio(
      db,
      productoId: insumoId,
      usuarioId: usuarioId,
      anterior: insumo,
      precioCentavos: insumo.precioCentavos,
      costoCentavos: costoNuevo,
      precioPorKiloCentavos: insumo.precioPorKiloCentavos,
      costoPorKiloCentavos: insumo.costoPorKiloCentavos,
    );
  });
}

/// Lo que se contó de un insumo, en milésimas: queda ese stock, con su ajuste.
Future<void> contarInsumo(
  AppDatabase db, {
  required int insumoId,
  required int stockMilesimas,
  required int usuarioId,
  String motivo = 'Conteo físico',
}) {
  return db.transaction(() async {
    if (stockMilesimas < 0) throw ArgumentError('El stock contado no puede ser negativo');
    final insumo = await _producto(db, insumoId);
    if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
    final anterior = insumo.stockMilesimas ?? 0;
    if (anterior == stockMilesimas) return;
    await (db.update(db.productos)..where((p) => p.id.equals(insumoId))).write(
      ProductosCompanion(stockMilesimas: Value(stockMilesimas), actualizadoEn: Value(DateTime.now())),
    );
    await _movimientoDeInsumo(db, insumoId: insumoId, usuarioId: usuarioId, anterior: anterior, posterior: stockMilesimas, motivo: motivo);
  });
}

/// Una línea de la receta tal como la arma el creador: qué insumo (id local) y cuánto usa, en milésimas.
typedef LineaDeReceta = ({int insumoId, int milesimas});

/// Crea (o, con [servicioId], edita) un servicio. La receta se guarda por `global_id` de cada insumo para que viaje por la
/// sync (como `componentes_promo`). `costo_centavos` queda con lo que cuestan hoy sus insumos (la mano de obra no
/// es costo, Regla 20): el que se muestra al día sale siempre de [listarServicios], que lo recalcula con los costos de cada
/// insumo, y el de una venta, del momento en que se cobra.
///
/// Devuelve el id del servicio.
Future<int> guardarServicio(
  AppDatabase db, {
  int? servicioId,
  required String nombre,
  required int precioCentavos,
  required int duracionMinutos,
  required List<LineaDeReceta> receta,
  bool sumaManoDeObra = false,
  int? gananciaBuscadaBp,
  int? categoriaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final nombreLimpio = _nombreValido(nombre);
    if (precioCentavos < 0) throw ArgumentError('El precio no puede ser negativo');
    if (duracionMinutos <= 0) throw ArgumentError('El servicio tiene que durar algo');
    if (gananciaBuscadaBp != null && (gananciaBuscadaBp < 0 || gananciaBuscadaBp >= 10000)) {
      throw ArgumentError('La ganancia buscada va de 0 a menos de 100 %');
    }
    if (receta.map((l) => l.insumoId).toSet().length != receta.length) {
      throw ArgumentError('Un insumo está dos veces en la receta');
    }

    final usos = <UsoDeInsumo>[];
    final recetaGuardada = <Map<String, Object>>[];
    for (final linea in receta) {
      if (linea.milesimas <= 0) throw ArgumentError('Cada insumo de la receta tiene que usar algo');
      final insumo = await _producto(db, linea.insumoId);
      if (!insumo.esInsumo) throw ArgumentError('"${insumo.nombre}" no es un insumo');
      if (insumo.globalId == null) throw StateError('"${insumo.nombre}" no tiene identidad de sincronización');
      usos.add(UsoDeInsumo(insumo: insumoParaCalculo(insumo), cantidadMilesimas: linea.milesimas));
      recetaGuardada.add({'gid': insumo.globalId!, 'milesimas': linea.milesimas});
    }

    // Solo los insumos: la mano de obra es una referencia para el precio, no un costo de la venta (Regla 20).
    final costo = costoInsumosCentavos(usos);

    final anterior = servicioId == null ? null : await _producto(db, servicioId);
    if (anterior != null && !anterior.esServicio) throw ArgumentError('"${anterior.nombre}" no es un servicio');

    final int id;
    if (anterior == null) {
      id = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: nombreLimpio,
              esServicio: const Value(true),
              // El precio de un servicio lo pone quien lo da (con la sugerencia a la vista): no lo mueve el porcentaje de
              // ningún proveedor.
              precioFijo: const Value(true),
              precioCentavos: Value(precioCentavos),
              costoCentavos: Value(costo),
              duracionMinutos: Value(duracionMinutos),
              recetaServicio: Value(jsonEncode(recetaGuardada)),
              sumaManoDeObra: Value(sumaManoDeObra),
              gananciaBuscadaBp: Value(gananciaBuscadaBp),
              categoriaId: Value(categoriaId),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );
    } else {
      id = anterior.id;
      await (db.update(db.productos)..where((p) => p.id.equals(id))).write(
        ProductosCompanion(
          nombre: Value(nombreLimpio),
          precioCentavos: Value(precioCentavos),
          costoCentavos: Value(costo),
          duracionMinutos: Value(duracionMinutos),
          recetaServicio: Value(jsonEncode(recetaGuardada)),
          sumaManoDeObra: Value(sumaManoDeObra),
          gananciaBuscadaBp: Value(gananciaBuscadaBp),
          categoriaId: Value(categoriaId),
          activo: const Value(true),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
    }
    await registrarCambioDePrecio(
      db,
      productoId: id,
      usuarioId: usuarioId,
      anterior: anterior,
      precioCentavos: precioCentavos,
      costoCentavos: costo,
      precioPorKiloCentavos: null,
      costoPorKiloCentavos: null,
    );
    return id;
  });
}

/// Deja de ofrecer un servicio (o de usar un insumo). No se borra: lo vendido y su historial siguen apuntando a la fila.
Future<void> dejarDeOfrecer(AppDatabase db, int productoId) => cambiarActivo(db, id: productoId, activo: false);

/// Un insumo de la lista, con su costo por unidad de uso ("$ 733/ml") y si está bajo el mínimo.
class InsumoConCosto {
  const InsumoConCosto({required this.insumo, required this.unidad, required this.costoPorUnidadCentavos});

  final Producto insumo;
  final UnidadInsumo unidad;

  /// Null si al insumo le falta el contenido del envase (no hay con qué calcular).
  final int? costoPorUnidadCentavos;

  int get stockMilesimas => insumo.stockMilesimas ?? 0;

  bool get stockBajo {
    final minimo = insumo.stockMinimoMilesimas ?? 0;
    return minimo > 0 && stockMilesimas <= minimo;
  }
}

/// Los insumos por nombre. [soloActivos] deja afuera los que se dejaron de usar.
Future<List<InsumoConCosto>> listarInsumos(AppDatabase db, {bool soloActivos = true}) async {
  final filas = await (db.select(db.productos)
        ..where((p) => p.esInsumo.equals(true) & (soloActivos ? p.activo.equals(true) : const Constant(true)))
        ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
      .get();
  return [
    for (final f in filas)
      InsumoConCosto(
        insumo: f,
        unidad: UnidadInsumo.desdeClave(f.unidadInsumo) ?? UnidadInsumo.u,
        costoPorUnidadCentavos: (f.contenidoEnvaseMilesimas ?? 0) > 0 ? costoPorUnidadCentavos(insumoParaCalculo(f)) : null,
      ),
  ];
}

/// Una línea de la receta ya resuelta contra la base de este equipo.
class UsoDeInsumoResuelto {
  const UsoDeInsumoResuelto({required this.insumo, required this.cantidadMilesimas});

  final Producto insumo;
  final int cantidadMilesimas;

  UsoDeInsumo get paraCalculo => UsoDeInsumo(insumo: insumoParaCalculo(insumo), cantidadMilesimas: cantidadMilesimas);
}

/// Un servicio con su receta y las cuentas de hoy.
class ServicioConCosto {
  const ServicioConCosto({
    required this.servicio,
    required this.receta,
    required this.insumosSinLlegar,
    required this.costo,
    required this.alcanzaPara,
    required this.seAcabaPrimero,
  });

  final Producto servicio;
  final List<UsoDeInsumoResuelto> receta;

  /// Insumos de la receta que todavía no llegaron por la sync a este equipo (o se borraron): el costo no los cuenta, así
  /// que la pantalla lo avisa en vez de mostrar un número de menos como si fuera bueno.
  final int insumosSinLlegar;

  final CostoDeServicio costo;

  /// Null con la receta vacía.
  final int? alcanzaPara;

  /// El insumo que se acaba primero, o null con la receta vacía.
  final Producto? seAcabaPrimero;

  int get precioCentavos => servicio.precioCentavos ?? 0;
  int get gananciaBuscadaBp => servicio.gananciaBuscadaBp ?? gananciaBuscadaPorDefectoBp;
  int get precioSugerido => precioSugeridoCentavos(costoCentavos: costo.totalCentavos, gananciaBuscadaBp: gananciaBuscadaBp);
}

/// La receta guardada de un servicio, leída. Una receta ilegible se trata como vacía en vez de romper la lista.
List<({String gid, int milesimas})> recetaGuardada(Producto servicio) {
  final texto = servicio.recetaServicio;
  if (texto == null || texto.isEmpty) return const [];
  try {
    return [
      for (final l in jsonDecode(texto) as List)
        if (l is Map && l['gid'] is String && l['milesimas'] is int) (gid: l['gid'] as String, milesimas: l['milesimas'] as int),
    ];
  } on FormatException {
    return const [];
  }
}

/// Los servicios por nombre, con lo que cuestan hoy y para cuántos alcanza. [soloActivos] deja afuera los que se dejaron de
/// ofrecer.
Future<List<ServicioConCosto>> listarServicios(AppDatabase db, {bool soloActivos = true}) async {
  final servicios = await (db.select(db.productos)
        ..where((p) => p.esServicio.equals(true) & (soloActivos ? p.activo.equals(true) : const Constant(true)))
        ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
      .get();
  if (servicios.isEmpty) return const [];

  final insumosPorGid = {
    for (final i in await (db.select(db.productos)..where((p) => p.esInsumo.equals(true))).get())
      if (i.globalId != null) i.globalId!: i,
  };
  final config = await configuracionNegocioActual(db);
  final manoDeObraActiva = modulosDeConfiguracion(config).estaActivo(Modulo.manoDeObra);

  return [
    for (final s in servicios) _conCosto(s, insumosPorGid, manoDeObraActiva ? config.valorHoraCentavos : null),
  ];
}

ServicioConCosto _conCosto(Producto servicio, Map<String, Producto> insumosPorGid, int? valorHoraCentavos) {
  final receta = <UsoDeInsumoResuelto>[];
  var sinLlegar = 0;
  for (final l in recetaGuardada(servicio)) {
    final insumo = insumosPorGid[l.gid];
    if (insumo == null) {
      sinLlegar++;
    } else {
      receta.add(UsoDeInsumoResuelto(insumo: insumo, cantidadMilesimas: l.milesimas));
    }
  }
  final usos = [for (final u in receta) u.paraCalculo];
  final primero = seAcabaPrimero(usos);
  return ServicioConCosto(
    servicio: servicio,
    receta: receta,
    insumosSinLlegar: sinLlegar,
    costo: costoDeServicio(
      receta: usos,
      duracionMinutos: servicio.duracionMinutos ?? 0,
      valorHoraCentavos: servicio.sumaManoDeObra ? valorHoraCentavos : null,
    ),
    alcanzaPara: alcanzaPara(usos),
    seAcabaPrimero: primero == null ? null : receta[primero].insumo,
  );
}

// ───────────────────────── Cobrar servicios (etapa 3, Regla 20) ─────────────────────────

/// Un servicio no se cobra porque le falta un insumo (módulo "Bloquear si falta un insumo"). Es un `ArgumentError` para que
/// las pantallas que ya muestran el mensaje de uno (cobrar en el celular) lo muestren igual.
class InsumoFaltante extends ArgumentError {
  InsumoFaltante({required this.insumo, required this.servicio, required this.faltanMilesimas})
      : super(
          'Falta ${insumo.nombre.toLowerCase()} para "${servicio.nombre}": quedan '
          '${textoDeMilesimas(insumo.stockMilesimas ?? 0)} ${insumo.unidadInsumo ?? ''}. Cargá la compra primero.',
        );

  final Producto insumo;
  final Producto servicio;
  final int faltanMilesimas;
}

/// Lo que usa cada servicio de [linea] (por unidad): los ajustes de esa venta si los tiene y el módulo está prendido, si no
/// la receta. Un insumo que todavía no llegó por la sync se saltea (no hay de dónde descontarlo). Con el módulo de insumos
/// apagado no se usa nada: el servicio se cobra sin tocar insumos.
Future<List<(Producto insumo, int milesimas)>> _usoDeLinea(
  AppDatabase db,
  Producto servicio,
  LineaVentaPorUnidad linea,
  ModulosNegocio modulos,
) async {
  if (!modulos.estaActivo(Modulo.insumos)) return const [];
  final ajustes = modulos.estaActivo(Modulo.ajustarInsumos) ? linea.insumosAjustados : null;
  if (ajustes != null) {
    final insumos = ajustes.isEmpty ? const <Producto>[] : await (db.select(db.productos)..where((p) => p.id.isIn(ajustes.keys))).get();
    return [
      for (final i in insumos)
        if (i.esInsumo && (ajustes[i.id] ?? 0) > 0) (i, ajustes[i.id]!),
    ];
  }
  final receta = recetaGuardada(servicio);
  if (receta.isEmpty) return const [];
  final porGid = {
    for (final i in await (db.select(db.productos)..where((p) => p.globalId.isIn([for (final l in receta) l.gid]))).get()) i.globalId!: i,
  };
  return [
    for (final l in receta)
      if (porGid[l.gid] case final insumo?) (insumo, l.milesimas),
  ];
}

Future<Producto?> _servicioDeLinea(AppDatabase db, LineaVenta linea) async {
  if (linea is! LineaVentaPorUnidad || linea.esVarios) return null;
  final id = int.tryParse(linea.productoId);
  if (id == null) return null;
  final p = await (db.select(db.productos)..where((t) => t.id.equals(id))).getSingleOrNull();
  return p != null && p.esServicio ? p : null;
}

/// Si "Bloquear si falta un insumo" está prendido, que alcance lo que pide el carrito ENTERO (dos kappings piden el doble de
/// top coat). Si no alcanza, [InsumoFaltante]. Apagado, nada: se cobra igual y el stock puede quedar negativo (Regla 20).
Future<void> exigirInsumosParaCobrar(AppDatabase db, List<LineaVenta> lineas) async {
  final modulos = await modulosNegocioActuales(db);
  if (!modulos.estaActivo(Modulo.insumos) || !modulos.estaActivo(Modulo.bloquearInsumos)) return;
  final necesario = <int, int>{};
  final insumos = <int, Producto>{};
  final deQuien = <int, Producto>{};
  for (final linea in lineas) {
    final servicio = await _servicioDeLinea(db, linea);
    if (servicio == null) continue;
    for (final (insumo, milesimas) in await _usoDeLinea(db, servicio, linea as LineaVentaPorUnidad, modulos)) {
      necesario.update(insumo.id, (a) => a + milesimas * linea.cantidad, ifAbsent: () => milesimas * linea.cantidad);
      insumos[insumo.id] = insumo;
      deQuien.putIfAbsent(insumo.id, () => servicio);
    }
  }
  final falta = primerFaltante(necesario, (id) => insumos[id]!.stockMilesimas ?? 0);
  if (falta != null) {
    throw InsumoFaltante(
      insumo: insumos[falta]!,
      servicio: deQuien[falta]!,
      faltanMilesimas: necesario[falta]! - (insumos[falta]!.stockMilesimas ?? 0),
    );
  }
}

/// Graba la línea de un servicio cobrado: UNA línea con el nombre del servicio (la del ticket) y su costo de insumos, lo que
/// gastó de cada insumo en `consumos_de_linea` (costo-foto y proveedor de cada uno) y, si [afectaStock], el descuento de cada
/// insumo con su movimiento. Lo llama `registrarLineaOPromo` (`repositorio_ventas.dart`) al cobrar y al editar una venta.
Future<void> registrarServicioEnVenta(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
  required Producto servicio,
  required LineaVentaPorUnidad linea,
  bool afectaStock = true,
}) async {
  final usos = await _usoDeLinea(db, servicio, linea, await modulosNegocioActuales(db));
  final calculo = consumosDeLinea(
    [for (final (insumo, milesimas) in usos) UsoDeInsumo(insumo: insumoParaCalculo(insumo), cantidadMilesimas: milesimas)],
    cantidad: linea.cantidad,
  );
  final lineaId = await db.into(db.lineasDeVenta).insert(
        LineasDeVentaCompanion.insert(
          ventaId: ventaId,
          productoId: Value(servicio.id),
          nombreProductoFoto: linea.nombreProducto,
          esServicio: const Value(true),
          cantidad: Value(linea.cantidad),
          precioUnitarioCentavos: linea.precioUnitarioCentavos,
          // El costo de hoy de sus insumos (no el que traía el carrito): es el que se descuenta ahora.
          costoUnitarioCentavos: Value(calculo.costoUnitarioCentavos),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
  for (var k = 0; k < usos.length; k++) {
    final insumo = usos[k].$1;
    final consumo = calculo.consumos[k];
    await db.into(db.consumosDeLinea).insert(
          ConsumosDeLineaCompanion.insert(
            lineaVentaId: lineaId,
            insumoId: insumo.id,
            milesimas: consumo.milesimas,
            costoCentavos: consumo.costoCentavos,
            proveedorIdFoto: Value(insumo.proveedorId),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
    if (!afectaStock) continue;
    // Se relee: el mismo insumo puede haberse descontado recién por otra línea de esta venta.
    final anterior = (await _producto(db, insumo.id)).stockMilesimas ?? 0;
    final posterior = anterior - consumo.milesimas;
    await (db.update(db.productos)..where((p) => p.id.equals(insumo.id))).write(ProductosCompanion(stockMilesimas: Value(posterior)));
    await db.into(db.movimientosDeStock).insert(
          MovimientosDeStockCompanion.insert(
            productoId: insumo.id,
            usuarioId: usuarioId,
            tipo: 'VENTA',
            ventaId: Value(ventaId),
            milesimas: Value(consumo.milesimas),
            milesimasAnterior: Value(anterior),
            milesimasPosterior: Value(posterior),
            motivo: Value(servicio.nombre),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  }
}

/// Devuelve al stock lo que gastó una línea de servicio (al anular o editar la venta, Regla 9), con su movimiento.
Future<void> devolverInsumosDeLinea(
  AppDatabase db, {
  required FilaLineaVenta linea,
  required int usuarioId,
  required String motivo,
}) async {
  final consumos = await (db.select(db.consumosDeLinea)..where((c) => c.lineaVentaId.equals(linea.id))).get();
  for (final c in consumos) {
    final anterior = (await _producto(db, c.insumoId)).stockMilesimas ?? 0;
    final posterior = anterior + c.milesimas;
    await (db.update(db.productos)..where((p) => p.id.equals(c.insumoId))).write(ProductosCompanion(stockMilesimas: Value(posterior)));
    await db.into(db.movimientosDeStock).insert(
          MovimientosDeStockCompanion.insert(
            productoId: c.insumoId,
            usuarioId: usuarioId,
            tipo: 'AJUSTE',
            ventaId: Value(linea.ventaId),
            milesimas: Value(c.milesimas),
            milesimasAnterior: Value(anterior),
            milesimasPosterior: Value(posterior),
            motivo: Value(motivo),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
  }
}

/// Un servicio tal como lo muestra Vender (Regla 20).
class ServicioParaVender {
  const ServicioParaVender({required this.servicio, this.alcanzaPara, this.falta});

  final Producto servicio;

  /// Para cuántos alcanza hoy, solo cuando eso limita el cobro (módulo de insumos y "Bloquear si falta un insumo"
  /// prendidos, con receta). Null: sin límite.
  final int? alcanzaPara;

  /// El insumo que no alcanza ni para uno: el servicio se ve con candado y no se puede agregar. Null si se puede cobrar.
  final Producto? falta;
}

/// Los servicios que se ofrecen, por nombre, con lo que necesita Vender para mostrarlos.
Future<List<ServicioParaVender>> serviciosParaVender(AppDatabase db) async {
  final servicios = await listarServicios(db);
  if (servicios.isEmpty) return const [];
  final modulos = await modulosNegocioActuales(db);
  final limita = modulos.estaActivo(Modulo.insumos) && modulos.estaActivo(Modulo.bloquearInsumos);
  return [
    for (final s in servicios)
      if (!limita || s.alcanzaPara == null)
        ServicioParaVender(servicio: s.servicio)
      else
        ServicioParaVender(servicio: s.servicio, alcanzaPara: s.alcanzaPara, falta: s.alcanzaPara! < 1 ? s.seAcabaPrimero : null),
  ];
}
