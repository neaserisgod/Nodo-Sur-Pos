import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
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

  test('registrarSiNoEsDeRed: la falta de internet no se anota, un error de verdad sí', () async {
    for (final red in <Object>[const SocketException('sin red'), TimeoutException('lento'), http.ClientException('cortado'), const ErrorNube('sin_red', 'No hay conexión')]) {
      expect(esFallaDeRed(red), isTrue);
      await registrarSiNoEsDeRed('Sin red', red);
    }
    expect(File('${carpeta.path}/errores.log').existsSync(), isFalse, reason: 'estar sin internet es lo normal en un local');

    expect(esFallaDeRed(StateError('x')), isFalse);
    expect(esFallaDeRed(const ErrorNube('mp_error', 'Mercado Pago falló')), isFalse, reason: 'un error del sitio no es falta de red');
    await registrarSiNoEsDeRed('Con error', StateError('token roto'));
    expect(File('${carpeta.path}/errores.log').readAsStringSync(), allOf(contains('Con error'), contains('token roto')));
  });
}
