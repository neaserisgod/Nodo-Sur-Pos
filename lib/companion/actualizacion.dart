// Sistema de actualización de la companion app (2026-09-07, el dueño: "para
// poder probar sin tener que pasar la apk a cada rato"): la PC ofrece su
// propio .apk empaquetado como asset (`servidor_companion.dart`), el
// celular lo descarga y le pide a Android que lo instale — sin depender de
// ninguna tienda de apps ni de que alguien copie el archivo a mano.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'cliente_companion.dart';

/// Servidor de actualizaciones (el mismo sitio que usa la app de escritorio).
const String hostActualizaciones = 'horsepos.com';

/// Una versión del APK publicada en el sitio (workflow `publicar-apk`).
class OfertaSitio {
  final String version;
  final Uri url;
  final String sha256;

  const OfertaSitio({
    required this.version,
    required this.url,
    required this.sha256,
  });
}

/// Pregunta al sitio si hay un APK más nuevo que [versionPropia]
/// ("1.0.0+2098"). Devuelve null si no hay. Tira si el sitio no responde:
/// quien llama decide el plan B (la PC emparejada).
///
/// Canal estable y sin `cid`: el celular no tiene identificador de
/// instalación, así que solo ve versiones liberadas al 100 % — a propósito,
/// el reparto gradual de una beta no se puede decidir sin identidad.
Future<OfertaSitio?> consultarSitio(
  String versionPropia, {
  http.Client? cliente,
}) async {
  final c = cliente ?? http.Client();
  try {
    final r = await c
        .get(
          Uri.https(hostActualizaciones, '/api/update/latest.json', {
            'platform': 'android',
            'channel': 'stable',
            'version': versionPropia,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw HttpException('El sitio respondió ${r.statusCode}');
    }
    return ofertaDeRespuesta(r.body);
  } finally {
    if (cliente == null) c.close();
  }
}

/// Lee la respuesta de `latest.json`. Separado de la red para poder probarlo.
OfertaSitio? ofertaDeRespuesta(String cuerpo) {
  final j = jsonDecode(cuerpo);
  if (j is! Map || j['update'] != true) return null;
  final url = Uri.tryParse('${j['url']}');
  final sha = '${j['sha256']}'.toLowerCase();
  if (url == null || !url.isScheme('https') || sha.length != 64) return null;
  return OfertaSitio(version: '${j['version']}', url: url, sha256: sha);
}

class EstadoActualizacion {
  final bool hayActualizacion;

  /// Si la actualización sale del sitio (no de la PC), la oferta concreta.
  final OfertaSitio? oferta;

  /// Texto para mostrar tal cual en pantalla — a propósito nunca se
  /// esconde, ni en el caso de "está todo bien" ni en el de error (El dueño,
  /// 2026-09-07: "no salió nada" — el chequeo fallaba en silencio y no
  /// había forma de saber si era "misma versión" o "no se pudo conectar").
  final String diagnostico;

  const EstadoActualizacion({
    required this.hayActualizacion,
    required this.diagnostico,
    this.oferta,
  });
}

/// Compara la versión propia contra la que ofrece la PC — son distintas
/// (más nueva, más vieja, no importa: alguna de las dos está desactualizada
/// respecto de la otra, así que conviene igualarlas) si los dos textos no
/// coinciden.
Future<EstadoActualizacion> revisarActualizacion(
  ClienteCompanion? cliente,
) async {
  final propia = await PackageInfo.fromPlatform();
  final propiaTexto = '${propia.version}+${propia.buildNumber}';
  // Primero el sitio: no depende de que la PC esté prendida ni de que el
  // celular esté en su red. Sin internet, plan B: la PC emparejada.
  try {
    final oferta = await consultarSitio(propiaTexto);
    return EstadoActualizacion(
      hayActualizacion: oferta != null,
      oferta: oferta,
      diagnostico: oferta == null
          ? 'Celular: $propiaTexto · al día'
          : 'Celular: $propiaTexto · disponible: ${oferta.version}',
    );
  } catch (_) {
    // sigue con la PC
  }
  if (cliente == null) throw const HttpException('Sin conexión al sitio ni a la PC');
  final delServidor = await cliente.versionServidor();
  return EstadoActualizacion(
    hayActualizacion: propiaTexto != delServidor,
    diagnostico: 'Celular: $propiaTexto · PC: $delServidor',
  );
}

/// Descarga el .apk que ofrece la PC a un archivo temporal y le pide a
/// Android que lo instale — abre el instalador del sistema, la instalación
/// en sí la confirma la persona (Android nunca deja instalar en silencio).
Future<void> descargarEInstalarActualizacion(
  ClienteCompanion? cliente, {
  OfertaSitio? oferta,
}) async {
  final List<int> bytes;
  if (oferta != null) {
    final r = await http.get(oferta.url);
    if (r.statusCode != 200) {
      throw HttpException('El sitio respondió ${r.statusCode}');
    }
    // Sin firma propia en el APK, la integridad la da el hash que registró
    // el CI: si no coincide (descarga cortada o archivo cambiado), no se
    // le pasa nada a Android.
    if (sha256.convert(r.bodyBytes).toString() != oferta.sha256) {
      throw const HttpException('El archivo descargado no coincide con el publicado');
    }
    bytes = r.bodyBytes;
  } else {
    bytes = await cliente!.descargarApk();
  }
  final carpeta = await getTemporaryDirectory();
  final archivo = File(
    '${carpeta.path}/la_plazoleta_companion_actualizacion.apk',
  );
  await archivo.writeAsBytes(bytes);
  await OpenFilex.open(archivo.path);
}
