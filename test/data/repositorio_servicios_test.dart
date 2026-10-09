// Servicios e insumos contra una base de verdad (`docs/PLAN-SERVICIOS.md`, etapa 2): alta, compra por envases, conteo,
// receta por `global_id` y el listado con costo, precio sugerido y "alcanza para". Las cuentas en sí se prueban en
// `test/domain/servicios_test.dart`; acá, que se guarden y se lean bien, con su rastro.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/busqueda_productos.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_tablero.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/domain/servicios.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = (await db.select(db.usuarios).get()).first.id;
  });
  tearDown(() => db.close());

  Future<Producto> producto(int id) => (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
  Future<List<MovimientoStock>> movimientos(int id) =>
      (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(id))).get();

  // Top coat: frasco de 15 ml a $11.000.
  Future<int> topCoat() => crearInsumo(
        db,
        nombre: 'Top coat',
        unidad: UnidadInsumo.ml,
        contenidoEnvaseMilesimas: 15000,
        costoEnvaseCentavos: 1100000,
        usuarioId: usuarioId,
      );

  group('insumos', () {
    test('el alta es un insumo con stock 0, sin precio de venta, y deja la primera foto del costo', () async {
      final id = await topCoat();
      final p = await producto(id);
      expect(p.esInsumo, isTrue);
      expect(p.esServicio, isFalse);
      expect(p.unidadInsumo, 'ml');
      expect(p.stockMilesimas, 0);
      expect(p.precioCentavos, isNull);
      expect(p.costoCentavos, 1100000);
      expect(p.globalId, isNotNull);
      expect((await historialDelProducto(db, id)).single.costoCentavos, 1100000);
    });

    test('sin contenido de envase no se da de alta', () async {
      expect(
        () => crearInsumo(db, nombre: 'X', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 0, costoEnvaseCentavos: 1, usuarioId: usuarioId),
        throwsArgumentError,
      );
    });

    test('comprar 2 envases suma 30 ml y deja el movimiento con las milésimas antes y después', () async {
      final id = await topCoat();
      await cargarCompraDeInsumo(db, insumoId: id, envases: 2, usuarioId: usuarioId);
      expect((await producto(id)).stockMilesimas, 30000);
      final m = (await movimientos(id)).single;
      expect(m.tipo, 'AJUSTE');
      expect(m.milesimas, 30000);
      expect(m.milesimasAnterior, 0);
      expect(m.milesimasPosterior, 30000);
      expect(m.motivo, 'Compra de 2 envases');
      expect(m.globalId, isNotNull);
    });

    test('una compra a otro precio cambia el costo del envase y queda en el historial', () async {
      final id = await topCoat();
      await cargarCompraDeInsumo(db, insumoId: id, envases: 1, costoEnvaseCentavos: 1250000, usuarioId: usuarioId);
      expect((await producto(id)).costoCentavos, 1250000);
      expect((await historialDelProducto(db, id)).map((h) => h.costoCentavos), containsAll([1100000, 1250000]));
    });

    test('contar corrige el stock con rastro; contar lo mismo no deja movimiento', () async {
      final id = await topCoat();
      await cargarCompraDeInsumo(db, insumoId: id, envases: 1, usuarioId: usuarioId);
      await contarInsumo(db, insumoId: id, stockMilesimas: 12400, usuarioId: usuarioId);
      expect((await producto(id)).stockMilesimas, 12400);
      final conteo = (await movimientos(id)).last;
      expect(conteo.motivo, 'Conteo físico');
      expect(conteo.milesimas, -2600);
      await contarInsumo(db, insumoId: id, stockMilesimas: 12400, usuarioId: usuarioId);
      expect(await movimientos(id), hasLength(2));
    });

    test('un producto común no se compra ni se cuenta como insumo', () async {
      final yerba = await crearProducto(db, nombre: 'Yerba', precioCentavos: 520000, usuarioId: usuarioId);
      expect(() => cargarCompraDeInsumo(db, insumoId: yerba, envases: 1, usuarioId: usuarioId), throwsArgumentError);
      expect(() => contarInsumo(db, insumoId: yerba, stockMilesimas: 1, usuarioId: usuarioId), throwsArgumentError);
    });

    test('poco stock según el mínimo cargado', () async {
      final id = await crearInsumo(
        db,
        nombre: 'Guantes',
        unidad: UnidadInsumo.u,
        contenidoEnvaseMilesimas: 100000,
        costoEnvaseCentavos: 900000,
        stockMinimoMilesimas: 20000,
        usuarioId: usuarioId,
      );
      await contarInsumo(db, insumoId: id, stockMilesimas: 15000, usuarioId: usuarioId);
      final listado = (await listarInsumos(db)).single;
      expect(listado.pocoStock, isTrue);
      expect(listado.costoPorUnidadCentavos, 9000); // $90 el guante
    });
  });

  group('servicios', () {
    test('la receta se guarda por global_id y el listado calcula costo, sugerido y alcanza para', () async {
      final tc = await topCoat();
      await cargarCompraDeInsumo(db, insumoId: tc, envases: 1, usuarioId: usuarioId); // 15 ml
      final id = await crearServicio(
        db,
        nombre: 'Semipermanente manos',
        precioCentavos: 1800000,
        duracionMinutos: 60,
        receta: [(insumoId: tc, milesimas: 400)],
        usuarioId: usuarioId,
      );
      final p = await producto(id);
      expect(p.esServicio, isTrue);
      expect(recetaDesdeJson(p.recetaServicio).single, (gid: (await producto(tc)).globalId!, milesimas: 400));

      final s = (await listarServicios(db, conManoDeObra: false)).single;
      // 11.000 × 0,4 / 15 = 293,33 → $294.
      expect(s.costo.insumosCentavos, 29400);
      expect(s.costo.manoDeObraCentavos, 0);
      expect(s.precioSugeridoCentavos, precioSugeridoCentavos(costoCentavos: 29400, gananciaBuscadaBp: gananciaBuscadaPorDefectoBp));
      expect(s.alcanzaPara, 37); // 15000 / 400
      expect(s.seAcabaPrimero?.producto.id, tc);
      expect(s.faltantes, 0);
    });

    test('la mano de obra entra solo con el módulo, el servicio que la suma y el valor de la hora cargado', () async {
      await crearServicio(db, nombre: 'Corte', precioCentavos: 1200000, duracionMinutos: 30, sumaManoDeObra: true, usuarioId: usuarioId);
      expect((await listarServicios(db, conManoDeObra: true)).single.costo.manoDeObraCentavos, 0, reason: 'sin valor de la hora');
      await configurarValorHora(db, 800000);
      expect((await listarServicios(db, conManoDeObra: true)).single.costo.manoDeObraCentavos, 400000);
      expect((await listarServicios(db, conManoDeObra: false)).single.costo.manoDeObraCentavos, 0, reason: 'módulo apagado');
    });

    test('editar el precio queda en el historial; la ganancia buscada es de cada servicio', () async {
      final id = await crearServicio(db, nombre: 'Corte', precioCentavos: 1200000, duracionMinutos: 30, usuarioId: usuarioId);
      await editarServicio(
        db,
        id: id,
        nombre: 'Corte clásico',
        precioCentavos: 1300000,
        duracionMinutos: 30,
        gananciaBuscadaBp: 7000,
        usuarioId: usuarioId,
      );
      expect((await historialDelProducto(db, id)).map((h) => h.precioCentavos), containsAll([1200000, 1300000]));
      expect((await listarServicios(db, conManoDeObra: false)).single.gananciaBuscadaBp, 7000);
    });

    test('un insumo dos veces o una cantidad en cero no se guardan', () async {
      final tc = await topCoat();
      expect(
        () => crearServicio(db, nombre: 'X', precioCentavos: 1, duracionMinutos: 10,
            receta: [(insumoId: tc, milesimas: 100), (insumoId: tc, milesimas: 200)], usuarioId: usuarioId),
        throwsArgumentError,
      );
      expect(
        () => crearServicio(db, nombre: 'X', precioCentavos: 1, duracionMinutos: 10, receta: [(insumoId: tc, milesimas: 0)], usuarioId: usuarioId),
        throwsArgumentError,
      );
    });

    test('un insumo de la receta que todavía no llegó cuenta como faltante, sin cortar la lista', () async {
      final id = await crearServicio(db, nombre: 'Kapping', precioCentavos: 2200000, duracionMinutos: 75, usuarioId: usuarioId);
      await db.customStatement(
        "UPDATE productos SET receta_servicio = '[{\"gid\":\"no-llego\",\"milesimas\":500}]' WHERE id = $id",
      );
      final s = (await listarServicios(db, conManoDeObra: false)).single;
      expect(s.faltantes, 1);
      expect(s.receta, isEmpty);
      expect(s.alcanzaPara, isNull);
    });

    test('dado de baja no se lista, salvo pedido', () async {
      final id = await crearServicio(db, nombre: 'Retiro', precioCentavos: 600000, duracionMinutos: 20, usuarioId: usuarioId);
      await cambiarActivo(db, id: id, activo: false);
      expect(await listarServicios(db, conManoDeObra: false), isEmpty);
      expect(await listarServicios(db, incluirInactivos: true, conManoDeObra: false), hasLength(1));
    });

    test('un JSON de receta roto es una receta vacía', () {
      expect(recetaDesdeJson('{no es json'), isEmpty);
      expect(recetaDesdeJson('{"gid":"x"}'), isEmpty);
      expect(recetaDesdeJson(null), isEmpty);
    });
  });

  test('hasta la etapa 3, insumos y servicios no se venden ni aparecen en las listas del almacén', () async {
    final tc = await topCoat();
    await contarInsumo(db, insumoId: tc, stockMilesimas: 5000, usuarioId: usuarioId);
    await crearServicio(db, nombre: 'Top semipermanente', precioCentavos: 1800000, duracionMinutos: 60, usuarioId: usuarioId);
    final catalogo = await db.select(db.productos).get();
    expect(buscarProductos(catalogo: catalogo, textoBuscado: 'top', incluirSinStock: true), isEmpty);
    expect((await listarProductos(db)).where((p) => p.nombre.toLowerCase().contains('top')), isEmpty);
    expect((await productosTodos(db)).where((p) => p.nombre.toLowerCase().contains('top')), isEmpty);
    expect((await tableroDelDia(db)).stockBajo.where((p) => p.nombre.toLowerCase().contains('top')), isEmpty);
  });

  test('dos equipos gastan del mismo frasco a la vez: al sincronizar se suman los dos movimientos', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final celular = baseDeTest();
    addTearDown(() async {
      await celular.close();
      establecerIdDispositivo('desktop');
    });
    final usuarioCelular = (await celular.select(celular.usuarios).get()).first.id;

    // El alta llega al celular, y después la compra como movimiento (así anda la sync de todos los días).
    final tc = await topCoat();
    await aplicarCambios(celular, tabla: 'productos', filas: await cambiosDesde(db, tabla: 'productos', desde: 0));
    await cargarCompraDeInsumo(db, insumoId: tc, envases: 2, usuarioId: usuarioId); // 30 ml
    await aplicarCambios(celular, tabla: 'movimientos_de_stock', filas: await cambiosDesde(db, tabla: 'movimientos_de_stock', desde: 0));
    final tcCelular = (await (celular.select(celular.productos)..where((p) => p.nombre.equals('Top coat'))).getSingle()).id;
    expect((await (celular.select(celular.productos)..where((p) => p.id.equals(tcCelular))).getSingle()).stockMilesimas, 30000);

    // Cada uno cuenta por su lado sin verse: la PC gastó 2 ml, el celular 1 ml.
    await contarInsumo(db, insumoId: tc, stockMilesimas: 28000, usuarioId: usuarioId);
    establecerIdDispositivo('android');
    await contarInsumo(celular, insumoId: tcCelular, stockMilesimas: 29000, usuarioId: usuarioCelular);

    // Desde 0: lo que ya estaba se reconoce por `global_id` y no se vuelve a aplicar.
    await aplicarCambios(db, tabla: 'movimientos_de_stock', filas: await cambiosDesde(celular, tabla: 'movimientos_de_stock', desde: 0));
    await aplicarCambios(celular, tabla: 'movimientos_de_stock', filas: await cambiosDesde(db, tabla: 'movimientos_de_stock', desde: 0));
    // Un cambio del producto por otro motivo no pisa el contador.
    await aplicarCambios(celular, tabla: 'productos', filas: await cambiosDesde(db, tabla: 'productos', desde: 0));

    expect((await producto(tc)).stockMilesimas, 27000);
    expect((await (celular.select(celular.productos)..where((p) => p.id.equals(tcCelular))).getSingle()).stockMilesimas, 27000);
  });
}
