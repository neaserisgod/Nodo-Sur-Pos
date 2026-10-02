import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/migracion_carpeta_datos.dart';
import 'package:path/path.dart' as p;

// Con `test` y no `testWidgets`: dart:io real no se lleva con el reloj falso de testWidgets (ver TRAMPAS.md).
void main() {
  late Directory raiz;
  late Directory vieja;
  late Directory nueva;

  setUp(() async {
    // Misma forma que en Windows: %APPDATA%\com.laplazoleta\<nombre del producto>
    raiz = await Directory.systemTemp.createTemp('migracion_datos_');
    final empresa = Directory(p.join(raiz.path, 'com.laplazoleta'))..createSync();
    vieja = Directory(p.join(empresa.path, 'la_plazoleta'));
    nueva = Directory(p.join(empresa.path, 'Nodo Sur POS'));
  });
  tearDown(() async => raiz.delete(recursive: true));

  void escribir(Directory d, String nombre, String contenido) {
    d.createSync(recursive: true);
    File(p.join(d.path, nombre)).writeAsStringSync(contenido);
  }

  String leer(Directory d, String nombre) => File(p.join(d.path, nombre)).readAsStringSync();
  bool existe(Directory d, String nombre) => File(p.join(d.path, nombre)).existsSync();
  Map<String, dynamic> prefs(Directory d) => jsonDecode(leer(d, 'shared_preferences.json')) as Map<String, dynamic>;

  test('trae la cuenta vinculada, el estado de la sync y las preferencias de la carpeta vieja a la nueva', () async {
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"abc"}');
    escribir(vieja, 'nodosur_sync.json', '{"cursor":7}');
    escribir(vieja, 'shared_preferences.json', '{"flutter.objetivo_venta_centavos":500000}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r.huboCarpetaVieja, isTrue);
    expect(r.archivosTraidos, unorderedEquals(['nodosur_cuenta.json', 'nodosur_sync.json', 'shared_preferences.json']));
    expect(leer(nueva, 'nodosur_cuenta.json'), '{"token":"abc"}');
    expect(leer(nueva, 'nodosur_sync.json'), '{"cursor":7}');
    expect(prefs(nueva), {'flutter.objetivo_venta_centavos': 500000});
  });

  test('si la persona ya volvió a vincular en la carpeta nueva, NO se le pisa esa cuenta con la vieja', () async {
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"viejo"}');
    escribir(nueva, 'nodosur_cuenta.json', '{"token":"nuevo"}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(leer(nueva, 'nodosur_cuenta.json'), '{"token":"nuevo"}');
    expect(r.archivosTraidos, isNot(contains('nodosur_cuenta.json')));
  });

  test('las preferencias se mezclan: lo que falta en la nueva se agrega y lo que ya hay en la nueva gana', () async {
    escribir(vieja, 'shared_preferences.json', '{"a":1,"b":2}');
    escribir(nueva, 'shared_preferences.json', '{"b":9,"c":3}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(prefs(nueva), {'a': 1, 'b': 9, 'c': 3});
    expect(r.archivosTraidos, ['shared_preferences.json']);
  });

  test('si las preferencias nuevas ya tenían todo lo de las viejas, no reescribe nada', () async {
    escribir(vieja, 'shared_preferences.json', '{"a":1}');
    escribir(nueva, 'shared_preferences.json', '{"a":5,"c":3}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r.archivosTraidos, isEmpty);
    expect(prefs(nueva), {'a': 5, 'c': 3});
  });

  test('es idempotente: correrla dos veces deja lo mismo y la segunda no trae nada', () async {
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"abc"}');
    escribir(vieja, 'shared_preferences.json', '{"a":1}');
    await migrarCarpetaDatosVieja(nueva: nueva);
    final antes = leer(nueva, 'nodosur_cuenta.json');
    final r2 = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r2.archivosTraidos, isEmpty);
    expect(leer(nueva, 'nodosur_cuenta.json'), antes);
  });

  test('nunca borra nada de la carpeta vieja: queda como respaldo', () async {
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"abc"}');
    await migrarCarpetaDatosVieja(nueva: nueva);
    expect(leer(vieja, 'nodosur_cuenta.json'), '{"token":"abc"}');
  });

  test('sin carpeta vieja (instalación nueva) no hace nada ni crea carpetas', () async {
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r.huboCarpetaVieja, isFalse);
    expect(r.archivosTraidos, isEmpty);
    expect(nueva.existsSync(), isFalse);
  });

  test('una carpeta vieja sin ninguno de esos archivos no deja la nueva a medias', () async {
    escribir(vieja, 'otra_cosa.txt', 'x');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r.archivosTraidos, isEmpty);
    expect(existe(nueva, 'nodosur_cuenta.json'), isFalse);
  });

  test('un archivo roto en la carpeta vieja no impide traer los demás ni tira una excepción', () async {
    escribir(vieja, 'shared_preferences.json', '{esto no es json');
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"abc"}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva);
    expect(r.archivosTraidos, ['nodosur_cuenta.json']);
    expect(r.fallos, hasLength(1));
    expect(r.fallos.single, contains('shared_preferences.json'));
  });

  test('si la carpeta nueva se llamara igual que la vieja no hace nada', () async {
    escribir(vieja, 'nodosur_cuenta.json', '{"token":"abc"}');
    final r = await migrarCarpetaDatosVieja(nueva: vieja);
    expect(r.huboCarpetaVieja, isFalse);
    expect(r.archivosTraidos, isEmpty);
  });

  test('el nombre de la carpeta vieja se puede indicar', () async {
    final otra = Directory(p.join(raiz.path, 'com.laplazoleta', 'otro_nombre'));
    escribir(otra, 'nodosur_cuenta.json', '{"token":"x"}');
    final r = await migrarCarpetaDatosVieja(nueva: nueva, nombreViejo: 'otro_nombre');
    expect(r.archivosTraidos, ['nodosur_cuenta.json']);
  });
}
