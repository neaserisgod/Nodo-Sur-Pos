import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/servicios.dart';

import '../helpers/base_para_tests.dart';

/// Insumos y servicios viajan entre equipos (v65, `docs/PLAN-SERVICIOS.md` etapa 2). El stock en milésimas es un contador:
/// dos equipos que lo mueven sin verse suman los dos cambios, como el stock de un producto.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase pc;
  late AppDatabase celular;

  Future<int> usuarioDe(AppDatabase db) async {
    final id = (await db.select(db.usuarios).get()).first.id;
    await db.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial' WHERE id = $id");
    return id;
  }

  Future<void> sincronizar(AppDatabase origen, AppDatabase destino) async {
    for (final tabla in tablasSincronizables.keys) {
      final fallidas = await aplicarCambios(destino, tabla: tabla, filas: await cambiosDesde(origen, tabla: tabla, desde: 0));
      expect(fallidas, isEmpty, reason: tabla);
    }
  }

  Future<Producto> porGid(AppDatabase db, String gid) => (db.select(db.productos)..where((p) => p.globalId.equals(gid))).getSingle();

  setUp(() async {
    pc = baseDeTest();
    celular = baseDeTest();
    await configurarRubro(pc, PlantillaRubro.unas);
    await configurarRubro(celular, PlantillaRubro.unas);
  });
  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  test('un insumo y un servicio creados en un equipo llegan al otro con su receta y sus cuentas', () async {
    final u = await usuarioDe(pc);
    await usuarioDe(celular);
    final coat = await crearInsumo(
      pc,
      nombre: 'Top coat',
      unidad: UnidadInsumo.ml,
      contenidoEnvaseMilesimas: 15000,
      costoEnvaseCentavos: 1100000,
      stockMilesimas: 2000,
      usuarioId: u,
    );
    await guardarServicio(pc, nombre: 'Kapping', precioCentavos: 2000000, duracionMinutos: 60, receta: [(insumoId: coat, milesimas: 400)], usuarioId: u);

    await sincronizar(pc, celular);

    final s = (await listarServicios(celular)).single;
    expect(s.servicio.nombre, 'Kapping');
    expect(s.insumosSinLlegar, 0);
    expect(s.receta.single.insumo.nombre, 'Top coat');
    expect(s.receta.single.insumo.stockMilesimas, 2000);
    expect(s.alcanzaPara, 5);
  });

  test('dos equipos usan el mismo insumo sin verse: al sincronizar, los dos cambios se suman (ninguno se pisa)', () async {
    final uPc = await usuarioDe(pc);
    final uCel = await usuarioDe(celular);
    final idPc = await crearInsumo(
      pc,
      nombre: 'Top coat',
      unidad: UnidadInsumo.ml,
      contenidoEnvaseMilesimas: 15000,
      costoEnvaseCentavos: 1100000,
      stockMilesimas: 10000,
      usuarioId: uPc,
    );
    final gid = (await pc.select(pc.productos).get()).firstWhere((p) => p.id == idPc).globalId!;
    await sincronizar(pc, celular);
    final idCel = (await porGid(celular, gid)).id;
    expect((await porGid(celular, gid)).stockMilesimas, 10000);

    // La PC carga una compra (+15 ml) y el celular cuenta lo que quedó (10 → 9,2 ml), cada uno sobre su copia.
    await cargarCompraDeInsumo(pc, insumoId: idPc, envases: 1, usuarioId: uPc);
    await contarInsumo(celular, insumoId: idCel, stockMilesimas: 9200, usuarioId: uCel);

    // Solo los movimientos, en las dos direcciones: el producto no trae su stock (no se pisa).
    for (final (origen, destino) in [(pc, celular), (celular, pc)]) {
      await aplicarCambios(destino, tabla: 'movimientos_de_stock', filas: await cambiosDesde(origen, tabla: 'movimientos_de_stock', desde: 0));
    }
    // 10 + 15 − 0,8 = 24,2 ml en los dos.
    expect((await porGid(pc, gid)).stockMilesimas, 24200);
    expect((await porGid(celular, gid)).stockMilesimas, 24200);

    // El celular cuenta de nuevo y después, en la PC, le cambian el nombre: el nombre viaja (es la edición más nueva), pero
    // sin arrastrar el stock de la PC por encima del que contó el celular.
    await contarInsumo(celular, insumoId: idCel, stockMilesimas: 20000, usuarioId: uCel);
    await editarInsumo(
      pc,
      insumoId: idPc,
      nombre: 'Top coat brillo',
      unidad: UnidadInsumo.ml,
      contenidoEnvaseMilesimas: 15000,
      costoEnvaseCentavos: 1100000,
      usuarioId: uPc,
    );
    // Más nueva de verdad: `actualizado_en` va en segundos y las dos ediciones caen en el mismo.
    await pc.customStatement('UPDATE productos SET actualizado_en = 999999999999 WHERE id = $idPc');
    await aplicarCambios(celular, tabla: 'productos', filas: await cambiosDesde(pc, tabla: 'productos', desde: 0));
    final enCelular = await porGid(celular, gid);
    expect(enCelular.nombre, 'Top coat brillo');
    expect(enCelular.stockMilesimas, 20000);
  });
}
