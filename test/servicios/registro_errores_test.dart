import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/registro_errores.dart';

void main() {
  late Directory carpeta;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('log_errores');
    carpetaDeLogsParaPruebas = carpeta;
  });
  tearDown(() {
    carpetaDeLogsParaPruebas = null;
    carpeta.deleteSync(recursive: true);
  });

  test('deja el error con su contexto en el archivo', () async {
    await registrarError('Cobrando', StateError('se rompió'), StackTrace.current);

    final texto = File('${carpeta.path}/errores.log').readAsStringSync();
    expect(texto, contains('Cobrando'));
    expect(texto, contains('se rompió'));
  });

  test('pasado el límite rota el archivo en vez de crecer sin fin', () async {
    final archivo = File('${carpeta.path}/errores.log')..writeAsStringSync('x' * (600 * 1024));

    await registrarError('Nuevo', 'otro error');

    expect(File('${carpeta.path}/errores.log.1').existsSync(), isTrue);
    expect(archivo.readAsStringSync(), contains('otro error'));
    expect(archivo.lengthSync(), lessThan(1024));
  });
}
