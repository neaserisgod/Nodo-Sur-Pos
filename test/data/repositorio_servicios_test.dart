// Servicios e insumos contra una base de verdad (`docs/PLAN-SERVICIOS.md`, etapa 2): alta, compra por envases, conteo,
// servicio con receta y las cuentas de la lista. Las cuentas en sí se prueban en `test/domain/servicios_test.dart`; acá, que
// se guarden, dejen rastro y se lean bien.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/servicios.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuario;

  setUp(() async {
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    await configurarRubro(db, PlantillaRubro.unas);
  });
  tearDown(() => db.close());

  Future<int> topCoat({int stock = 0}) => crearInsumo(
        db,
        nombre: 'Top coat',
        unidad: UnidadInsumo.ml,
        contenidoEnvaseMilesimas: 15000,
        costoEnvaseCentavos: 1100000, // $ 11.000 el frasco de 15 ml
        stockMilesimas: stock,
        usuarioId: usuario,
      );

  Future<int> guantes() => crearInsumo(
        db,
        nombre: 'Guantes',
        unidad: UnidadInsumo.u,
        contenidoEnvaseMilesimas: 100000, // caja de 100
        costoEnvaseCentavos: 800000,
        stockMilesimas: 50000,
        usuarioId: usuario,
      );

  Future<List<MovimientoStock>> movimientosDe(int id) =>
      (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();

  group('insumos', () {
    test('el alta guarda envase, costo y stock, con identidad de sync y su historial de precio', () async {
      final id = await topCoat(stock: 7500);
      final i = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(i.esInsumo, isTrue);
      expect(i.esServicio, isFalse);
      expect(i.unidadInsumo, 'ml');
      expect(i.stockMilesimas, 7500);
      expect(i.costoCentavos, 1100000);
      expect(i.globalId, isNotNull);
      final historial = await (db.select(db.historialDePrecios)..where((h) => h.productoId.equals(id))).get();
      expect(historial.single.costoCentavos, 1100000);
    });

    test('un envase vacío, un costo negativo o un nombre en blanco no se guardan', () async {
      expect(
        () => crearInsumo(db, nombre: 'X', unidad: UnidadInsumo.g, contenidoEnvaseMilesimas: 0, costoEnvaseCentavos: 100, usuarioId: usuario),
        throwsArgumentError,
      );
      expect(
        () => crearInsumo(db, nombre: 'X', unidad: UnidadInsumo.g, contenidoEnvaseMilesimas: 10, costoEnvaseCentavos: -1, usuarioId: usuario),
        throwsArgumentError,
      );
      expect(
        () => crearInsumo(db, nombre: '  ', unidad: UnidadInsumo.g, contenidoEnvaseMilesimas: 10, costoEnvaseCentavos: 1, usuarioId: usuario),
        throwsArgumentError,
      );
    });

    test('cargar una compra suma los envases al stock, deja su movimiento en milésimas y el costo nuevo con historial', () async {
      final id = await topCoat(stock: 2000);
      await cargarCompraDeInsumo(db, insumoId: id, envases: 2, costoEnvaseCentavos: 1200000, usuarioId: usuario);

      final i = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
      expect(i.stockMilesimas, 32000);
      expect(i.costoCentavos, 1200000);
      final m = (await movimientosDe(id)).single;
      expect((m.milesimasAnterior, m.milesimasPosterior, m.milesimas), (2000, 32000, 30000));
      expect(m.stockAnterior, isNull, reason: 'un insumo no mueve el stock en unidades');
      expect(m.globalId, isNotNull);
      final historial = await (db.select(db.historialDePrecios)..where((h) => h.productoId.equals(id))).get();
      expect(historial.map((h) => h.costoCentavos), [1100000, 1200000]);
    });

    test('una compra sin costo nuevo deja el de antes y no suma historial', () async {
      final id = await topCoat();
      await cargarCompraDeInsumo(db, insumoId: id, envases: 1, usuarioId: usuario);
      final historial = await (db.select(db.historialDePrecios)..where((h) => h.productoId.equals(id))).get();
      expect(historial, hasLength(1));
    });

    test('contar deja el stock contado con su ajuste; contar lo mismo no deja nada', () async {
      final id = await topCoat(stock: 15000);
      await contarInsumo(db, insumoId: id, stockMilesimas: 11600, usuarioId: usuario);
      await contarInsumo(db, insumoId: id, stockMilesimas: 11600, usuarioId: usuario);
      final m = (await movimientosDe(id)).single;
      expect((m.milesimasAnterior, m.milesimasPosterior), (15000, 11600));
      expect(m.motivo, 'Conteo físico');
    });

    test('editar cambia el envase y el costo sin tocar el stock', () async {
      final id = await topCoat(stock: 4000);
      await editarInsumo(
        db,
        insumoId: id,
        nombre: 'Top coat brillo',
        unidad: UnidadInsumo.ml,
        contenidoEnvaseMilesimas: 10000,
        costoEnvaseCentavos: 900000,
        stockMinimoMilesimas: 3000,
        usuarioId: usuario,
      );
      final lista = await listarInsumos(db);
      final i = lista.single;
      expect(i.insumo.nombre, 'Top coat brillo');
      expect(i.stockMilesimas, 4000);
      expect(i.costoPorUnidadCentavos, 90000, reason: r'$ 9.000 / 10 ml = $ 900 el ml');
      expect(i.stockBajo, isFalse);
      await contarInsumo(db, insumoId: id, stockMilesimas: 3000, usuarioId: usuario);
      expect((await listarInsumos(db)).single.stockBajo, isTrue);
    });

    test('los insumos no aparecen como servicios ni al revés', () async {
      await topCoat();
      expect(await listarServicios(db), isEmpty);
    });
  });

  group('servicios', () {
    test('un servicio guarda su receta por global_id y la lista calcula costo, alcanza para y el que se acaba primero', () async {
      final coat = await topCoat(stock: 2000); // rinde 5 de 0,4 ml
      final guante = await guantes(); // 50 guantes, rinde 25 de a 2
      final id = await guardarServicio(
        db,
        nombre: 'Kapping',
        precioCentavos: 2000000,
        duracionMinutos: 60,
        receta: [(insumoId: coat, milesimas: 400), (insumoId: guante, milesimas: 2000)],
        usuarioId: usuario,
      );

      final s = (await listarServicios(db)).single;
      expect(s.servicio.id, id);
      expect(s.servicio.esServicio, isTrue);
      expect(s.servicio.recetaServicio, contains('"milesimas":400'));
      expect(s.receta.map((u) => u.insumo.nombre), ['Top coat', 'Guantes']);
      // 11000 × 0,4/15 = 293,33 + 8000 × 2/100 = 160 → 453,33 → $ 454.
      expect(s.costo.insumosCentavos, 45400);
      expect(s.costo.manoDeObraCentavos, 0);
      expect(s.servicio.costoCentavos, 45400, reason: 'el costo de hoy queda guardado en el servicio');
      expect(s.alcanzaPara, 5);
      expect(s.seAcabaPrimero?.nombre, 'Top coat');
      expect(s.gananciaBuscadaBp, gananciaBuscadaPorDefectoBp);
      expect(s.precioSugerido, precioSugeridoCentavos(costoCentavos: 45400, gananciaBuscadaBp: 6000));
    });

    test('el costo de la lista sigue al costo nuevo de un insumo', () async {
      final coat = await topCoat(stock: 15000);
      await guardarServicio(db, nombre: 'Esmaltado', precioCentavos: 900000, duracionMinutos: 30, receta: [(insumoId: coat, milesimas: 1500)], usuarioId: usuario);
      expect((await listarServicios(db)).single.costo.insumosCentavos, 110000); // 1/10 del frasco
      await cargarCompraDeInsumo(db, insumoId: coat, envases: 1, costoEnvaseCentavos: 1500000, usuarioId: usuario);
      expect((await listarServicios(db)).single.costo.insumosCentavos, 150000);
    });

    test('la mano de obra suma solo si el servicio la suma, el módulo está prendido y hay valor de la hora', () async {
      final coat = await topCoat(stock: 15000);
      await guardarServicio(
        db,
        nombre: 'Semi',
        precioCentavos: 1500000,
        duracionMinutos: 90,
        receta: [(insumoId: coat, milesimas: 1500)],
        sumaManoDeObra: true,
        usuarioId: usuario,
      );
      expect((await listarServicios(db)).single.costo.manoDeObraCentavos, 0, reason: 'sin valor de la hora');

      await configurarValorHora(db, 800000);
      expect((await listarServicios(db)).single.costo.manoDeObraCentavos, 1200000, reason: r'1,5 h × $ 8.000');

      await configurarModulo(db, Modulo.manoDeObra, activo: false);
      expect((await listarServicios(db)).single.costo.manoDeObraCentavos, 0, reason: 'módulo apagado');
    });

    test('editar un servicio reescribe la receta y deja el cambio de precio en el historial', () async {
      final coat = await topCoat(stock: 15000);
      final guante = await guantes();
      final id = await guardarServicio(db, nombre: 'Kapping', precioCentavos: 2000000, duracionMinutos: 60, receta: [(insumoId: coat, milesimas: 400)], usuarioId: usuario);
      await guardarServicio(
        db,
        servicioId: id,
        nombre: 'Kapping gel',
        precioCentavos: 2200000,
        duracionMinutos: 75,
        receta: [(insumoId: guante, milesimas: 2000)],
        gananciaBuscadaBp: 5000,
        usuarioId: usuario,
      );
      final s = (await listarServicios(db)).single;
      expect(s.servicio.nombre, 'Kapping gel');
      expect(s.servicio.duracionMinutos, 75);
      expect(s.receta.single.insumo.nombre, 'Guantes');
      expect(s.gananciaBuscadaBp, 5000);
      final historial = await (db.select(db.historialDePrecios)..where((h) => h.productoId.equals(id))).get();
      expect(historial.map((h) => h.precioCentavos), [2000000, 2200000]);
    });

    test('una receta con algo que no es insumo, repetido o en cero no se guarda', () async {
      final coat = await topCoat();
      final noInsumo = (await db.select(db.productos).get()).firstWhere((p) => !p.esInsumo).id;
      Future<int> con(List<LineaDeReceta> receta) =>
          guardarServicio(db, nombre: 'X', precioCentavos: 100, duracionMinutos: 10, receta: receta, usuarioId: usuario);
      await expectLater(con([(insumoId: coat, milesimas: 0)]), throwsArgumentError);
      await expectLater(con([(insumoId: coat, milesimas: 1), (insumoId: coat, milesimas: 2)]), throwsArgumentError);
      await expectLater(con([(insumoId: noInsumo, milesimas: 1)]), throwsArgumentError);
      expect(
        () => guardarServicio(db, nombre: 'X', precioCentavos: 100, duracionMinutos: 0, receta: const [], usuarioId: usuario),
        throwsArgumentError,
      );
    });

    test('dejar de ofrecer lo saca de la lista pero no lo borra', () async {
      final id = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, receta: const [], usuarioId: usuario);
      await dejarDeOfrecer(db, id);
      expect(await listarServicios(db), isEmpty);
      expect((await listarServicios(db, soloActivos: false)).single.servicio.activo, isFalse);
    });

    test('un insumo de la receta que no llegó a este equipo se cuenta aparte, sin romper la lista', () async {
      final id = await guardarServicio(db, nombre: 'Corte', precioCentavos: 1000000, duracionMinutos: 30, receta: const [], usuarioId: usuario);
      await db.customStatement(
        "UPDATE productos SET receta_servicio = '[{\"gid\":\"no-existe\",\"milesimas\":5}]' WHERE id = $id",
      );
      final s = (await listarServicios(db)).single;
      expect(s.receta, isEmpty);
      expect(s.insumosSinLlegar, 1);
      expect(s.alcanzaPara, isNull);
    });
  });

  test('hasta la etapa 3, insumos y servicios no aparecen en la venta ni en las listas de productos', () async {
    final coat = await topCoat(stock: 15000);
    await guardarServicio(db, nombre: 'Kapping', precioCentavos: 2000000, duracionMinutos: 60, receta: [(insumoId: coat, milesimas: 400)], usuarioId: usuario);
    await crearProducto(db, nombre: 'Quitaesmalte', precioCentavos: 300000, stock: 4, usuarioId: usuario);

    List<String> nombres(Iterable<Producto> ps) => [for (final p in ps) p.nombre];
    expect(nombres(await listarProductos(db)), ['Quitaesmalte']);
    expect(nombres(await listarProductos(db, busqueda: 'k')), isEmpty);
    expect(nombres(await catalogoConStockDePromos(db)), isNot(anyOf(contains('Top coat'), contains('Kapping'))));
    expect([for (final p in await productosTodos(db)) p.nombre], ['Quitaesmalte']);
    expect([for (final p in await productosSinProveedor(db)) p.nombre], ['Quitaesmalte']);
  });
}
