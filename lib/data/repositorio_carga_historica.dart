// Carga histórica producto por producto (reemplaza a la carga por planilla
// de la fase 9): la pantalla (`lib/ui/carga_historica/`) arma en memoria una
// lista de ventas con el mismo carrito que usa la venta en vivo, para una
// única fecha elegida una sola vez; acá se persiste todo junto, recién al
// guardar el día completo.
//
// Nada toca la base hasta `cargarDiaHistoricoDesdeVentas`: si el dueño cierra la
// app a mitad de carga, no queda ninguna sesión a medio armar dando vueltas.
//
// El arqueo se deja de lado a propósito (El dueño: "es simplemente para tener
// un histórico") — el día se cierra solo con contado = esperado (diferencia
// 0), reusando la misma fórmula que un cierre real (`calcularResumenCierre`/
// `cerrarSesion`, Regla 3: una sola fórmula, un solo lugar), nunca una nueva.
// Ninguna línea afecta el stock actual (`registrarVenta(afectaStock: false)`):
// esa mercadería ya se descontó en su momento.

import 'package:drift/drift.dart';

import '../domain/venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'linea_venta_reconstruccion.dart';
import 'repositorio_cierre.dart';
import 'repositorio_productos.dart' show listarProveedores;
import 'repositorio_ventas.dart';

/// Una venta ya armada con el carrito (líneas + total + pagos), esperando a
/// que se guarde el día completo.
class VentaHistoricaPendiente {
  final Venta venta;
  final ResultadoTotalVenta resultado;
  final List<PagoARegistrar> pagos;

  const VentaHistoricaPendiente({
    required this.venta,
    required this.resultado,
    required this.pagos,
  });
}

/// Marca las sesiones creadas por este archivo (para días pasados,
/// "como si fuesen ventas que no descuentan stock") — no pública hasta
/// 2026-09-13, cuando la pantalla de "Cierres" de la companion
/// (`servidor_companion.dart`) necesitó excluirlas de la lista de sesiones
/// reales cerradas (Regla 3: un solo lugar con este texto).
const notaCargaHistorica = 'Carga histórica';

/// Recalcula el resumen automático (contado = esperado, mismo criterio que
/// al cargar el día — El dueño: "el arqueo dejalo de lado") y lo vuelve a
/// escribir. La usan tanto crear un día nuevo como agregar o borrar una
/// venta de uno ya cargado (El dueño, 2026-09-07: "dejame verlos y
/// editarlos") — para que el resumen de Historial nunca quede
/// desactualizado respecto de lo que hay de verdad. `exigirAbierta: false`
/// (El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" agregó
/// esa guarda a `cerrarSesion` para el cierre real) — acá es una UPDATE
/// simple de los campos cacheados, intencionalmente segura de llamar de
/// nuevo sobre una sesión que ya está CERRADA.
Future<void> _recalcularResumenDiaHistorico(
  AppDatabase db, {
  required int sesionId,
  required int usuarioId,
  required DateTime fecha,
}) async {
  final resumen = await calcularResumenCierre(db, sesionId: sesionId, efectivoContadoCentavos: 0);
  await cerrarSesion(
    db,
    sesionId: sesionId,
    usuarioId: usuarioId,
    efectivoContadoCentavos: resumen.efectivoEsperadoCentavos,
    mpContadoCentavos: resumen.mpEsperadoCentavos,
    lataContadoCentavos: resumen.lataFinalCentavos,
    nota: notaCargaHistorica,
    fechaCierre: fecha,
    exigirAbierta: false,
  );
}

/// Crea la sesión del día [fecha], graba cada venta de [ventas] bajo ella
/// (sin tocar stock, con [fecha] como su fecha real) y la cierra sola con
/// arqueo automático. Todo en una sola transacción.
Future<int> cargarDiaHistoricoDesdeVentas(
  AppDatabase db, {
  required DateTime fecha,
  required int usuarioId,
  required List<VentaHistoricaPendiente> ventas,
}) {
  return db.transaction(() async {
    final sesionId = await db
        .into(db.sesionesDeCaja)
        .insert(
          SesionesDeCajaCompanion.insert(
            fechaApertura: Value(fecha),
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );

    for (final pendiente in ventas) {
      await registrarVenta(
        db,
        venta: pendiente.venta,
        resultado: pendiente.resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: pendiente.pagos,
        fecha: fecha,
        afectaStock: false,
      );
    }

    await _recalcularResumenDiaHistorico(db, sesionId: sesionId, usuarioId: usuarioId, fecha: fecha);
    return sesionId;
  });
}

/// Un día histórico ya cargado (El dueño, 2026-09-07: "dejame verlos y
/// editarlos porque le erré y lo cerré sin completarlo") — lo que se
/// necesita para listarlo en el celular.
class DiaHistorico {
  final int sesionId;
  final DateTime fecha;
  final int totalCentavos;
  final int cantidadVentas;
  const DiaHistorico({
    required this.sesionId,
    required this.fecha,
    required this.totalCentavos,
    required this.cantidadVentas,
  });
}

Future<List<DiaHistorico>> listarDiasHistoricos(AppDatabase db) async {
  final sesiones = await (db.select(db.sesionesDeCaja)
        ..where((s) => s.nota.equals(notaCargaHistorica))
        ..orderBy([(s) => OrderingTerm.desc(s.fechaApertura)]))
      .get();

  final resultado = <DiaHistorico>[];
  for (final s in sesiones) {
    final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(s.id))).get();
    resultado.add(
      DiaHistorico(
        sesionId: s.id,
        fecha: s.fechaApertura,
        totalCentavos: ventas.fold(0, (acc, v) => acc + v.totalCentavos),
        cantidadVentas: ventas.length,
      ),
    );
  }
  return resultado;
}

/// Una venta de un día histórico, resumida para mostrarla en el celular —
/// [medioResumen] es `'efectivo'` | `'virtual'` | `'mixto'`, mismo
/// vocabulario que usa `servidor_companion.dart` para vender.
class VentaHistoricaResumen {
  final int ventaId;
  final int totalCentavos;
  final String medioResumen;
  final String detalle;
  const VentaHistoricaResumen({
    required this.ventaId,
    required this.totalCentavos,
    required this.medioResumen,
    required this.detalle,
  });
}

Future<List<VentaHistoricaResumen>> ventasDeDiaHistorico(AppDatabase db, int sesionId) async {
  final mediosDePago = await db.select(db.mediosDePago).get();
  bool esEfectivo(int medioPagoId) =>
      mediosDePago.firstWhere((m) => m.id == medioPagoId).esEfectivo;

  final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
  final resultado = <VentaHistoricaResumen>[];
  for (final v in ventas) {
    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(v.id))).get();
    final pagos = await (db.select(db.pagos)..where((p) => p.ventaId.equals(v.id))).get();

    final medioResumen = pagos.length > 1
        ? 'mixto'
        : (pagos.isNotEmpty && esEfectivo(pagos.single.medioPagoId) ? 'efectivo' : 'virtual');

    final detalle = lineas
        .map((l) => l.esPesable ? '${l.nombreProductoFoto} (${l.gramos}g)' : '${l.nombreProductoFoto} x${l.cantidad}')
        .join(', ');

    resultado.add(
      VentaHistoricaResumen(
        ventaId: v.id,
        totalCentavos: v.totalCentavos,
        medioResumen: medioResumen,
        detalle: detalle,
      ),
    );
  }
  return resultado;
}

/// Agrega más ventas a un día ya cargado (El dueño: "le erré y lo cerré sin
/// completarlo" — seguir cargando en vez de tener que borrar todo). No
/// hace falta "reabrir" la sesión primero: `registrarVenta` no exige
/// ningún estado particular, y el resumen se recalcula solo al final.
Future<void> agregarVentasADiaHistorico(
  AppDatabase db, {
  required int sesionId,
  required int usuarioId,
  required List<VentaHistoricaPendiente> ventas,
}) {
  return db.transaction(() async {
    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
    for (final pendiente in ventas) {
      await registrarVenta(
        db,
        venta: pendiente.venta,
        resultado: pendiente.resultado,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        pagos: pendiente.pagos,
        fecha: sesion.fechaApertura,
        afectaStock: false,
      );
    }
    await _recalcularResumenDiaHistorico(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      fecha: sesion.fechaApertura,
    );
  });
}

/// Borra UNA venta de un día histórico — nunca toca stock (nunca lo tocó
/// al cargarla), así que no hace falta ninguna reversión, solo limpiar sus
/// propias filas y recalcular el resumen del día.
Future<void> eliminarVentaHistorica(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
}) {
  return db.transaction(() async {
    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    await (db.delete(db.movimientosDeCaja)..where((m) => m.ventaId.equals(ventaId))).go();
    await (db.delete(db.pagos)..where((p) => p.ventaId.equals(ventaId))).go();
    await (db.delete(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).go();
    await (db.delete(db.ventas)..where((v) => v.id.equals(ventaId))).go();

    final sesion = await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.id.equals(venta.sesionCajaId))).getSingle();
    await _recalcularResumenDiaHistorico(
      db,
      sesionId: venta.sesionCajaId,
      usuarioId: usuarioId,
      fecha: sesion.fechaApertura,
    );
  });
}

/// Borra el día completo — todas sus ventas y la sesión misma (El dueño: "le
/// erré... para recomenzarlo" — el escape hatch cuando conviene empezar de
/// cero antes que corregir venta por venta).
Future<void> eliminarDiaHistorico(AppDatabase db, {required int sesionId}) {
  return db.transaction(() async {
    final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
    for (final v in ventas) {
      await (db.delete(db.movimientosDeCaja)..where((m) => m.ventaId.equals(v.id))).go();
      await (db.delete(db.pagos)..where((p) => p.ventaId.equals(v.id))).go();
      await (db.delete(db.lineasDeVenta)..where((l) => l.ventaId.equals(v.id))).go();
    }
    await (db.delete(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).go();
    await (db.delete(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).go();
  });
}

/// Lo vendido de un proveedor en un día, y cuánto le corresponde separar
/// (Regla 5: la reposición es el costo real, no un porcentaje) — mismo
/// dato que ya calcula "Reportes" para el día en curso, acá para un día
/// histórico puntual.
class ResumenProveedorDia {
  final int proveedorId;
  final String nombreProveedor;
  final int vendidoCentavos;
  final int costoRealCentavos;
  final int gananciaCentavos;

  const ResumenProveedorDia({
    required this.proveedorId,
    required this.nombreProveedor,
    required this.vendidoCentavos,
    required this.costoRealCentavos,
    required this.gananciaCentavos,
  });
}

/// Un producto vendido ese día sin proveedor o sin costo cargado (El dueño,
/// 2026-09-07: "de lo vendido decime que no tiene costo o proveedor, así
/// le asignamos uno") — el detalle de `vendidoSinCostoCentavos`: no solo
/// cuánto falta completar, sino A QUÉ ir a completarle el dato.
class ProductoSinDatos {
  /// Null si el producto ya no existe en el catálogo (se borró después de
  /// esta venta) — no hay a dónde ir a completarlo.
  final int? productoId;
  final String nombreProducto;
  final int vendidoCentavos;
  final bool sinProveedor;
  final bool sinCosto;

  const ProductoSinDatos({
    required this.productoId,
    required this.nombreProducto,
    required this.vendidoCentavos,
    required this.sinProveedor,
    required this.sinCosto,
  });
}

/// El resumen de un día histórico (El dueño, 2026-09-07: "necesitaría un
/// resumen de lo vendido por medio de pago, por proveedor, y la
/// separación teórica") — nada de esto es una fórmula nueva: reusa
/// `efectivoDeVentasDelDia`/`pagosNoEfectivoDelDia` (por medio de pago) y
/// `reposicionDelDia` (por proveedor, Regla 5) tal cual ya las usa el
/// cierre y "Reportes" del día en curso (Regla 3).
class ResumenDiaHistorico {
  final int totalCentavos;
  final int efectivoCentavos;
  final int mercadoPagoCentavos;

  /// Precio de lista de los cigarrillos vendidos (Regla 6) — lo que hay
  /// que separar a la lata para Distribuidora de Cigarrillos. El dueño, 2026-09-07: "el
  /// arqueo muestra solamente una fracción del monto... así que me
  /// gustaría que aparezca" — antes ni el arqueo en vivo ni este resumen
  /// mostraban esta plata en ningún lado fuera del cierre real (que pide
  /// contar primero). Nunca entra en `porProveedor`: es la misma exclusión
  /// que ya hace `calcularReposicion` (Regla 6), acá solo se hace visible.
  final int cigarrillosListaCentavos;

  /// Vendido sin proveedor o sin costo cargado — no entra en ningún
  /// renglón de "por proveedor" porque no se sabe a quién ni cuánto
  /// separarle (mismo criterio que "Reportes").
  final int vendidoSinCostoCentavos;

  /// El detalle de `vendidoSinCostoCentavos`, producto por producto.
  final List<ProductoSinDatos> productosSinDatos;

  /// Ordenado de mayor a menor vendido — solo proveedores que vendieron
  /// algo ese día, no los 15 completos como en "Reportes" (acá interesa
  /// el día puntual, no el estado permanente de cada proveedor).
  final List<ResumenProveedorDia> porProveedor;

  const ResumenDiaHistorico({
    required this.totalCentavos,
    required this.efectivoCentavos,
    required this.mercadoPagoCentavos,
    required this.cigarrillosListaCentavos,
    required this.vendidoSinCostoCentavos,
    required this.productosSinDatos,
    required this.porProveedor,
  });
}

/// Detalle de `vendidoSinCostoCentavos`: agrupa por nombre de producto
/// (Regla 4, costo-foto — no por `productoId`, para no separar dos filas
/// de lo que a la vista es "el mismo producto" si se recreó con otro id).
/// Cigarrillos y "Varios" quedan afuera, mismo criterio que
/// `calcularReposicion`: los primeros no necesitan proveedor/costo acá
/// (se separan por la lata, Regla 6), y "Varios" nunca los tiene por
/// diseño (Regla 5) — no es algo para "ir a completar".
Future<List<ProductoSinDatos>> productosSinCostoOProveedorDelDia(
  AppDatabase db,
  int sesionId,
) async {
  final filas = await (db.select(db.lineasDeVenta).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
  ])
        ..where(
          db.ventas.sesionCajaId.equals(sesionId) &
              db.lineasDeVenta.tipoCigarrillo.equals('ninguno') &
              db.lineasDeVenta.esVarios.equals(false) &
              (db.lineasDeVenta.proveedorIdFoto.isNull() |
                  db.lineasDeVenta.costoUnitarioCentavos.isNull()),
        ))
      .get();

  final porNombre = <String, ({int? productoId, int vendidoCentavos, bool sinProveedor, bool sinCosto})>{};
  for (final fila in filas) {
    final linea = fila.readTable(db.lineasDeVenta);
    final precio = lineaParaReposicionDesde(linea).precioLineaCentavos;
    final previo = porNombre[linea.nombreProductoFoto];
    porNombre[linea.nombreProductoFoto] = (
      productoId: linea.productoId,
      vendidoCentavos: (previo?.vendidoCentavos ?? 0) + precio,
      sinProveedor: (previo?.sinProveedor ?? false) || linea.proveedorIdFoto == null,
      sinCosto: (previo?.sinCosto ?? false) || linea.costoUnitarioCentavos == null,
    );
  }

  return porNombre.entries
      .map(
        (e) => ProductoSinDatos(
          productoId: e.value.productoId,
          nombreProducto: e.key,
          vendidoCentavos: e.value.vendidoCentavos,
          sinProveedor: e.value.sinProveedor,
          sinCosto: e.value.sinCosto,
        ),
      )
      .toList()
    ..sort((a, b) => b.vendidoCentavos.compareTo(a.vendidoCentavos));
}

Future<ResumenDiaHistorico> resumenDiaHistorico(AppDatabase db, int sesionId) async {
  final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
  final totalCentavos = ventas.fold<int>(0, (acc, v) => acc + v.totalCentavos);

  final efectivo = await efectivoDeVentasDelDia(db, sesionId);
  final mercadoPago = await pagosNoEfectivoDelDia(db, sesionId);
  final cigarrillosLista = await precioListaCigarrillosDelDia(db, sesionId);
  final reposicion = await reposicionDelDia(db, sesionId);
  final productosSinDatos = await productosSinCostoOProveedorDelDia(db, sesionId);

  final proveedores = await listarProveedores(db);
  final nombrePorId = {for (final p in proveedores) p.id: p.nombre};

  final porProveedor =
      reposicion.vendidoPorProveedorCentavos.entries.map((entry) {
          final id = int.parse(entry.key);
          return ResumenProveedorDia(
            proveedorId: id,
            nombreProveedor: nombrePorId[id] ?? 'Proveedor #$id',
            vendidoCentavos: entry.value,
            costoRealCentavos: reposicion.costoRealPorProveedorCentavos[entry.key] ?? 0,
            gananciaCentavos: reposicion.gananciaPorProveedorCentavos[entry.key] ?? 0,
          );
        }).toList()
        ..sort((a, b) => b.vendidoCentavos.compareTo(a.vendidoCentavos));

  return ResumenDiaHistorico(
    totalCentavos: totalCentavos,
    efectivoCentavos: efectivo,
    mercadoPagoCentavos: mercadoPago,
    cigarrillosListaCentavos: cigarrillosLista,
    vendidoSinCostoCentavos: reposicion.vendidoSinCostoCentavos,
    productosSinDatos: productosSinDatos,
    porProveedor: porProveedor,
  );
}
