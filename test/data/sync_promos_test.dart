import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';

import '../helpers/base_para_tests.dart';

/// Las promos viajan entre equipos con sus artículos (v62, El dueño, 2026-10-07: promos en el celular).
void main() {
  late AppDatabase pc;
  late AppDatabase celular;

  Future<({int yerba, int galletitas, int usuario})> catalogo(AppDatabase db) async {
    final usuario = (await db.select(db.usuarios).get()).first.id;
    await db.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial' WHERE id = $usuario");
    Future<int> producto(String nombre, String gid, int stock) => db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: nombre,
            precioCentavos: const Value(300000),
            costoCentavos: const Value(200000),
            stock: Value(stock),
            globalId: Value(gid),
          ),
        );
    return (yerba: await producto('Yerba', 'p-yerba', 10), galletitas: await producto('Galletitas', 'p-galle', 3), usuario: usuario);
  }

  Future<List<Map<String, dynamic>>> sincronizar(AppDatabase origen, AppDatabase destino) async {
    final fallidas = <Map<String, dynamic>>[];
    for (final tabla in tablasSincronizables.keys) {
      fallidas.addAll(await aplicarCambios(destino, tabla: tabla, filas: await cambiosDesde(origen, tabla: tabla, desde: 0)));
    }
    return fallidas;
  }

  setUp(() {
    pc = baseDeTest();
    celular = baseDeTest();
  });
  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  test('una promo creada en la PC llega al celular con sus artículos y se puede vender ahí', () async {
    final p = await catalogo(pc);
    final c = await catalogo(celular);
    await guardarPromo(
      pc,
      nombre: 'Merienda',
      articulos: [(productoId: p.yerba, cantidad: 1), (productoId: p.galletitas, cantidad: 2)],
      gananciaBp: 3000,
      usuarioId: p.usuario,
    );

    expect(await sincronizar(pc, celular), isEmpty);

    final promos = await listarPromos(celular);
    expect(promos.single.promo.nombre, 'Merienda');
    expect({for (final x in promos.single.componentes) x.producto.id: x.cantidad}, {c.yerba: 1, c.galletitas: 2});
    final enLaBusqueda = (await catalogoConStockDePromos(celular)).firstWhere((x) => x.esPromo);
    expect(enLaBusqueda.stock, 1, reason: 'alcanzan las galletitas para una sola (3 ÷ 2)');
  });

  test('editar la promo en el celular cambia sus artículos en la PC, sin dejar los viejos', () async {
    final p = await catalogo(pc);
    final c = await catalogo(celular);
    await guardarPromo(pc, nombre: 'Merienda', articulos: [(productoId: p.yerba, cantidad: 1), (productoId: p.galletitas, cantidad: 2)], gananciaBp: 3000, usuarioId: p.usuario);
    await sincronizar(pc, celular);
    final promoCel = (await listarPromos(celular)).single.promo.id;

    await Future<void>.delayed(const Duration(milliseconds: 1100)); // `actualizado_en` va en segundos
    await guardarPromo(celular, promoId: promoCel, nombre: 'Merienda x3', articulos: [(productoId: c.yerba, cantidad: 1), (productoId: c.galletitas, cantidad: 3)], gananciaBp: 3000, usuarioId: c.usuario);
    expect(await sincronizar(celular, pc), isEmpty);

    final enLaPc = (await listarPromos(pc)).single;
    expect(enLaPc.promo.nombre, 'Merienda x3');
    expect({for (final x in enLaPc.componentes) x.producto.id: x.cantidad}, {p.yerba: 1, p.galletitas: 3});
  });

  test('si la promo llega antes que un artículo, se reintenta y queda armada cuando el artículo llega', () async {
    final p = await catalogo(pc);
    await catalogo(celular);
    final nuevo = await pc.into(pc.productos).insert(
          ProductosCompanion.insert(nombre: 'Mate', precioCentavos: const Value(500000), costoCentavos: const Value(300000), stock: const Value(4), globalId: const Value('p-mate')),
        );
    await guardarPromo(pc, nombre: 'Matera', articulos: [(productoId: p.yerba, cantidad: 1), (productoId: nuevo, cantidad: 1)], gananciaBp: 3000, usuarioId: p.usuario);
    final filas = await cambiosDesde(pc, tabla: 'productos', desde: 0);
    final promo = filas.where((f) => f['es_promo'] == 1).toList();
    final resto = filas.where((f) => f['es_promo'] != 1).toList();

    final pendientes = await aplicarCambios(celular, tabla: 'productos', filas: promo);
    expect(pendientes, hasLength(1), reason: 'el Mate todavía no llegó');
    await aplicarCambios(celular, tabla: 'productos', filas: [...resto, ...pendientes]);

    expect((await listarPromos(celular)).single.componentes, hasLength(2));
  });
}
