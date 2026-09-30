import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_usuarios.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  test('listarUsuarios trae al usuario sembrado, activo', () async {
    final usuarios = await listarUsuarios(db);
    expect(usuarios, hasLength(1));
    expect(usuarios.single.nombre, 'Dueño');
    expect(usuarios.single.activo, isTrue);
  });

  test('listarUsuariosActivos excluye a los desactivados', () async {
    final id = await crearUsuario(db, 'Ayuda finde');
    await desactivarUsuario(db, id);

    final activos = await listarUsuariosActivos(db);
    final todos = await listarUsuarios(db);

    expect(activos.any((u) => u.id == id), isFalse);
    expect(todos.any((u) => u.id == id), isTrue); // nunca se borra (misma regla que productos/proveedores)
  });

  test('crearUsuario agrega uno nuevo, activo por defecto', () async {
    final id = await crearUsuario(db, 'Ayuda finde');
    final usuarios = await listarUsuarios(db);
    final nuevo = usuarios.firstWhere((u) => u.id == id);
    expect(nuevo.nombre, 'Ayuda finde');
    expect(nuevo.activo, isTrue);
  });

  test('renombrarUsuario cambia el nombre sin tocar el resto', () async {
    final id = await crearUsuario(db, 'Nombre viejo');
    await renombrarUsuario(db, id, 'Nombre nuevo');
    final usuarios = await listarUsuarios(db);
    expect(usuarios.firstWhere((u) => u.id == id).nombre, 'Nombre nuevo');
  });

  test('desactivarUsuario y activarUsuario alternan el estado sin borrar la fila', () async {
    final id = await crearUsuario(db, 'Ayuda finde');
    await desactivarUsuario(db, id);
    expect((await listarUsuarios(db)).firstWhere((u) => u.id == id).activo, isFalse);

    await activarUsuario(db, id);
    expect((await listarUsuarios(db)).firstWhere((u) => u.id == id).activo, isTrue);
  });
}
