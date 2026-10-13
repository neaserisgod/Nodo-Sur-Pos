// Varias cuentas en un celular (2026-10-13): mover la activa a su carpeta y traer otra, sin mezclar nada, y terminar un
// cambio que se cortó a la mitad.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/borrar_celular.dart';
import 'package:la_plazoleta/companion/cuentas_del_celular.dart';
import 'package:la_plazoleta/domain/cuentas_del_celular.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

late CarpetasDelCelular carpetas;

File _base([String sufijo = '']) => File(p.join(carpetas.documentos.path, 'la_plazoleta.sqlite$sufijo'));
File _cuenta() => File(p.join(carpetas.soporte.path, 'cuenta_nube.json'));
File _botDatos() => File(p.join(carpetas.soporte.path, 'bot-datos', 'sesion.json'));
File _log() => File(p.join(carpetas.soporte.path, 'logs', 'errores.log'));

/// Deja "puesta" una cuenta: su base, su archivo de cuenta, datos del bot y sus preferencias.
Future<void> _ponerCuenta(String quien, {int usuario = 1}) async {
  _base().writeAsStringSync('base de $quien');
  _base('-wal').writeAsStringSync('wal de $quien');
  _cuenta().writeAsStringSync('{"email":"$quien@x.com"}');
  _botDatos()
    ..createSync(recursive: true)
    ..writeAsStringSync('bot de $quien');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('companion_usuario_id', usuario);
  await prefs.setString('companion_usuario_nombre', quien);
  await prefs.setBool('companion_algo', true);
  await prefs.setDouble('companion_decimal', 1.0);
  await prefs.setStringList('companion_lista', ['x', 'y']);
}

Future<void> _esLaCuentaDe(String quien, {int usuario = 1}) async {
  expect(_base().readAsStringSync(), 'base de $quien');
  expect(_base('-wal').readAsStringSync(), 'wal de $quien');
  expect(_cuenta().readAsStringSync(), contains('$quien@x.com'));
  expect(_botDatos().readAsStringSync(), 'bot de $quien');
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getInt('companion_usuario_id'), usuario);
  expect(prefs.getString('companion_usuario_nombre'), quien);
  expect(prefs.getBool('companion_algo'), isTrue);
  expect(prefs.getDouble('companion_decimal'), 1.0);
  expect(prefs.getStringList('companion_lista'), ['x', 'y']);
}

Future<void> _estaVacio() async {
  expect(_base().existsSync(), isFalse);
  expect(_cuenta().existsSync(), isFalse);
  expect(_botDatos().existsSync(), isFalse);
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getKeys().where(esPreferenciaDeLaCuenta), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final raiz = await Directory.systemTemp.createTemp('cuentas_celular_');
    addTearDown(() => raiz.delete(recursive: true));
    carpetas = CarpetasDelCelular(
      documentos: await Directory(p.join(raiz.path, 'documentos')).create(),
      soporte: await Directory(p.join(raiz.path, 'soporte')).create(),
    );
    SharedPreferences.setMockInitialValues({'companion_tema': 'oscuro'});
    _log()
      ..createSync(recursive: true)
      ..writeAsStringSync('registro del aparato');
  });

  test('agregar otra cuenta deja el lugar vacío y la primera guardada; volver la trae entera, y la segunda queda guardada', () async {
    await _ponerCuenta('ana', usuario: 7);
    final ana = identificarActiva(IndiceCuentas.vacio, email: 'ana@x.com', nombre: 'Ana');
    await cambiarDeCuenta(actual: ana, destino: null, carpetas: carpetas);
    await _estaVacio();
    expect((await leerIndiceCuentas(carpetas)).guardadas.single.email, 'ana@x.com');

    // Entra Beto en el lugar vacío.
    await _ponerCuenta('beto', usuario: 3);
    final beto = identificarActiva(await leerIndiceCuentas(carpetas), email: 'beto@x.com', nombre: 'Beto');
    await cambiarDeCuenta(actual: beto, destino: ana.id, carpetas: carpetas);
    await _esLaCuentaDe('ana', usuario: 7);
    final indice = await leerIndiceCuentas(carpetas);
    expect(indice.activa!.id, ana.id);
    expect(indice.guardadas.single.email, 'beto@x.com');

    // Y de vuelta a Beto: nada de Ana quedó en la de Beto ni al revés.
    await cambiarDeCuenta(actual: identificarActiva(indice, email: 'ana@x.com', nombre: 'Ana'), destino: indice.guardadas.single.id, carpetas: carpetas);
    await _esLaCuentaDe('beto', usuario: 3);
    expect(carpetas.guardada(ana.id).existsSync(), isTrue);
    expect(carpetas.guardada(beto.id).existsSync(), isFalse, reason: 'la traída ya no tiene carpeta guardada');
  });

  test('lo del aparato no se mueve: el tema y los registros siguen en su lugar', () async {
    await _ponerCuenta('ana');
    await cambiarDeCuenta(actual: identificarActiva(IndiceCuentas.vacio, email: 'ana@x.com', nombre: null), destino: null, carpetas: carpetas);
    expect((await SharedPreferences.getInstance()).getString('companion_tema'), 'oscuro');
    expect(_log().readAsStringSync(), 'registro del aparato');
  });

  test('un cambio cortado mientras guardaba se termina al abrir, sin perder nada', () async {
    await _ponerCuenta('beto', usuario: 3);
    final beto = identificarActiva(IndiceCuentas.vacio, email: 'beto@x.com', nombre: null);
    await cambiarDeCuenta(actual: beto, destino: null, carpetas: carpetas);
    await _ponerCuenta('ana', usuario: 7);
    final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);

    // Simula el corte: el índice dice "guardando" y solo la base llegó a moverse.
    final empezado = empezarCambio(await leerIndiceCuentas(carpetas), actual: ana, destino: beto.id);
    File(p.join(carpetas.guardadas.path, 'indice.json')).writeAsStringSync(jsonEncode(empezado.toJson()));
    final base = Directory(p.join(carpetas.guardada(ana.id).path, 'base'))..createSync(recursive: true);
    _base().renameSync(p.join(base.path, 'la_plazoleta.sqlite'));

    expect(await terminarCambioPendiente(carpetas), isTrue);
    await _esLaCuentaDe('beto', usuario: 3);
    expect((await leerIndiceCuentas(carpetas)).cambio, isNull);
    expect(await terminarCambioPendiente(carpetas), isFalse, reason: 'ya no queda nada pendiente');

    // Ana quedó guardada entera.
    await cambiarDeCuenta(actual: identificarActiva(await leerIndiceCuentas(carpetas), email: 'beto@x.com', nombre: null), destino: ana.id, carpetas: carpetas);
    await _esLaCuentaDe('ana', usuario: 7);
  });

  test('un cambio cortado mientras traía se termina sin devolver a la carpeta lo ya traído', () async {
    await _ponerCuenta('beto', usuario: 3);
    final beto = identificarActiva(IndiceCuentas.vacio, email: 'beto@x.com', nombre: null);
    await cambiarDeCuenta(actual: beto, destino: null, carpetas: carpetas);
    final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
    await _ponerCuenta('ana', usuario: 7);

    // Ana ya se guardó (simulado con el paso real) y se cortó trayendo a Beto: solo su base llegó.
    final empezado = empezarCambio(await leerIndiceCuentas(carpetas), actual: ana, destino: beto.id);
    await cambiarDeCuentaSoloGuardar(empezado);
    final baseBeto = File(p.join(carpetas.guardada(beto.id).path, 'base', 'la_plazoleta.sqlite'));
    baseBeto.renameSync(_base().path);

    expect(await terminarCambioPendiente(carpetas), isTrue);
    await _esLaCuentaDe('beto', usuario: 3);
    await cambiarDeCuenta(actual: identificarActiva(await leerIndiceCuentas(carpetas), email: 'beto@x.com', nombre: null), destino: ana.id, carpetas: carpetas);
    await _esLaCuentaDe('ana', usuario: 7);
  });

  group('cerrar sesión y borrar', () {
    test('con otras cuentas guardadas: borra solo la activa y trae la última usada', () async {
      await _ponerCuenta('beto', usuario: 3);
      await cambiarDeCuenta(actual: identificarActiva(IndiceCuentas.vacio, email: 'beto@x.com', nombre: null), destino: null, carpetas: carpetas);
      await _ponerCuenta('ana', usuario: 7);

      final quedo = await borrarTodoDelCelular(carpetas);
      expect(quedo!.email, 'beto@x.com');
      await _esLaCuentaDe('beto', usuario: 3);
      final indice = await leerIndiceCuentas(carpetas);
      expect(indice.guardadas, isEmpty, reason: 'la borrada no queda en ninguna lista');
      expect((await SharedPreferences.getInstance()).getString('companion_tema'), 'oscuro');
    });

    test('sin otras cuentas: queda como recién instalado', () async {
      await _ponerCuenta('ana');
      expect(await borrarTodoDelCelular(carpetas), isNull);
      await _estaVacio();
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });
}

/// Hace solo el paso "guardando" de un cambio, como si se hubiera cortado justo después (anotando "trayendo").
Future<void> cambiarDeCuentaSoloGuardar(IndiceCuentas empezado) async {
  // Guardar a la activa en su carpeta es lo mismo que agregar una cuenta nueva; después se reescribe el índice como si
  // estuviera trayendo a la otra.
  await cambiarDeCuenta(actual: empezado.activa!, destino: null, carpetas: carpetas);
  final trayendo = IndiceCuentas(
    activa: empezado.activa,
    guardadas: empezado.guardadas,
    cambio: empezado.cambio!.conPaso(PasoCambio.trayendo),
  );
  File(p.join(carpetas.guardadas.path, 'indice.json')).writeAsStringSync(jsonEncode(trayendo.toJson()));
}
