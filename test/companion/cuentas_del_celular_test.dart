// Varias cuentas en un celular (2026-10-13): mover la activa a su carpeta y traer otra, sin mezclar nada, y terminar un
// cambio que se cortó a la mitad.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/borrar_celular.dart';
import 'package:la_plazoleta/companion/cuentas_del_celular.dart';
import 'package:la_plazoleta/domain/cuentas_del_celular.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart' show PerfilDeCuenta;
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


  group('blindaje', () {
    Future<CuentaDelCelular> guardarBetoYPonerAna() async {
      await _ponerCuenta('beto', usuario: 3);
      final beto = identificarActiva(IndiceCuentas.vacio, email: 'beto@x.com', nombre: null);
      await cambiarDeCuenta(actual: beto, destino: null, carpetas: carpetas);
      await _ponerCuenta('ana', usuario: 7);
      return beto;
    }

    test('en dos tiempos: con la app abierta solo se guarda; lo elegido se trae al abrir', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas, soloGuardar: true);
      await _estaVacio();
      expect((await leerIndiceCuentas(carpetas)).cambio, isNotNull);
      expect(await terminarCambioPendiente(carpetas), isTrue);
      await _esLaCuentaDe('beto', usuario: 3);
    });

    test('lo que algo escribe TARDE (después de guardar, antes de cerrar) va a la cuenta vieja, nunca a la nueva', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas, soloGuardar: true);
      // Una vuelta de la sync y una preferencia que llegaron tarde, todavía con la app de Ana abierta.
      File(p.join(carpetas.soporte.path, 'estado_sync.json')).writeAsStringSync('sync de ana');
      await (await SharedPreferences.getInstance()).setString('companion_tarde', 'de ana');

      await terminarCambioPendiente(carpetas);
      await _esLaCuentaDe('beto', usuario: 3);
      expect(File(p.join(carpetas.soporte.path, 'estado_sync.json')).existsSync(), isFalse, reason: 'no se pegó a Beto');
      expect((await SharedPreferences.getInstance()).getString('companion_tarde'), isNull, reason: 'no se pegó a Beto');

      // Y volviendo a Ana, está todo, lo tardío incluido.
      final indice = await leerIndiceCuentas(carpetas);
      await cambiarDeCuenta(actual: identificarActiva(indice, email: 'beto@x.com', nombre: null), destino: ana.id, carpetas: carpetas);
      await _esLaCuentaDe('ana', usuario: 7);
      expect(File(p.join(carpetas.soporte.path, 'estado_sync.json')).readAsStringSync(), 'sync de ana');
      expect((await SharedPreferences.getInstance()).getString('companion_tarde'), 'de ana');
    });

    test('nunca se pisa nada: si en el destino ya hay algo con el mismo nombre, se aparta', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      // Un intento anterior ya había dejado una base de Ana en su carpeta (distinta de la de ahora).
      final base = Directory(p.join(carpetas.guardada(ana.id).path, 'base'))..createSync(recursive: true);
      File(p.join(base.path, 'la_plazoleta.sqlite')).writeAsStringSync('base vieja de ana');
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas);
      final apartados = Directory(p.join(carpetas.guardada(ana.id).path, 'conflictos')).listSync();
      expect(apartados.map((e) => File(e.path).readAsStringSync()), ['base vieja de ana']);
      expect(File(p.join(base.path, 'la_plazoleta.sqlite')).readAsStringSync(), 'base de ana', reason: 'gana la más nueva');
    });

    test('lo que encuentra suelto en el lugar al traer se aparta en _huerfanos, sin mezclarse', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas, soloGuardar: true);
      // Simula el lugar ya barrido y algo que aparece justo antes de traer (no debería pasar, pero si pasa no se mezcla).
      final indice = await leerIndiceCuentas(carpetas);
      File(p.join(carpetas.guardadas.path, 'indice.json')).writeAsStringSync(
        jsonEncode(IndiceCuentas(activa: indice.activa, guardadas: indice.guardadas, cambio: indice.cambio!.conPaso(PasoCambio.trayendo)).toJson()),
      );
      _cuenta().writeAsStringSync('{"email":"nadie@x.com"}');
      await (await SharedPreferences.getInstance()).setString('companion_suelta', 'x');

      await terminarCambioPendiente(carpetas);
      await _esLaCuentaDe('beto', usuario: 3);
      expect((await SharedPreferences.getInstance()).getString('companion_suelta'), isNull);
      final huerfanos = Directory(p.join(carpetas.guardadas.path, '_huerfanos'));
      final todo = huerfanos.listSync(recursive: true).whereType<File>().map((f) => f.readAsStringSync()).join('|');
      expect(todo, contains('nadie@x.com'));
      expect(todo, contains('companion_suelta'));
    });

    test('un índice ilegible usa el anterior; sin ninguno, se rearma con las carpetas: nada queda invisible', () async {
      final beto = await guardarBetoYPonerAna();
      final indice = File(p.join(carpetas.guardadas.path, 'indice.json'));
      indice.writeAsStringSync('{roto');
      expect((await leerIndiceCuentas(carpetas)).guardadas.map((g) => g.id), contains(beto.id), reason: 'del anterior');
      File('${indice.path}.anterior').writeAsStringSync('tampoco');
      final rearmado = await leerIndiceCuentas(carpetas);
      expect(rearmado.guardadas.single.id, beto.id);
      expect(rearmado.guardadas.single.email, 'beto@x.com', reason: 'cada carpeta dice quién es');
    });

    test('pasar a una que ya no está: error claro y no se mueve nada', () async {
      final beto = await guardarBetoYPonerAna();
      carpetas.guardada(beto.id).deleteSync(recursive: true);
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await expectLater(cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas), throwsA(isA<CuentaNoEstaEnElCelular>()));
      await _esLaCuentaDe('ana', usuario: 7);
      expect((await leerIndiceCuentas(carpetas)).guardadas, isEmpty, reason: 'la lista no ofrece una carpeta que no está');
    });

    test('se cortó justo después de traer (carpeta ya borrada): termina normal, con la traída como activa', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas);
      // Vuelve a anotar el paso "trayendo", como si el índice final no hubiera llegado a escribirse.
      final hecho = await leerIndiceCuentas(carpetas);
      File(p.join(carpetas.guardadas.path, 'indice.json')).writeAsStringSync(jsonEncode(IndiceCuentas(
        activa: ana,
        guardadas: [beto, ...hecho.guardadas],
        cambio: CambioPendiente(guardarComo: ana.id, traer: beto.id, paso: PasoCambio.trayendo),
      ).toJson()));
      await terminarCambioPendiente(carpetas);
      await _esLaCuentaDe('beto', usuario: 3);
      expect((await leerIndiceCuentas(carpetas)).activa!.id, beto.id);
    });

    test('la que se iba a traer desapareció (sin datos en su lugar): el lugar queda vacío, nunca a su nombre', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas, soloGuardar: true);
      carpetas.guardada(beto.id).deleteSync(recursive: true);
      await terminarCambioPendiente(carpetas);
      await _estaVacio();
      final indice = await leerIndiceCuentas(carpetas);
      expect(indice.activa, isNull);
      expect(indice.guardadas.map((g) => g.id), [ana.id], reason: 'Ana sigue guardada entera');
    });

    test('repetir el arranque cualquier cantidad de veces no cambia nada', () async {
      final beto = await guardarBetoYPonerAna();
      final ana = identificarActiva(await leerIndiceCuentas(carpetas), email: 'ana@x.com', nombre: null);
      await cambiarDeCuenta(actual: ana, destino: beto.id, carpetas: carpetas, soloGuardar: true);
      for (var i = 0; i < 3; i++) {
        await terminarCambioPendiente(carpetas);
      }
      await _esLaCuentaDe('beto', usuario: 3);
    });

    test('anotar la activa al entrar: queda con su negocio; un celular de una sola cuenta no gana índice', () async {
      const perfil = PerfilDeCuenta(email: 'ana@x.com', nombre: 'Ana', negocio: 1, sucursal: 2, nombreNegocio: 'Almacén');
      await anotarCuentaActiva(perfil: perfil, carpetas: carpetas);
      expect(carpetas.guardadas.existsSync(), isFalse);

      await guardarBetoYPonerAna();
      await anotarCuentaActiva(perfil: perfil, carpetas: carpetas);
      final activa = (await leerIndiceCuentas(carpetas)).activa!;
      expect([activa.email, activa.negocio, activa.nombreNegocio], ['ana@x.com', 1, 'Almacén']);
    });
  });

  group('cerrar sesión y borrar', () {
    test('con otras cuentas guardadas: borra solo la activa y trae la última usada', () async {
      await _ponerCuenta('beto', usuario: 3);
      await cambiarDeCuenta(actual: identificarActiva(IndiceCuentas.vacio, email: 'beto@x.com', nombre: null), destino: null, carpetas: carpetas);
      await _ponerCuenta('ana', usuario: 7);

      final quedo = await borrarTodoDelCelular(carpetas);
      expect(quedo!.email, 'beto@x.com');
      await _estaVacio();
      // Se trae al abrir de nuevo, como cualquier cambio.
      expect(await terminarCambioPendiente(carpetas), isTrue);
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
