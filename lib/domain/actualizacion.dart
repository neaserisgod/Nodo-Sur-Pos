// Reglas puras del sistema de actualización: qué versión tiene la app, cómo
// se compara contra el feed y cuándo corresponde avisar. Sin Flutter, sin
// red y sin disco — la parte con I/O vive en `servicios/actualizaciones.dart`.

/// Servidor de actualizaciones (Cloudflare, sitio horsepos.com).
const String _hostFeed = 'horsepos.com';
const String _rutaFeed = '/api/update/appcast.xml';

/// Cuánto se silencia el aviso cuando se elige "más tarde".
const Duration postergacionAviso = Duration(hours: 4);

/// Nombre y build de la app a partir de lo que devuelve `PackageInfo`.
///
/// `package_info_plus` en Windows parte `ProductVersion` por '+'. Como ese
/// campo tiene que ser "1.0.0.2098" (con puntos, ver [versionParaFeed]),
/// devuelve todo junto en `version` y el build vacío: se vuelve a separar
/// acá, en un solo lugar, para que lo que hoy se muestra y se compara como
/// "1.0.0+2098" (Configuración, la companion) siga igual.
({String nombre, String build}) separarVersion(String version, String buildNumber) {
  if (buildNumber.isNotEmpty) return (nombre: version, build: buildNumber);
  if (version.contains('+')) {
    final partes = version.split('+');
    return (nombre: partes.first, build: partes.sublist(1).join('+'));
  }
  final segmentos = version.split('.');
  if (segmentos.length == 4) {
    return (nombre: segmentos.take(3).join('.'), build: segmentos.last);
  }
  return (nombre: version, build: '');
}

/// Versión como la ve el feed: nombre.build con puntos ("1.0.0.2098").
///
/// Tiene que ser EXACTAMENTE el mismo formato que `ProductVersion` del .exe
/// (`windows/runner/Runner.rc`) y que el `sparkle:version` del servidor: con
/// "1.0.0+2098" en el .exe, WinSparkle veía siempre un feed más nuevo y
/// ofrecía actualizar en bucle (spike 2026-09-30, `DECISIONES.md`).
String versionParaFeed(String nombre, String build) =>
    build.isEmpty ? nombre : '$nombre.$build';

/// Compara dos versiones segmento a segmento como números (10000 > 9999);
/// lo que falta vale cero. Devuelve negativo, cero o positivo. El '+' y el
/// '.' separan igual: "1.0.0+2098" == "1.0.0.2098".
int compararVersiones(String a, String b) {
  final segmentosA = _segmentos(a);
  final segmentosB = _segmentos(b);
  final largo = segmentosA.length > segmentosB.length ? segmentosA.length : segmentosB.length;
  for (var i = 0; i < largo; i++) {
    final x = i < segmentosA.length ? segmentosA[i] : 0;
    final y = i < segmentosB.length ? segmentosB[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _segmentos(String version) => [
  for (final parte in version.trim().split(RegExp(r'[^0-9]+')))
    if (parte.isNotEmpty) int.parse(parte),
];

final RegExp _versionComoAtributo = RegExp(r'sparkle:version\s*=\s*"([^"]+)"');
final RegExp _versionComoElemento = RegExp(r'<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>');

/// La versión más alta que anuncia el feed, o null si no trae ninguna (feed
/// vacío, una página de error del proxy, etc.).
String? versionMasNuevaDelFeed(String xml) {
  String? mejor;
  final encontradas = [
    ..._versionComoAtributo.allMatches(xml).map((m) => m.group(1)!),
    ..._versionComoElemento.allMatches(xml).map((m) => m.group(1)!),
  ];
  for (final version in encontradas) {
    if (_segmentos(version).isEmpty) continue;
    if (mejor == null || compararVersiones(version, mejor) > 0) mejor = version;
  }
  return mejor;
}

/// Hay actualización solo si el feed es ESTRICTAMENTE mayor: mismo build
/// significa "estás al día".
bool hayActualizacion({required String versionActual, required String xmlFeed}) {
  final nueva = versionMasNuevaDelFeed(xmlFeed);
  return nueva != null && compararVersiones(nueva, versionActual) > 0;
}

/// URL del feed. `cid` es un id aleatorio que la app genera una sola vez;
/// el servidor lo usa para repartir el despliegue gradual.
String urlFeedActualizaciones({
  required String idCliente,
  String plataforma = 'windows',
  String canal = 'stable',
}) => Uri(
  scheme: 'https',
  host: _hostFeed,
  path: _rutaFeed,
  queryParameters: {'platform': plataforma, 'channel': canal, 'cid': idCliente},
).toString();

enum AvisoActualizacion { ninguno, mostrar }

/// Cuándo se muestra el aviso "Hay una actualización". Regla de el dueño
/// (2026-09-30): nada mientras haya una venta abierta — la pantalla de
/// mostrador con gente esperando no se interrumpe por una actualización —,
/// y nunca se instala sola: solo se avisa, y el que cobra elige.
AvisoActualizacion decidirAviso({
  required bool hayActualizacion,
  required bool hayVentaAbierta,
  DateTime? postergadaHasta,
  required DateTime ahora,
}) {
  if (!hayActualizacion || hayVentaAbierta) return AvisoActualizacion.ninguno;
  if (postergadaHasta != null && ahora.isBefore(postergadaHasta)) {
    return AvisoActualizacion.ninguno;
  }
  return AvisoActualizacion.mostrar;
}
