// Cobrar servicios (`docs/PLAN-SERVICIOS.md`, etapa 3; Regla 20) contra una base de verdad: la línea del servicio, lo que
// gasta de cada insumo, "Bloquear si falta un insumo", ajustar lo usado, anular y editar, y la reposición repartida por el
// proveedor de cada insumo.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_edicion_venta.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late int usuario;
  late int sesion;
  late int provEsmaltes;
  late int provDescartables;
  late int top;
  late int guantes;
  late int kapping;

  setUp(() async {
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    await configurarRubro(db, PlantillaRubro.unas);
    final proveedores = await db.select(db.proveedores).get();
    provEsmaltes = proveedores[0].id;
    provDescartables = proveedores[1].id;
    top = await crearInsumo(
      db,
      nombre: 'Top coat',
      unidad: UnidadInsumo.ml,
      contenidoEnvaseMilesimas: 15000,
      costoEnvaseCentavos: 1100000, // $ 11.000 los 15 ml
      stockMilesimas: 1000, // 1 ml: alcanza para 2 de 0,4
      proveedorId: provEsmaltes,
      usuarioId: usuario,
    );
    guantes = await crearInsumo(
      db,
      nombre: 'Guantes',
      unidad: UnidadInsumo.u,
      contenidoEnvaseMilesimas: 100000,
      costoEnvaseCentavos: 1400000, // $ 14.000 la caja de 100
      stockMilesimas: 96000,
      proveedorId: provDescartables,
      usuarioId: usuario,
    );
    kapping = await guardarServicio(
      db,
      nombre: 'Kapping',
      precioCentavos: 2000000,
      duracionMinutos: 60,
      receta: [(insumoId: top, milesimas: 400), (insumoId: guantes, milesimas: 2000)],
      usuarioId: usuario,
    );
    sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  LineaVentaPorUnidad linea(int servicioId, {int cantidad = 1, Map<int, int>? ajustes, int precio = 2000000}) => LineaVentaPorUnidad(
        productoId: '$servicioId',
        nombreProducto: 'Kapping',
        proveedorId: null,
        cantidad: cantidad,
        precioUnitarioCentavos: precio,
        insumosAjustados: ajustes,
      );

  Future<int> cobrar(List<LineaVenta> lineas, {ComposicionPago medio = ComposicionPago.efectivo}) async =>
      (await registrarVentaSegunMedio(db, lineas: lineas, medio: medio, sesionCajaId: sesion, usuarioId: usuario)).ventaId;

  Future<int> stock(int id) async => (await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()).stockMilesimas ?? 0;

  test('cobrar un servicio deja UNA línea con su nombre, gasta los insumos y guarda qué usó, a qué costo y de quién', () async {
    final ventaId = await cobrar([linea(kapping)]);

    final lineas = await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get();
    expect(lineas, hasLength(1));
    expect(lineas.single.nombreProductoFoto, 'Kapping');
    expect(lineas.single.esServicio, isTrue);
    // 11.000 × 0,4 / 15 = 293,33 + 14.000 × 2 / 100 = 280 → $ 574 (el mismo número del calculador).
    expect(lineas.single.costoUnitarioCentavos, 57400);

    final consumos = await (db.select(db.consumosDeLinea)..where((c) => c.lineaVentaId.equals(lineas.single.id))).get();
    expect(consumos.map((c) => (c.insumoId, c.milesimas, c.proveedorIdFoto)), [(top, 400, provEsmaltes), (guantes, 2000, provDescartables)]);
    expect(consumos.fold<int>(0, (a, c) => a + c.costoCentavos), 57400);
    expect(consumos.every((c) => c.globalId != null), isTrue, reason: 'viajan por la sync');

    expect(await stock(top), 600);
    expect(await stock(guantes), 94000);
    final movimientos = await (db.select(db.movimientosDeStock)..where((m) => m.ventaId.equals(ventaId))).get();
    expect(movimientos.map((m) => (m.productoId, m.milesimasAnterior, m.milesimasPosterior)), [(top, 1000, 600), (guantes, 96000, 94000)]);
    expect((await (db.select(db.productos)..where((p) => p.id.equals(kapping))).getSingle()).stock, 0, reason: 'el servicio no tiene stock propio');
  });

  test('con "Bloquear si falta un insumo" no se cobra si el carrito entero no alcanza, y no queda nada grabado', () async {
    // Dos kappings en dos líneas piden 0,8 ml: alcanza. Tres, 1,2 ml: no.
    await expectLater(cobrar([linea(kapping, cantidad: 2), linea(kapping)]), throwsA(isA<InsumoFaltante>()));
    expect(await db.select(db.ventas).get(), isEmpty);
    expect(await stock(top), 1000);

    try {
      await cobrar([linea(kapping, cantidad: 3)]);
      fail('tenía que faltar top coat');
    } on InsumoFaltante catch (e) {
      expect(e.insumo.id, top);
      expect(e.faltanMilesimas, 200);
      expect(e.message, contains('Falta top coat'));
    }
    await cobrar([linea(kapping, cantidad: 2)]);
    expect(await stock(top), 200);
  });

  test('con el módulo apagado solo avisa: se cobra igual y el stock queda negativo', () async {
    await configurarModulo(db, Modulo.bloquearInsumos, activo: false);
    await cobrar([linea(kapping, cantidad: 3)]);
    expect(await stock(top), -200);
  });

  test('sin el módulo de insumos el servicio se cobra sin tocar insumos y sin costo', () async {
    await configurarModulo(db, Modulo.insumos, activo: false);
    final ventaId = await cobrar([linea(kapping, cantidad: 5)]);
    final l = (await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get()).single;
    expect(l.costoUnitarioCentavos, 0);
    expect(await db.select(db.consumosDeLinea).get(), isEmpty);
    expect(await stock(top), 1000);
  });

  test('ajustar lo usado cambia solo esa venta: lo que se descuenta y su costo', () async {
    final ventaId = await cobrar([linea(kapping, ajustes: {top: 600, guantes: 2000})]);
    expect(await stock(top), 400);
    final l = (await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get()).single;
    expect(l.costoUnitarioCentavos, costoInsumosCentavos([
      const UsoDeInsumo(insumo: InsumoParaCalculo(costoEnvaseCentavos: 1100000, contenidoEnvaseMilesimas: 15000, stockMilesimas: 0), cantidadMilesimas: 600),
      const UsoDeInsumo(insumo: InsumoParaCalculo(costoEnvaseCentavos: 1400000, contenidoEnvaseMilesimas: 100000, stockMilesimas: 0), cantidadMilesimas: 2000),
    ]));
    expect(recetaGuardada((await (db.select(db.productos)..where((p) => p.id.equals(kapping))).getSingle())).first.milesimas, 400,
        reason: 'la receta no cambia');

    // Con el módulo apagado, el ajuste no vale: se usa la receta.
    await configurarModulo(db, Modulo.ajustarInsumos, activo: false);
    await cobrar([linea(kapping, ajustes: {top: 100})]);
    expect(await stock(top), 0);
  });

  test('un servicio sin receta (un corte) se cobra siempre, cuesta 0 y no es "sin costo"', () async {
    final corte = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, receta: const [], usuarioId: usuario);
    final ventaId = await cobrar([linea(corte, precio: 1000000)]);
    final l = (await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.equals(ventaId))).get()).single;
    expect(l.costoUnitarioCentavos, 0);
    final repo = await reposicionDelDia(db, sesion);
    expect(repo.costoRealPorProveedorCentavos.values.fold<int>(0, (a, b) => a + b), 0);
    expect(await vendidoSinCostoDesde(db, DateTime(2000)), isEmpty);
  });

  test('anular la venta devuelve los insumos', () async {
    final ventaId = await cobrar([linea(kapping, cantidad: 2)]);
    await anularVenta(db, ventaId: ventaId, usuarioId: usuario, motivo: 'se equivocó');
    expect(await stock(top), 1000);
    expect(await stock(guantes), 96000);
  });

  test('editar la venta devuelve lo viejo, gasta lo nuevo y reemplaza los consumos', () async {
    final ventaId = await cobrar([linea(kapping, cantidad: 2)]);
    final nueva = Venta(lineas: [linea(kapping)]);
    final resultado = await calcularResultadoVenta(db, lineas: nueva.lineas, medio: ComposicionPago.efectivo);
    await editarVenta(
      db,
      ventaId: ventaId,
      ventaNueva: nueva,
      resultadoNuevo: resultado,
      pagosNuevos: await pagosSegunMedio(db, medio: ComposicionPago.efectivo, totalCentavos: resultado.totalCentavos),
      usuarioId: usuario,
      motivo: 'era uno',
    );
    expect(await stock(top), 600);
    expect(await stock(guantes), 94000);
    final consumos = await db.select(db.consumosDeLinea).get();
    expect(consumos.map((c) => c.milesimas), [400, 2000]);
  });

  test('la reposición y las Separaciones reparten el servicio por el proveedor de cada insumo y cierran con lo cobrado', () async {
    await cobrar([linea(kapping)]);

    final repo = await reposicionDelDia(db, sesion);
    final costoEsmaltes = repo.costoRealPorProveedorCentavos['$provEsmaltes']!;
    final costoDescartables = repo.costoRealPorProveedorCentavos['$provDescartables']!;
    expect(costoEsmaltes + costoDescartables, 57400);
    expect(costoEsmaltes, greaterThan(costoDescartables));
    expect(repo.vendidoPorProveedorCentavos['$provEsmaltes']! + repo.vendidoPorProveedorCentavos['$provDescartables']!, 2000000,
        reason: 'el precio se reparte entero entre los proveedores de los insumos');

    final separaciones = await separacionesDelDia(db);
    final porProveedor = {for (final s in separaciones) s.proveedor?.id: s};
    expect(porProveedor[provEsmaltes]!.costoCentavos, costoEsmaltes);
    expect(porProveedor[provDescartables]!.costoCentavos, costoDescartables);
    expect(porProveedor.containsKey(null), isFalse, reason: 'nada queda "sin proveedor"');
    expect(separaciones.fold<int>(0, (a, s) => a + s.vendidoCentavos), 2000000);
  });

  test('los consumos viajan con su línea al otro equipo', () async {
    final otro = baseDeTest();
    addTearDown(otro.close);
    await db.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial'");
    await otro.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial'");
    Future<void> sincronizar() async {
      for (final tabla in tablasSincronizables.keys) {
        final fallidas = await aplicarCambios(otro, tabla: tabla, filas: await cambiosDesde(db, tabla: tabla, desde: 0));
        expect(fallidas, isEmpty, reason: tabla);
      }
    }

    // Los insumos ya están en los dos equipos antes de cobrar (lo de siempre). Si llegaran recién con la venta, su stock se
    // descontaría dos veces: el bug de la primera sincronización anotado en ESTADO.md, que no es de los servicios.
    await sincronizar();
    await cobrar([linea(kapping)]);
    await sincronizar();
    final consumos = await otro.select(otro.consumosDeLinea).get();
    expect(consumos.map((c) => c.milesimas), [400, 2000]);
    final insumoTop = await (otro.select(otro.productos)..where((p) => p.nombre.equals('Top coat'))).getSingle();
    expect(consumos.first.insumoId, insumoTop.id);
    expect(insumoTop.stockMilesimas, 600);
  });

  test('un almacén no cambia: una venta de productos no deja consumos', () async {
    final yerba = await crearProducto(db, nombre: 'Yerba', precioCentavos: 300000, costoCentavos: 200000, stock: 5, usuarioId: usuario);
    await cobrar([
      LineaVentaPorUnidad(productoId: '$yerba', nombreProducto: 'Yerba', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 300000, costoUnitarioCentavos: 200000),
    ]);
    expect(await db.select(db.consumosDeLinea).get(), isEmpty);
    expect((await db.select(db.lineasDeVenta).get()).single.esServicio, isFalse);
  });
}
