// Registro de errores a archivo (Fase 0.15): hasta acá un fallo solo salía por `debugPrint`, que en la PC del local no lo ve
// nadie. Queda en `<datos de la app>/logs/errores.log`, rotado al pasar de 512 KB, para poder pedir "mandame el archivo".

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _tamanioMaximoBytes = 512 * 1024;

/// Carpeta de logs; los tests la reemplazan para no tocar la real.
Directory? carpetaDeLogsParaPruebas;

Future<File> _archivo() async {
  final carpeta = carpetaDeLogsParaPruebas ??
      Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));
  await carpeta.create(recursive: true);
  return File(p.join(carpeta.path, 'errores.log'));
}

/// Anota [error] con su [contexto] (qué se estaba haciendo). Nunca lanza: registrar un error no puede causar otro.
Future<void> registrarError(String contexto, Object error, [StackTrace? pila]) async {
  debugPrint('$contexto: $error');
  try {
    final archivo = await _archivo();
    if (await archivo.exists() && await archivo.length() > _tamanioMaximoBytes) {
      final vieja = File('${archivo.path}.1');
      if (await vieja.exists()) await vieja.delete();
      await archivo.rename(vieja.path);
    }
    final linea = '${DateTime.now().toIso8601String()}  $contexto\n$error\n${pila ?? ''}\n---\n';
    await archivo.writeAsString(linea, mode: FileMode.append, flush: true);
  } catch (_) {
    // Sin disco o sin permisos: ya salió por la consola, no hay nada más que hacer.
  }
}

/// Engancha los tres lugares por donde se escapa un error en Flutter. Se llama una vez, al arrancar.
void instalarRegistroDeErrores() {
  final anterior = FlutterError.onError;
  FlutterError.onError = (detalles) {
    anterior?.call(detalles);
    registrarError('Error de Flutter', detalles.exception, detalles.stack);
  };
  PlatformDispatcher.instance.onError = (error, pila) {
    registrarError('Error sin capturar', error, pila);
    return true;
  };
}
