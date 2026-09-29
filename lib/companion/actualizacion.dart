// Sistema de actualización de la companion app (2026-09-07, Bruno: "para
// poder probar sin tener que pasar la apk a cada rato"): la PC ofrece su
// propio .apk empaquetado como asset (`servidor_companion.dart`), el
// celular lo descarga y le pide a Android que lo instale — sin depender de
// ninguna tienda de apps ni de que alguien copie el archivo a mano.

import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'cliente_companion.dart';

class EstadoActualizacion {
  final bool hayActualizacion;

  /// Texto para mostrar tal cual en pantalla — a propósito nunca se
  /// esconde, ni en el caso de "está todo bien" ni en el de error (Bruno,
  /// 2026-09-07: "no salió nada" — el chequeo fallaba en silencio y no
  /// había forma de saber si era "misma versión" o "no se pudo conectar").
  final String diagnostico;

  const EstadoActualizacion({
    required this.hayActualizacion,
    required this.diagnostico,
  });
}

/// Compara la versión propia contra la que ofrece la PC — son distintas
/// (más nueva, más vieja, no importa: alguna de las dos está desactualizada
/// respecto de la otra, así que conviene igualarlas) si los dos textos no
/// coinciden.
Future<EstadoActualizacion> revisarActualizacion(
  ClienteCompanion cliente,
) async {
  final propia = await PackageInfo.fromPlatform();
  final propiaTexto = '${propia.version}+${propia.buildNumber}';
  final delServidor = await cliente.versionServidor();
  return EstadoActualizacion(
    hayActualizacion: propiaTexto != delServidor,
    diagnostico: 'Celular: $propiaTexto · PC: $delServidor',
  );
}

/// Descarga el .apk que ofrece la PC a un archivo temporal y le pide a
/// Android que lo instale — abre el instalador del sistema, la instalación
/// en sí la confirma la persona (Android nunca deja instalar en silencio).
Future<void> descargarEInstalarActualizacion(ClienteCompanion cliente) async {
  final bytes = await cliente.descargarApk();
  final carpeta = await getTemporaryDirectory();
  final archivo = File(
    '${carpeta.path}/la_plazoleta_companion_actualizacion.apk',
  );
  await archivo.writeAsBytes(bytes);
  await OpenFilex.open(archivo.path);
}
