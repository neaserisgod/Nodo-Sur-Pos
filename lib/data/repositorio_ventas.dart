// El puente entre `data/` y `domain/` para el flujo de venta: convierte
// filas de `productos` en las estructuras que el dominio sabe calcular
// (lib/domain/venta.dart), y persiste una venta ya calculada en las tablas
// que la fase 2 dejó listas para esto.

import 'package:drift/drift.dart';

import '../domain/descuento.dart';
import '../domain/medio_pago.dart';
import '../domain/pesables.dart';
import '../domain/promo.dart';
import '../domain/recargo_cigarrillos.dart';
import '../domain/venta.dart';
import 'numero_venta.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_configuracion.dart' show configuracionNegocioActual;
import 'repositorio_encargues.dart' show liberarEncargueEntregado;

// ─── Sesión de caja ──────────────────────────────────────────────────────

Future<SesionCaja?> sesionAbierta(AppDatabase db) {
  return (db.select(db.sesionesDeCaja)
        ..where((s) => s.estado.equals('ABIERTA'))
        ..orderBy([(s) => OrderingTerm.desc(s.fechaApertura)])
        ..limit(1))
      .getSingleOrNull();
}

/// Se tira desde [verificarSesionAbierta] cuando [sesion] ya no está
/// `ABIERTA` — un gasto/ingreso rápido (o cualquier otro movimiento que
/// dependa de una sesión abierta) que llega justo después de un cierre debe
/// rechazarse, no grabarse contra una sesión cerrada sin que nadie se
/// entere.
class SesionCerradaException implements Exception {
  const SesionCerradaException(this.sesion);
  final SesionCaja sesion;
}

/// Guarda compartida (Regla 3: la validación de "sigue abierta" vive en un
/// solo lugar) para cualquier escritura que dependa de que [sesionCajaId]
/// siga siendo la sesión abierta — hoy la usan `registrarGastoRapido`/
/// `registrarIngresoRapido`, siempre envuelta junto con su insert en la
/// misma `db.transaction()` para que la verificación y la escritura no
/// puedan separarse por una carrera.
Future<void> verificarSesionAbierta(AppDatabase db, int sesionCajaId) async {
  final sesion = await (db.select(
    db.sesionesDeCaja,
  )..where((s) => s.id.equals(sesionCajaId))).getSingleOrNull();
  if (sesion == null) {
    throw ArgumentError('No existe la sesión de caja $sesionCajaId');
  }
  if (sesion.estado != 'ABIERTA') throw SesionCerradaException(sesion);
}

/// La última sesión cerrada, sin importar el día — de ahí sale la lata que
/// se arrastra a la próxima apertura (`abrirSesion`) y lo que se puede
/// mostrar de antemano sin abrir todavía (`lataQueSeArrastraCentavos`,
/// `mpQueSeArrastraCentavos`). Distinta de `sesionCerradaAnterior`
/// (`repositorio_cierre.dart`), que busca "anterior a una sesión que ya
/// existe" — acá todavía no hay ninguna sesión abierta.
Future<SesionCaja?> ultimaSesionCerrada(AppDatabase db) {
  return (db.select(db.sesionesDeCaja)
        ..where((s) => s.estado.equals('CERRADA'))
        ..orderBy([(s) => OrderingTerm.desc(s.fechaCierre)])
        ..limit(1))
      .getSingleOrNull();
}

/// Lo que va a quedar como `lataInicialCentavos` si se abre una sesión
/// ahora — por default se arrastra sola, sin pantalla (Regla 10: el
/// recuento es al cerrar, no al abrir), pero mostrarlo de antemano evita la
/// sensación de "¿y la caja de cigarrillos?" al abrir (El dueño, 2026-09-10,
/// apertura desde el celular). Sigue existiendo con este mismo contrato
/// (`int`, nunca null) porque la companion la usa solo para mostrar, no
/// para un campo editable — ver `lataInicialSugeridoCentavos` para eso.
Future<int> lataQueSeArrastraCentavos(AppDatabase db) async {
  final ultimaCerrada = await ultimaSesionCerrada(db);
  return ultimaCerrada == null ? 0 : lataQueQuedo(ultimaCerrada);
}

/// Lo que quedó en la lata al cerrar [sesion]: lo CONTADO, no lo esperado
/// (REGLAS-NEGOCIO.md §10: la apertura "se precarga con lo último
/// contado", igual que Mercado Pago con `mpContadoCentavos`). Bug real
/// encontrado revisando la base el 2026-09-28: se arrastraba
/// `lataFinalCentavos` (lo esperado), así que una diferencia de lata del
/// cierre reaparecía al día siguiente como si nadie la hubiera contado (el
/// 24/09 se esperaban $115.000, se contaron $125.000 y el 25 abrió con
/// $115.000). Lo esperado queda solo si ese cierre no tiene lata contada
/// (cierres viejos, de antes de que se contara la lata).
int lataQueQuedo(SesionCaja sesion) => sesion.lataContadoCentavos ?? sesion.lataFinalCentavos ?? 0;

/// Sugerencia para el campo editable "Caja cigarrillos" del escritorio
/// (2026-09-12, el dueño: reboot de la base — la caja normal, la lata y MP se
/// piden las tres al abrir). Null solo si nunca hubo un cierre anterior
/// (nada que sugerir todavía) — un cierre anterior que de verdad dejó la
/// lata en 0 SÍ se sugiere, mismo criterio que `fondoInicialSugeridoCentavos`
/// para el efectivo. Distinta de `lataQueSeArrastraCentavos` (que sigue
/// existiendo tal cual, para la companion y el aviso de solo lectura).
Future<int?> lataInicialSugeridoCentavos(AppDatabase db) async {
  final ultimaCerrada = await ultimaSesionCerrada(db);
  return ultimaCerrada == null ? null : lataQueQuedo(ultimaCerrada);
}

/// Sugerencia para "Monto Mercado Pago" al abrir — a diferencia de la lata
/// por default, esta sí se pregunta y se puede corregir (2026-09-12, el dueño:
/// reboot de la base), mismo criterio que `fondoInicialSugeridoCentavos`
/// para el efectivo: se sugiere lo que el dueño contó de verdad en el cierre
/// anterior (`mpContadoCentavos`, no el esperado), sin importar el día — la
/// cuenta de Mercado Pago no se "cierra" a la noche como el cajón físico.
/// Null solo si nunca hubo un cierre anterior — un MP contado en 0 de
/// verdad SÍ se sugiere (no es indistinguible de "nada que sugerir").
Future<int?> mpQueSeArrastraCentavos(AppDatabase db) async {
  final ultimaCerrada = await ultimaSesionCerrada(db);
  return ultimaCerrada?.mpContadoCentavos;
}

/// Apertura del día (fase 3, ampliada 2026-09-12): usuario, fondo inicial,
/// monto Mercado Pago y —opcional— una corrección de la lata. El arqueo, la
/// separación de cigarrillos y el cierre en sí son de la fase 4 — acá solo
/// se abre la sesión para que la pantalla de venta tenga dónde grabar.
///
/// [lataInicialCentavos] en `null` (default: todos los llamadores que no
/// pasan nada, ej. la apertura desde la companion) preserva el
/// comportamiento de siempre — se arrastra sola del cierre anterior, sin
/// preguntar (Regla 10). El escritorio sí puede pasar un valor explícito
/// (2026-09-12, reboot de la base: sin cierre anterior del que arrastrar,
/// hace falta poder tipearla a mano) — mismo criterio que
/// [mpInicialCentavos], que también viene con default (0) para no romper
/// llamadores que no lo necesitan.
/// Se tira cuando ya hay una sesión `ABIERTA` — bloqueo directo (El dueño,
/// 2026-09-19: "aislar los usuarios para que no se pisen"), ya no la unión
/// silenciosa que había antes. Quien la atrapa resuelve "quién y desde
/// cuándo" con [sesion] (`usuarioAbrioId`/`fechaApertura`) para avisar en
/// vez de reabrir con otros montos.
class SesionYaAbiertaException implements Exception {
  const SesionYaAbiertaException(this.sesion);
  final SesionCaja sesion;
}

Future<int> abrirSesion(
  AppDatabase db, {
  required int usuarioId,
  required int fondoInicialCentavos,
  int? mpInicialCentavos,
  int? lataInicialCentavos,
}) {
  // `db.transaction()` (mismo mecanismo que `registrarVenta`) serializa este
  // bloque contra cualquier otra escritura sobre `db` — cierra de verdad la
  // ventana de carrera que antes solo mitigaba el merge silencioso: dos
  // llamadas casi simultáneas (escritorio + companion vía HTTP contra la
  // MISMA base) ya no pueden pasar las dos el `if` de abajo.
  return db.transaction(() async {
    final yaAbierta = await sesionAbierta(db);
    if (yaAbierta != null) throw SesionYaAbiertaException(yaAbierta);

    final ultimaCerrada = await ultimaSesionCerrada(db);
    final mpInicial = mpInicialCentavos ?? ultimaCerrada?.mpContadoCentavos ?? 0;
    final lataInicial = lataInicialCentavos ?? (ultimaCerrada == null ? 0 : lataQueQuedo(ultimaCerrada));

    return db
        .into(db.sesionesDeCaja)
        .insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: fondoInicialCentavos,
            lataInicialCentavos: Value(lataInicial),
            // Sin valor explícito (apertura desde el celular) se arrastra lo último CONTADO
            // de MP, igual que la lata: con 0 el esperado de MP arrancaba sin el saldo real
            // y los pagos por MP lo dejaban en negativo.
            saldoMpInicialCentavos: Value(mpInicial),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
          ),
        );
  });
}

// ─── Producto → LineaVenta ───────────────────────────────────────────────

/// Construye la línea de dominio que corresponde a [producto].
///
/// [montoVariosCentavos] es obligatorio (y el único precio que se usa)
/// cuando `producto.esVarios`: el catálogo no tiene un precio para Varios
/// (Regla 5), el monto se carga a mano en el momento de la venta.
LineaVenta lineaDesdeProducto(
  Producto producto, {
  int? cantidad,
  int? gramos,
  int? montoVariosCentavos,
}) {
  final proveedorId = producto.proveedorId?.toString();

  if (producto.esPesable) {
    return LineaVentaPesable(
      productoId: producto.id.toString(),
      nombreProducto: producto.nombre,
      proveedorId: proveedorId,
      gramos: gramos!,
      precioPorKiloCentavos: producto.precioPorKiloCentavos!,
      costoPorKiloCentavos: producto.costoPorKiloCentavos,
    );
  }

  return LineaVentaPorUnidad(
    productoId: producto.id.toString(),
    nombreProducto: producto.nombre,
    proveedorId: proveedorId,
    cantidad: cantidad ?? 1,
    esVarios: producto.esVarios,
    tipoCigarrillo: tipoCigarrilloDesde(producto.tipoCigarrillo),
    precioUnitarioCentavos: producto.esVarios
        ? montoVariosCentavos!
        : producto.precioCentavos!,
    costoUnitarioCentavos: producto.costoCentavos,
  );
}

// ─── Persistir una venta ─────────────────────────────────────────────────

class PagoARegistrar {
  final int medioPagoId;
  final int montoCentavos;

  /// Determina si este pago genera un movimiento de caja normal (Regla 10:
  /// "caja esperada" solo cuenta efectivo). Un pago virtual queda registrado
  /// en `pagos`, pero no mueve la caja física.
  final bool esEfectivo;

  /// 'qr' | 'debit_card' | null (Fase 12). Null para efectivo y para
  /// Mercado Pago cobrado a mano — sigue siendo el mismo `medioPagoId` de
  /// siempre, esto es solo el dato de qué canal de la terminal Point se usó.
  final String? canal;

  const PagoARegistrar({
    required this.medioPagoId,
    required this.montoCentavos,
    required this.esEfectivo,
    this.canal,
  });
}

/// Nuevo stock de un producto tras descontar una línea de venta, para que
/// quien llamó a `registrarVenta` pueda corregir su catálogo en memoria sin
/// releerlo de la base (CLAUDE.md, "prioridad arranque vs. operación": nunca
/// una consulta a disco durante la venta). Los valores no tocados por esta
/// línea quedan `null` — nunca los dos a la vez, un producto es pesable o
/// por unidad, no las dos cosas.
class ActualizacionStock {
  const ActualizacionStock({
    required this.productoId,
    this.stock,
    this.stockGramos,
  });

  final int productoId;
  final int? stock;
  final int? stockGramos;
}

/// Graba una venta ya calculada por el dominio: la venta, sus líneas, sus
/// pagos, el descuento de stock de cada línea (Regla 8: todo movimiento deja
/// rastro) y el movimiento de caja de la porción efectivo. Todo en una sola
/// transacción: una venta a medio grabar sería peor que ninguna venta.
///
/// [fecha] null graba con "ahora" (comportamiento normal de una venta en
/// vivo, `currentDateAndTime` de la tabla). La carga histórica
/// (`repositorio_carga_historica.dart`) pasa la fecha elegida.
///
/// [afectaStock] en `false` (carga histórica): la mercadería de una venta
/// vieja ya se descontó en su momento, aunque no estuviera en el sistema
/// todavía — tocar el stock de hoy con una venta de hace un mes lo
/// descuadraría. Ver `registrarLineaDeVenta`.
Future<(int ventaId, List<ActualizacionStock> stockActualizado)> registrarVenta(
  AppDatabase db, {
  required Venta venta,
  required ResultadoTotalVenta resultado,
  required int sesionCajaId,
  required int usuarioId,
  required List<PagoARegistrar> pagos,
  bool esFiado = false,
  DateTime? fecha,
  bool afectaStock = true,
  // El borrador (`ventas_abiertas`) del que sale esta venta: se borra en la
  // MISMA transacción, así una caída entre cobrar y limpiar no deja la venta
  // cobrada y también armada, lista para cobrarse dos veces.
  int? ventaAbiertaId,
  // El encargue por apartado que esta venta entrega (`repositorio_encargues.dart`): se libera en la MISMA transacción,
  // porque la venta descuenta el stock y lo apartado ya estaba descontado.
  int? encargueId,
  // Cargar un día histórico escribe ventas en una sesión que nace cerrada (`repositorio_carga_historica.dart`): es la única
  // excepción a "no se cobra contra una caja cerrada". Todo lo demás (PC, celular, posnet) tiene que dejarla en `true`.
  bool exigirSesionAbierta = true,
}) {
  return db.transaction(() async {
    // Un pago negativo no es plata que entró: restaría del esperado de su caja (revisión 2026-10-03: un mixto cuyo
    // total bajó después de cargar el efectivo grababa Mercado Pago en negativo).
    if (pagos.any((p) => p.montoCentavos < 0)) {
      throw ArgumentError('Un pago no puede ser negativo');
    }
    // Dentro de la transacción, igual que gastos e ingresos: si el cierre llega justo antes, la venta se rechaza en vez de
    // grabarse contra una sesión cerrada (cambiaría los totales de un cierre ya hecho).
    if (exigirSesionAbierta) await verificarSesionAbierta(db, sesionCajaId);
    if (ventaAbiertaId != null) {
      await (db.delete(db.ventasAbiertas)..where((v) => v.id.equals(ventaAbiertaId))).go();
    }
    final ventaId = await db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            sesionCajaId: sesionCajaId,
            usuarioId: usuarioId,
            fecha: fecha == null ? const Value.absent() : Value(fecha),
            subtotalCentavos: resultado.subtotalCentavos,
            recargoCigarrillosCentavos: Value(
              resultado.recargoCigarrillosCentavos,
            ),
            descuentoCentavos: Value(resultado.descuentoCentavos),
            redondeoCentavos: Value(resultado.redondeoCentavos),
            totalCentavos: resultado.totalCentavos,
            esFiado: Value(esFiado),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
            actualizadoEn: Value(DateTime.now()),
            numero: Value(await siguienteNumeroDeVenta(db)),
          ),
        );

    // Antes de las líneas: así el stock que cada línea lee y devuelve (`stockActualizado`, que la pantalla de venta
    // aplica en memoria) ya es el final, sin pasar por un valor intermedio.
    if (encargueId != null) {
      await liberarEncargueEntregado(db, encargueId, ventaId: ventaId, usuarioId: usuarioId);
    }

    final stockActualizado = <ActualizacionStock>[];
    for (final linea in venta.lineas) {
      stockActualizado.addAll(
        await registrarLineaOPromo(
          db,
          ventaId: ventaId,
          usuarioId: usuarioId,
          linea: linea,
          afectaStock: afectaStock,
        ),
      );
    }

    Caja? cajaNormal;
    for (final pago in pagos) {
      await db
          .into(db.pagos)
          .insert(
            PagosCompanion.insert(
              ventaId: ventaId,
              medioPagoId: pago.medioPagoId,
              montoCentavos: pago.montoCentavos,
              canal: Value(pago.canal),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
              actualizadoEn: Value(DateTime.now()),
            ),
          );

      if (pago.esEfectivo) {
        cajaNormal ??= await (db.select(
          db.cajas,
        )..where((c) => c.esLata.equals(false))).getSingle();
        await db
            .into(db.movimientosDeCaja)
            .insert(
              MovimientosDeCajaCompanion.insert(
                sesionCajaId: sesionCajaId,
                cajaId: cajaNormal.id,
                usuarioId: usuarioId,
                tipo: 'VENTA',
                montoCentavos: pago.montoCentavos,
                ventaId: Value(ventaId),
                medioPagoId: Value(pago.medioPagoId),
                fecha: fecha == null ? const Value.absent() : Value(fecha),
                globalId: Value(generarGlobalId()),
                origenDispositivo: Value(idDispositivoActual),
              ),
            );
      }
    }

    return (ventaId, stockActualizado);
  });
}

/// Registra una línea del carrito. Si es una PROMO (El dueño, 2026-09-29: "la
/// promo aparece como un producto más pero debe descontar el stock"), la abre
/// en sus artículos ([registrarPromoEnVenta]); si no, es una línea normal
/// ([registrarLineaDeVenta]). Un solo punto de entrada para `registrarVenta` y
/// para la edición de una venta (Regla 3).
Future<List<ActualizacionStock>> registrarLineaOPromo(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
  required LineaVenta linea,
  bool afectaStock = true,
}) async {
  if (linea is LineaVentaPorUnidad && !linea.esVarios) {
    final id = int.tryParse(linea.productoId);
    final producto = id == null ? null : await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (producto != null && producto.esPromo) {
      return registrarPromoEnVenta(
        db,
        ventaId: ventaId,
        usuarioId: usuarioId,
        promo: producto,
        linea: linea,
        afectaStock: afectaStock,
      );
    }
  }
  final actualizacion = await registrarLineaDeVenta(
    db,
    ventaId: ventaId,
    usuarioId: usuarioId,
    linea: linea,
    afectaStock: afectaStock,
  );
  return [?actualizacion];
}

/// Una promo cobrada: en `lineas_de_venta` NO queda una línea "promo" sino
/// una por artículo, cada una con SU costo-foto y SU proveedor (Regla 4), así
/// la reposición por proveedor, la ganancia y el stock siguen siendo los de
/// siempre. El precio de la promo se reparte entre los artículos en
/// proporción a su precio de lista (`repartirEnProporcion`): la suma de las
/// líneas da exactamente lo cobrado. El nombre de cada línea lleva el de la
/// promo ("Yerba · Promo merienda") para que en el historial se entienda de
/// dónde salió.
Future<List<ActualizacionStock>> registrarPromoEnVenta(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
  required Producto promo,
  required LineaVentaPorUnidad linea,
  bool afectaStock = true,
}) async {
  final componentes = await (db.select(db.promoComponentes)..where((c) => c.promoId.equals(promo.id))).get();
  if (componentes.isEmpty) {
    throw StateError('La promo "${promo.nombre}" no tiene artículos');
  }
  final articulos = <Producto>[
    for (final c in componentes) await (db.select(db.productos)..where((p) => p.id.equals(c.productoId))).getSingle(),
  ];

  final totalPromo = linea.precioUnitarioCentavos * linea.cantidad;
  final pesos = [
    for (var i = 0; i < articulos.length; i++) (articulos[i].precioCentavos ?? 0) * componentes[i].cantidad * linea.cantidad,
  ];
  final partes = repartirEnProporcion(totalPromo, pesos);

  final stockActualizado = <ActualizacionStock>[];
  for (var i = 0; i < articulos.length; i++) {
    final articulo = articulos[i];
    final unidades = componentes[i].cantidad * linea.cantidad;
    for (final tanda in dividirEnUnidades(partes[i], unidades)) {
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              productoId: Value(articulo.id),
              nombreProductoFoto: '${articulo.nombre} · ${promo.nombre}',
              proveedorIdFoto: Value(articulo.proveedorId),
              tipoCigarrillo: const Value('ninguno'),
              cantidad: Value(tanda.cantidad),
              precioUnitarioCentavos: tanda.precioUnitarioCentavos,
              costoUnitarioCentavos: Value(articulo.costoCentavos),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
              actualizadoEn: Value(DateTime.now()),
            ),
          );
    }
    if (!afectaStock) continue;
    final anterior = articulo.stock;
    final posterior = anterior - unidades;
    await (db.update(db.productos)..where((p) => p.id.equals(articulo.id))).write(ProductosCompanion(stock: Value(posterior)));
    await db.into(db.movimientosDeStock).insert(
          MovimientosDeStockCompanion.insert(
            productoId: articulo.id,
            usuarioId: usuarioId,
            tipo: 'VENTA',
            ventaId: Value(ventaId),
            cantidad: Value(unidades),
            stockAnterior: Value(anterior),
            stockPosterior: Value(posterior),
            motivo: Value('Promo ${promo.nombre}'),
            globalId: Value(generarGlobalId()),
            origenDispositivo: Value(idDispositivoActual),
          ),
        );
    stockActualizado.add(ActualizacionStock(productoId: articulo.id, stock: posterior));
  }
  return stockActualizado;
}

/// Devuelve `null` cuando la línea es "Varios" (no descuenta stock, nada que
/// reportar) o cuando [afectaStock] es `false`; en cualquier otro caso, el
/// stock posterior de ese producto.
Future<ActualizacionStock?> registrarLineaDeVenta(
  AppDatabase db, {
  required int ventaId,
  required int usuarioId,
  required LineaVenta linea,
  bool afectaStock = true,
}) async {
  final productoId = int.parse(linea.productoId);
  final esPesable = linea is LineaVentaPesable;

  await db
      .into(db.lineasDeVenta)
      .insert(
        LineasDeVentaCompanion.insert(
          ventaId: ventaId,
          productoId: Value(productoId),
          nombreProductoFoto: linea.nombreProducto,
          proveedorIdFoto: Value(
            linea.proveedorId == null ? null : int.parse(linea.proveedorId!),
          ),
          esVarios: Value(linea.esVarios),
          tipoCigarrillo: Value(linea.tipoCigarrillo.name),
          esPesable: Value(esPesable),
          cantidad: Value(linea is LineaVentaPorUnidad ? linea.cantidad : null),
          gramos: Value(linea is LineaVentaPesable ? linea.gramos : null),
          precioUnitarioCentavos: switch (linea) {
            LineaVentaPorUnidad u => u.precioUnitarioCentavos,
            LineaVentaPesable p => p.precioPorKiloCentavos,
          },
          costoUnitarioCentavos: Value(switch (linea) {
            LineaVentaPorUnidad u => u.costoUnitarioCentavos,
            LineaVentaPesable p => p.costoPorKiloCentavos,
          }),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );

  // "Varios" no descuenta stock (Regla 5): no hay nada del catálogo real
  // que ajustar. Una línea de carga histórica (`afectaStock: false`) tampoco
  // toca stock: ver el comentario de `registrarVenta`.
  if (linea.esVarios || !afectaStock) return null;

  final producto = await (db.select(
    db.productos,
  )..where((p) => p.id.equals(productoId))).getSingle();

  switch (linea) {
    case LineaVentaPesable(:final gramos):
      final anterior = producto.stockGramos ?? 0;
      final posterior = stockGramosPosterior(
        stockGramosAnterior: anterior,
        gramosVendidos: gramos,
      );

      await (db.update(db.productos)..where((p) => p.id.equals(productoId)))
          .write(ProductosCompanion(stockGramos: Value(posterior)));

      await db
          .into(db.movimientosDeStock)
          .insert(
            MovimientosDeStockCompanion.insert(
              productoId: productoId,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              ventaId: Value(ventaId),
              gramos: Value(gramos),
              gramosAnterior: Value(anterior),
              gramosPosterior: Value(posterior),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );

      return ActualizacionStock(productoId: productoId, stockGramos: posterior);

    case LineaVentaPorUnidad(:final cantidad):
      final anterior = producto.stock;
      // Resta simple: a diferencia del subtotal de pesables, acá no hay una
      // multiplicación que se pueda mezclar con otra unidad — no hace falta
      // un helper de dominio para esto.
      final posterior = anterior - cantidad;

      await (db.update(db.productos)..where((p) => p.id.equals(productoId)))
          .write(ProductosCompanion(stock: Value(posterior)));

      await db
          .into(db.movimientosDeStock)
          .insert(
            MovimientosDeStockCompanion.insert(
              productoId: productoId,
              usuarioId: usuarioId,
              tipo: 'VENTA',
              ventaId: Value(ventaId),
              cantidad: Value(cantidad),
              stockAnterior: Value(anterior),
              stockPosterior: Value(posterior),
              globalId: Value(generarGlobalId()),
              origenDispositivo: Value(idDispositivoActual),
            ),
          );

      return ActualizacionStock(productoId: productoId, stock: posterior);
  }
}

// ─── Más vendidos ─────────────────────────────────────────────────────────

/// Ids de producto más vendidos de toda la historia (El dueño, rediseño
/// 2026-09-25: "en base al historial... los 10 productos mas vendidos por
/// default" — la grilla de venta arranca con esto en vez de todo el
/// catálogo). Se cuenta por CANTIDAD DE LÍNEAS DE VENTA, no por unidades:
/// mezclar unidades de un producto por unidad con gramos de un pesable no
/// es un número comparable, así que "cuántas veces se vendió" es la
/// métrica que sí tiene sentido para las dos formas de línea a la vez.
/// Excluye líneas de ventas anuladas (Regla 6: una venta anulada no fue
/// una venta real) y líneas sin producto ("Varios" no tiene identidad de
/// producto para rankear).
Future<List<int>> productosMasVendidosIds(AppDatabase db, {int limite = 10}) {
  final conteo = db.lineasDeVenta.productoId.count();
  final query = db.selectOnly(db.lineasDeVenta)
    ..join([
      innerJoin(db.ventas, db.ventas.id.equalsExp(db.lineasDeVenta.ventaId)),
    ])
    ..addColumns([db.lineasDeVenta.productoId, conteo])
    ..where(
      db.lineasDeVenta.productoId.isNotNull() & db.ventas.anuladaPorId.isNull(),
    )
    ..groupBy([db.lineasDeVenta.productoId])
    ..orderBy([OrderingTerm.desc(conteo)])
    ..limit(limite);
  return query.get().then(
    (filas) => [for (final fila in filas) ?fila.read(db.lineasDeVenta.productoId)],
  );
}

// ─── Vender desde la companion (Regla 3: un solo lugar) ──────────────────
//
// Estas tres funciones son el "pegamento" que arma un carrito + medio en un
// `ResultadoTotalVenta`/lista de pagos/venta grabada — antes vivían
// duplicadas como funciones privadas de `lib/servidor/servidor_companion.dart`
// (`_calcularResultado`/`_pagosDesdeMedio`/`_registrarVentaDesdeBody`).
// Extraídas acá para que tanto el servidor HTTP (celular con la PC prendida)
// como `lib/companion/puerto_local.dart` (celular vendiendo con su propia
// base, sin la PC) llamen a la misma lógica en vez de mantenerla dos veces.

/// Trae la configuración una sola vez si el llamador ya la tiene a mano
/// (ej. cargar un día histórico entero, muchas ventas con la misma config) —
/// sin ese parámetro, se resuelve acá mismo como siempre.
Future<ResultadoTotalVenta> calcularResultadoVenta(
  AppDatabase db, {
  required List<LineaVenta> lineas,
  required ComposicionPago medio,
  ConfiguracionNegocio? configuracionNegocio,
  TipoDescuento? tipoDescuento,
  int valorDescuento = 0,
}) async {
  final config = configuracionNegocio ?? await configuracionNegocioActual(db);
  return calcularTotalVenta(
    venta: Venta(lineas: lineas),
    composicionPago: medio,
    configRecargoCigarrillos: ConfigRecargoCigarrillos(
      primerAtadoCentavos: config.recargoPrimerAtadoCentavos,
      atadoAdicionalCentavos: config.recargoAtadoAdicionalCentavos,
      cigarroSueltoCentavos: config.recargoSueltoCentavos,
    ),
    pasoRedondeoCentavos: config.pasoRedondeoCentavos,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
  );
}

/// Arma la lista de [PagoARegistrar] según cómo se cobró la venta.
/// [montoEfectivoMixtoCentavos] solo hace falta con `medio == mixto` (hoy
/// solo lo usa la carga histórica) — mismo reparto que
/// `VentaControlador.construirPagos` del escritorio.
///
/// [medioEfectivoResuelto]/[medioVirtualResuelto] evitan releer
/// `medios_de_pago` por cada venta cuando el llamador ya los tiene (cargar
/// muchas ventas de un día histórico de una sola vez).
Future<List<PagoARegistrar>> pagosSegunMedio(
  AppDatabase db, {
  required ComposicionPago medio,
  required int totalCentavos,
  String? canal,
  int? montoEfectivoMixtoCentavos,
  MedioDePago? medioEfectivoResuelto,
  MedioDePago? medioVirtualResuelto,
}) async {
  final medioEfectivo =
      medioEfectivoResuelto ??
      await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(true))).getSingle();
  if (medio == ComposicionPago.efectivo) {
    return [
      PagoARegistrar(
        medioPagoId: medioEfectivo.id,
        montoCentavos: totalCentavos,
        esEfectivo: true,
      ),
    ];
  }
  final medioVirtual =
      medioVirtualResuelto ??
      await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(false))).getSingle();
  if (medio == ComposicionPago.mixto) {
    final montoEfectivo = montoEfectivoMixtoCentavos!;
    return [
      PagoARegistrar(
        medioPagoId: medioEfectivo.id,
        montoCentavos: montoEfectivo,
        esEfectivo: true,
      ),
      PagoARegistrar(
        medioPagoId: medioVirtual.id,
        montoCentavos: totalCentavos - montoEfectivo,
        esEfectivo: false,
        canal: canal,
      ),
    ];
  }
  return [
    PagoARegistrar(
      medioPagoId: medioVirtual.id,
      montoCentavos: totalCentavos,
      esEfectivo: false,
      canal: canal,
    ),
  ];
}

/// Calcula, arma los pagos y graba — el mismo camino tanto para "cobrar
/// efectivo directo" como para "el posnet ya aprobó".
Future<({int ventaId, int totalCentavos})> registrarVentaSegunMedio(
  AppDatabase db, {
  required List<LineaVenta> lineas,
  required ComposicionPago medio,
  String? canal,
  required int sesionCajaId,
  required int usuarioId,
  TipoDescuento? tipoDescuento,
  int valorDescuento = 0,
  int? encargueId,
}) async {
  final resultado = await calcularResultadoVenta(
    db,
    lineas: lineas,
    medio: medio,
    tipoDescuento: tipoDescuento,
    valorDescuento: valorDescuento,
  );
  final pagos = await pagosSegunMedio(
    db,
    medio: medio,
    totalCentavos: resultado.totalCentavos,
    canal: canal,
  );
  final (ventaId, _) = await registrarVenta(
    db,
    venta: Venta(lineas: lineas),
    resultado: resultado,
    sesionCajaId: sesionCajaId,
    usuarioId: usuarioId,
    pagos: pagos,
    encargueId: encargueId,
  );
  return (ventaId: ventaId, totalCentavos: resultado.totalCentavos);
}
