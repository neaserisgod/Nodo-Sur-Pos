// Mismo nombre = misma persona (El dueño, 2026-10-13: "aparezco tres veces"): las listas muestran uno, lo cargado a nombre de
// los repetidos pasa al que queda, y dos equipos que crearon el mismo perfil terminan con el mismo.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_usuarios.dart';

import '../helpers/base_para_tests.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase pc;
  late AppDatabase celular;

  setUp(() {
    pc = baseDeTest();
    celular = baseDeTest();
    establecerIdDispositivo('desktop');
  });
  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  /// Inserta un perfil a mano, como lo dejaba un equipo antes de este arreglo (sin pasar por `crearUsuario`).
  Future<int> perfilCrudo(AppDatabase db, String nombre, String gid, {bool activo = true}) => db.into(db.usuarios).insert(
    UsuariosCompanion.insert(nombre: nombre, globalId: Value(gid), activo: Value(activo), actualizadoEn: Value(DateTime.now())),
  );

  Iterable<String> nombres(List<Usuario> us) => us.map((u) => u.nombre);

  test('la lista muestra una sola vez a cada persona, activa si alguno de sus repetidos lo está', () async {
    await perfilCrudo(pc, 'Bruno Fuentes', 'b', activo: false);
    await perfilCrudo(pc, 'bruno fuentes', 'a', activo: false);
    await perfilCrudo(pc, 'BRUNO FUENTES', 'c');
    final lista = (await listarUsuarios(pc)).where((u) => u.nombre.toLowerCase() == 'bruno fuentes').toList();
    expect(lista, hasLength(1));
    expect(lista.single.globalId, 'a', reason: 'queda el de global_id menor');
    expect(lista.single.activo, isTrue);
    expect(nombres(await listarUsuariosActivos(pc)).where((n) => n.toLowerCase() == 'bruno fuentes'), hasLength(1));
  });

  test('unificar pasa lo cargado a nombre de un repetido al que queda, sin borrar el repetido', () async {
    final queda = await perfilCrudo(pc, 'Caro', 'a');
    final repetido = await perfilCrudo(pc, 'caro', 'b');
    final producto = await crearProducto(pc, nombre: 'Yerba', precioCentavos: 1000, stock: 0, usuarioId: repetido);
    await ajustarStockRapido(pc, productoId: producto, usuarioId: repetido, stock: 5);

    expect(await unificarUsuariosRepetidos(pc), 1);
    final movimientos = await pc.select(pc.movimientosDeStock).get();
    expect(movimientos.map((m) => m.usuarioId).toSet(), {queda});
    expect((await pc.select(pc.usuarios).get()).any((u) => u.id == repetido), isTrue, reason: 'sigue existiendo: algo puede apuntarle');
    expect(await unificarUsuariosRepetidos(pc), 1, reason: 'repetir no rompe nada');
  });

  test('dar de alta un nombre que ya existe devuelve ese perfil (y lo reactiva si estaba desactivado)', () async {
    final id = await crearUsuario(pc, 'Marta Gómez');
    expect(await crearUsuario(pc, '  marta gomez '), id);
    await desactivarUsuario(pc, id);
    expect(await crearUsuario(pc, 'Marta Gómez'), id);
    expect((await (pc.select(pc.usuarios)..where((u) => u.id.equals(id))).getSingle()).activo, isTrue);
  });

  test('dos equipos crearon el mismo perfil sin verse: al sincronizar los dos quedan con uno solo, el mismo', () async {
    final enPc = await crearUsuario(pc, 'Bruno Fuentes');
    final enCel = await crearUsuario(celular, 'Bruno Fuentes');
    final producto = await crearProducto(celular, nombre: 'Yerba', precioCentavos: 1000, stock: 0, usuarioId: enCel);
    await ajustarStockRapido(celular, productoId: producto, usuarioId: enCel, stock: 3);

    for (final (origen, destino) in [(pc, celular), (celular, pc), (pc, celular)]) {
      for (final t in tablasSincronizables.keys) {
        await aplicarCambios(destino, tabla: t, filas: await cambiosDesde(origen, tabla: t, desde: 0));
      }
    }
    final gidPc = (await (pc.select(pc.usuarios)..where((u) => u.id.equals(enPc))).getSingle()).globalId;
    final gidCel = (await (celular.select(celular.usuarios)..where((u) => u.id.equals(enCel))).getSingle()).globalId;
    final ganador = [gidPc!, gidCel!]..sort();

    for (final db in [pc, celular]) {
      final brunos = (await listarUsuarios(db)).where((u) => u.nombre == 'Bruno Fuentes').toList();
      expect(brunos, hasLength(1));
      expect(brunos.single.globalId, ganador.first, reason: 'los dos eligen el mismo');
      final movimientos = await db.select(db.movimientosDeStock).get();
      expect(movimientos.map((m) => m.usuarioId).toSet(), {brunos.single.id}, reason: 'lo del celular quedó a nombre del que queda');
    }
  });
}
