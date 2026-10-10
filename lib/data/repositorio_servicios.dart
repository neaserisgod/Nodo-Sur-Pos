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
/// sync (como `componentes_promo`). `costo_centavos` queda con el costo de hoy (insumos y, si corresponde, mano de obra): el
/// que se muestra al día sale siempre de [listarServicios], que lo recalcula con los costos de cada insumo.
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

    final costo = costoDeServicio(
      receta: usos,
      duracionMinutos: duracionMinutos,
      valorHoraCentavos: await _valorHoraSiSuma(db, sumaManoDeObra),
    ).totalCentavos;

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

/// El valor de la hora para sumar mano de obra: solo si el servicio la suma, el módulo está prendido y el valor está
/// cargado. Si no, null (esa parte del costo es 0).
Future<int?> _valorHoraSiSuma(AppDatabase db, bool sumaManoDeObra) async {
  if (!sumaManoDeObra) return null;
  final config = await configuracionNegocioActual(db);
  if (!modulosDeConfiguracion(config).estaActivo(Modulo.manoDeObra)) return null;
  return config.valorHoraCentavos;
}

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
