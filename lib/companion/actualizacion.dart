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
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/actualizacion.dart' show consultaDelCelular;
import '../edicion.dart';
import '../servicios/actualizaciones.dart' show idClienteActualizaciones;
import '../servicios/almacenes_del_equipo.dart';
import '../servicios/cuenta_nube.dart' show ClienteNube;
import 'cliente_companion.dart';
import '../plataforma.dart';

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

// --- Beta o Estable (El dueño, 2026-10-14: "que todas las apps móvil puedan descargar beta o release") -------------------

/// La elección de ESTE celular (es del aparato: no cambia al pasar de negocio). Solo cuenta si [celularDePruebas].
const claveCanalBetaCelular = 'actualizaciones_beta';

/// Lo último que dijo el sitio: si la cuenta de este celular es de pruebas (administrador o eximida) y puede elegir Beta.
/// Es de la cuenta: viaja con ella al cambiar de negocio.
const _claveDePruebas = 'companion_cuenta_de_pruebas';

final ValueNotifier<bool> celularEligeBeta = ValueNotifier(false);
final ValueNotifier<bool> celularDePruebas = ValueNotifier(false);

Future<void> cargarCanalCelular() async {
  final prefs = await SharedPreferences.getInstance();
  celularEligeBeta.value = prefs.getBool(claveCanalBetaCelular) ?? false;
  celularDePruebas.value = prefs.getBool(_claveDePruebas) ?? false;
}

Future<void> elegirBetaEnElCelular(bool beta) async {
  celularEligeBeta.value = beta;
  await (await SharedPreferences.getInstance()).setBool(claveCanalBetaCelular, beta);
}

/// Le avisa al sitio que este celular existe, con su id de instalación: así el sitio lo reconoce en el feed y le contesta si
/// la cuenta es de pruebas. Sin cuenta vinculada o sin red queda lo último que se supo. Si el sitio manda un token renovado,
/// se guarda (como la PC).
Future<void> avisarAlSitio(String version) async {
  try {
    final almacen = await almacenCuentaDelEquipo();
    final cuenta = await almacen.leer();
    if (cuenta == null) {
      celularDePruebas.value = false;
      return;
    }
    final r = await ClienteNube(http: http.Client())
        .avisar(cuenta.token, cid: await idClienteActualizaciones(), version: version, sistema: nombreDelSistema);
    if (r.tokenNuevo != null) await almacen.guardar(cuenta.conToken(r.tokenNuevo!));
    celularDePruebas.value = r.canal == 'beta';
    await (await SharedPreferences.getInstance()).setBool(_claveDePruebas, celularDePruebas.value);
  } catch (_) {
    // Sin red: queda lo último que se supo.
  }
}

/// Pregunta al sitio si hay un APK más nuevo que [versionPropia]
/// ("1.0.0+2098"). Devuelve null si no hay. Tira si el sitio no responde:
/// quien llama decide el plan B (la PC emparejada).
///
/// Con el id de instalación ([idCliente]) el sitio reparte el despliegue gradual y reconoce un celular de pruebas; el canal
/// sale de [consultaDelCelular].
Future<OfertaSitio?> consultarSitio(
  String versionPropia, {
  http.Client? cliente,
  String? idCliente,
  bool dePruebas = false,
  bool eligeBeta = false,
}) async {
  final c = cliente ?? http.Client();
  try {
    final r = await c
        .get(
          Uri.https(
            hostActualizaciones,
            '/api/update/latest.json',
            consultaDelCelular(
              plataforma: plataformaActualizacion,
              version: versionPropia,
              idCliente: idCliente,
              dePruebas: dePruebas,
              eligeBeta: eligeBeta,
            ),
          ),
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
  // Solo del sitio de Nodo Sur: la oferta trae la dirección Y el hash del mismo lugar, así que si la dirección pudiera apuntar a
  // cualquier host, quien controlara la respuesta controlaría también el hash y el APK. Y el hash tiene que ser un SHA-256 de verdad.
  if (url == null || !url.isScheme('https') || url.host != hostActualizaciones || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
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
    await avisarAlSitio(propiaTexto);
    final oferta = await consultarSitio(
      propiaTexto,
      idCliente: await idClienteActualizaciones(),
      dePruebas: celularDePruebas.value,
      eligeBeta: celularEligeBeta.value,
    );
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
  // Nodo Sur Servicios no tiene PC, y la PC ofrece el APK de la otra edición.
  if (cliente == null || esEdicionAparte) throw const HttpException('Sin conexión al sitio ni a la PC');
  final delServidor = await cliente.versionServidor();
  return EstadoActualizacion(
    hayActualizacion: propiaTexto != delServidor,
    diagnostico: 'Celular: $propiaTexto · PC: $delServidor',
  );
}

/// Descarga el .apk (del sitio, verificando su hash, o de la PC) a un archivo temporal, sin instalarlo todavía: la hoja
/// de actualización muestra "Lista para instalar" entre una cosa y la otra.
Future<File> descargarActualizacion(
  ClienteCompanion? cliente, {
  OfertaSitio? oferta,
}) async {
  final List<int> bytes;
  if (oferta != null) {
    final r = await http.get(oferta.url).timeout(const Duration(minutes: 10));
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
  return archivo;
}

/// Le pide a Android que instale el .apk descargado — abre el instalador del sistema, la instalación en sí la
/// confirma la persona (Android nunca deja instalar en silencio).
Future<void> instalarActualizacion(File archivo) async {
  await OpenFilex.open(archivo.path);
}

/// Las dos cosas juntas.
Future<void> descargarEInstalarActualizacion(
  ClienteCompanion? cliente, {
  OfertaSitio? oferta,
}) async => instalarActualizacion(await descargarActualizacion(cliente, oferta: oferta));
