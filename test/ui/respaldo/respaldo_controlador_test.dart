// Tests con test() plano, no testWidgets(): en este entorno, cualquier
// operación real de dart:io (incluso un File.writeAsString en una ruta
// conocida) se cuelga indefinidamente dentro de la zona especial de
// testWidgets (verificado a mano, no es un bug del código). La carga real de
// respaldos (que sí toca disco) se prueba acá con test() plano; la UI se
// prueba aparte solo en los estados que no requieren carpeta configurada.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_respaldo.dart';
import 'package:la_plazoleta/ui/respaldo/respaldo_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late Directory carpeta;

  setUp(() async {
    db = baseDeTest();
    carpeta = await Directory.systemTemp.createTemp('respaldo_controlador_test_');
  });
  tearDown(() async {
    await db.close();
    await carpeta.delete(recursive: true);
  });

  /// Un respaldo real de la base de prueba, como archivo .sqlite suelto.
  Future<String> hacerRespaldoDeTest() async {
    final destino = '${carpeta.path}/una_base.sqlite';
    await db.customStatement('VACUUM INTO ?', [destino]);
    return destino;
  }

  test('cargarTodo trae carpeta, cantidad de copias, respaldos existentes y si hay caja abierta', () async {
    await configurarCarpetaRespaldo(db, carpeta.path);

    final c = RespaldoControlador(db);
    await c.cargarTodo();

    expect(c.carpeta, carpeta.path);
    expect(c.cantidadCopias, 14);
    expect(c.respaldos, isEmpty);
    expect(c.hayCajaAbierta, isFalse);
    expect(c.cargando, isFalse);
  });

  test('con una sesión de caja abierta, hayCajaAbierta es true', () async {
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );

    final c = RespaldoControlador(db);
    await c.cargarTodo();

    expect(c.hayCajaAbierta, isTrue);
  });

  test('elegirCarpeta guarda la carpeta y recarga', () async {
    final c = RespaldoControlador(db);
    await c.cargarTodo();
    expect(c.carpeta, isNull);

    await c.elegirCarpeta(carpeta.path);

    expect(c.carpeta, carpeta.path);
  });

  test('respaldarAhora crea un respaldo real y actualiza la lista', () async {
    await configurarCarpetaRespaldo(db, carpeta.path);
    final c = RespaldoControlador(db);
    await c.cargarTodo();

    await c.respaldarAhora();

    expect(c.error, isNull);
    expect(c.respaldando, isFalse);
    expect(c.respaldos, hasLength(1));
  });

  test('respaldarAhora sin carpeta configurada deja un error legible, sin tirar una excepción', () async {
    final c = RespaldoControlador(db);
    await c.cargarTodo();

    await c.respaldarAhora();

    expect(c.error, isNotNull);
  });

  group('importar una base desde un archivo', () {
    test('un .sqlite bueno queda listo; uno malo deja el motivo en error y no devuelve nada', () async {
      final copia = await hacerRespaldoDeTest();
      final c = RespaldoControlador(db, carpetaTemporal: Directory('${carpeta.path}/listas'));

      final buena = await c.prepararImportacionDeArchivo(copia);
      expect(buena, isNotNull);
      expect(c.error, isNull);

      final mala = File('${carpeta.path}/foto.png')..writeAsBytesSync(List.filled(300, 7));
      expect(await c.prepararImportacionDeArchivo(mala.path), isNull);
      expect(c.error, contains('no es una base'));

      // Un intento bueno después limpia el error.
      expect(await c.prepararImportacionDeArchivo(copia), isNotNull);
      expect(c.error, isNull);
    });
  });
}

