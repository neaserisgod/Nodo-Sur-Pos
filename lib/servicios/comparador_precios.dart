// Comparador de precios vs. supermercados (Bruno, 2026-09-14: "una noción
// de los precios de mi local... para ajustarlos según si están muy caros o
// muy baratos"). Baja el ZIP diario de SEPA/Precios Claros
// (datos.produccion.gob.ar, Resolución 678/2020 — los supermercados
// grandes están obligados por ley a publicar precios todos los días),
// filtra a los comercios y sucursales de Bariloche que importan, y guarda
// el resultado en `precios_referencia_externa`.
//
// Se investigaron las tres páginas que Bruno pasó primero
// (carrefour.com.ar, laanonima.com.ar, todoatucasa.xrp.net) para
// scrapearlas directo: Carrefour prohíbe explícitamente en su
// `robots.txt` rastrear sus páginas de búsqueda, La Anónima bloquea bots
// con Cloudfront. SEPA es la fuente correcta para esas dos: legal,
// estructurada, identificada por código de barras (mismo dato que ya usa
// `Productos.codigoBarras`), sin nada que romper cuando un sitio cambia de
// diseño. Todo a tu Casa terminó teniendo su propia API pública (Bruno:
// "la última vez que scrapeé había una api expuesta") — ver
// `comparador_precios_todoatucasa.dart`, es una fuente aparte que
// comparte esta misma tabla (`precios_referencia_externa`, columna
// `fuente`) sin pisar lo que este archivo guarda.
//
// Única pieza con I/O de red de todo este módulo — `domain/` no se toca,
// esto no inventa ninguna fórmula de negocio, es una tabla de referencia
// externa. Se dispara sola desde `main.dart` (best-effort, silenciosa si
// falla), nunca bloquea el arranque — mismo criterio que
// `_iniciarServidorCompanion` y el chequeo de actualización de la
// companion (`actualizacion.dart`).
//
// Formato real del archivo (confirmado bajando uno el 2026-09-14, no hay
// diccionario público fácil de encontrar sin descargarlo): el ZIP
// nacional trae un ZIP interno por comercio
// (`sepa_N_comercio-sepa-<id>_...zip`), cada uno con comercio.csv /
// sucursales.csv / productos.csv separados por "|", UTF-8 con BOM. En
// productos.csv, `id_producto` es el EAN real — `productos_ean` NO lo es,
// es un flag 0/1 de si `id_producto` es un código válido. Sin ese "1", la
// fila entra igual (v29, "todo lo que esté en mi sistema") pero se cruza
// por `productos_descripcion` en vez de por código — mismo camino que un
// pesable sin barcode.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/normalizacion_texto.dart';
import '../data/repositorio_comparacion_precios.dart';

/// `id_comercio` de SEPA → nombre para mostrar. Confirmado bajando el
/// archivo real (2026-09-14): 2 = La Anónima, 10 = Carrefour (que agrupa
/// Hiper/Market/Express/Maxi bajo el mismo id_comercio, distintas
/// `id_bandera` — no filtramos por bandera, el nombre real de cada fila
/// sale de `comercio.csv`). Sumar un comercio nuevo es agregar una entrada
/// acá, nada más.
const _comerciosSeguidos = {'2', '10'};

const _diasSemana = [
  'lunes',
  'martes',
  'miercoles',
  'jueves',
  'viernes',
  'sabado',
  'domingo',
];

/// URLs reales de descarga (confirmadas bajando cada una, no adivinadas) —
/// el id del recurso es estable por día de la semana, el archivo detrás se
/// actualiza solo. `datos.produccion.gob.ar/dataset/sepa-precios`.
const _urlPorDia = {
  'lunes':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/0a9069a9-06e8-4f98-874d-da5578693290/download/sepa_lunes.zip',
  'martes':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/9dc06241-cc83-44f4-8e25-c9b1636b8bc8/download/sepa_martes.zip',
  'miercoles':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/1e92cd42-4f94-4071-a165-62c4cb2ce23c/download/sepa_miercoles.zip',
  'jueves':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/d076720f-a7f0-4af8-b1d6-1b99d5a90c14/download/sepa_jueves.zip',
  'viernes':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/91bc072a-4726-44a1-85ec-4a8467aad27e/download/sepa_viernes.zip',
  'sabado':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/b3c3da5d-213d-41e7-8d74-f23fda0a3c30/download/sepa_sabado.zip',
  'domingo':
      'https://datos.produccion.gob.ar/dataset/6f47ec76-d1ce-4e34-a7e1-621fe9b1d0b5/resource/f8e75128-515a-436e-bf8d-5c63a62f2005/download/sepa_domingo.zip',
};

String _urlDelDia(DateTime fecha) => _urlPorDia[_diasSemana[fecha.weekday - 1]]!;

/// Filtro de sucursal por localidad, no por `id_sucursal`: los ids no son
/// estables entre comercios ni están documentados en ningún lado; el
/// nombre de la localidad sí es legible y estable de un día a otro.
bool _esDeBariloche(String localidad) =>
    localidad.trim().toUpperCase().contains('BARILOCHE');

/// Una fila ya cruzada: a qué comercio corresponde + el precio de lista de
/// una sucursal puntual de Bariloche (antes de promediar entre sucursales
/// del mismo comercio). [ean] es `null` cuando `productos_ean` dice que
/// `id_producto` no es un código de barras real (Regla: no cruzar por un
/// código que el propio SEPA marca como no confiable) — en ese caso queda
/// para cruzarse por [nombre], igual que un pesable.
class _FilaEncontrada {
  final String? ean;
  final String comercio;
  final String nombre;
  final int precioCentavos;
  final int? precioReferenciaCentavos;
  final String? unidadReferencia;
  const _FilaEncontrada({
    required this.ean,
    required this.comercio,
    required this.nombre,
    required this.precioCentavos,
    this.precioReferenciaCentavos,
    this.unidadReferencia,
  });
}

/// Punto de entrada — se llama sola desde `main.dart`, sin esperarla, dentro
/// de un `try/catch` silencioso (mismo criterio que
/// `_iniciarServidorCompanion`). No hace nada si la última actualización
/// guardada tiene menos de 20 horas, para no re-bajar ~330MB en cada
/// arranque de la app — salvo que [forzar] sea `true` (el botón "Actualizar
/// ahora" de `PantallaCompararPrecios`, para probar o como respaldo si el
/// ciclo automático viene fallando en silencio hace días).
Future<void> actualizarComparacionPrecios(AppDatabase db, {bool forzar = false}) async {
  if (!forzar) {
    final ultima = await fechaUltimaActualizacionDeFuente(db, 'sepa');
    if (ultima != null && DateTime.now().difference(ultima) < const Duration(hours: 20)) {
      return;
    }
  }

  final zipNacional = await http
      .get(Uri.parse(_urlDelDia(DateTime.now())))
      .then((r) => r.bodyBytes);

  await actualizarComparacionPreciosDesdeZip(db, zipNacional);
}

/// El procesamiento real, separado de la descarga (`actualizarComparacionPrecios`)
/// para poder probarlo con un ZIP ya en memoria — una muestra fabricada en
/// test (`test/servicios/comparador_precios_test.dart`) o un archivo real
/// bajado a mano — sin depender de la red ni del chequeo de "menos de 20
/// horas".
Future<void> actualizarComparacionPreciosDesdeZip(
  AppDatabase db,
  Uint8List zipNacional,
) async {
  final filas = _extraerFilasDeBariloche(zipNacional);
  await _guardarPreciosReferencia(db, filas);
}

/// Recorre el ZIP nacional, entra solo a los ZIPs internos de
/// [_comerciosSeguidos], y de ahí solo a las filas de `productos.csv` cuya
/// sucursal está en Bariloche. Todo lo demás (otros comercios, otras
/// provincias) nunca se decodifica — es la parte cara de esta función, y
/// evitarla es lo que hace viable correr esto en segundo plano.
List<_FilaEncontrada> _extraerFilasDeBariloche(Uint8List zipNacional) {
  final resultado = <_FilaEncontrada>[];
  final outer = ZipDecoder().decodeBytes(zipNacional, verify: false);

  for (final entry in outer.files) {
    if (!entry.isFile || !entry.name.endsWith('.zip')) continue;
    final match = RegExp(r'comercio-sepa-(\d+)').firstMatch(entry.name);
    if (match == null || !_comerciosSeguidos.contains(match.group(1))) continue;

    final inner = ZipDecoder().decodeBytes(entry.content, verify: false);
    resultado.addAll(_filasDeUnComercio(inner));
  }
  return resultado;
}

List<_FilaEncontrada> _filasDeUnComercio(Archive inner) {
  final comercioCsv = _contenidoTexto(inner, 'comercio.csv');
  final sucursalesCsv = _contenidoTexto(inner, 'sucursales.csv');
  final productosCsv = _contenidoTexto(inner, 'productos.csv');
  if (comercioCsv == null || sucursalesCsv == null || productosCsv == null) {
    return const [];
  }

  // id_bandera -> comercio_bandera_nombre ("La Anonima", "Hipermercado
  // Carrefour", etc. — un mismo id_comercio puede traer varias banderas).
  final banderas = _filasConEncabezado(comercioCsv);
  final nombrePorBandera = {
    for (final fila in banderas) fila['id_bandera']: fila['comercio_bandera_nombre'],
  };

  // id_sucursal -> es de Bariloche.
  final sucursales = _filasConEncabezado(sucursalesCsv);
  final sucursalesBariloche = {
    for (final fila in sucursales)
      if (_esDeBariloche(fila['sucursales_localidad'] ?? '')) fila['id_sucursal'],
  };
  if (sucursalesBariloche.isEmpty) return const [];

  final resultado = <_FilaEncontrada>[];
  for (final fila in _filasConEncabezado(productosCsv)) {
    if (!sucursalesBariloche.contains(fila['id_sucursal'])) continue;
    final precioTexto = fila['productos_precio_lista'];
    final nombreComercio = nombrePorBandera[fila['id_bandera']];
    final nombre = fila['productos_descripcion'];
    if (precioTexto == null || nombreComercio == null || nombre == null || nombre.isEmpty) {
      continue;
    }
    final precioCentavos = _centavosDesdeTexto(precioTexto);
    if (precioCentavos == null) continue;

    // `productos_ean` es un flag 0/1 (ver comentario de cabecera): sin
    // "1" ahí, `id_producto` es un código interno del comercio, no un EAN
    // real — cruzarlo igual por código arriesga un falso positivo (dos
    // comercios usando el mismo código interno por casualidad). En ese
    // caso el producto solo entra por nombre, como un pesable.
    final esEanValido = fila['productos_ean'] == '1';
    final ean = esEanValido ? fila['id_producto'] : null;

    resultado.add(
      _FilaEncontrada(
        ean: (ean == null || ean.isEmpty) ? null : ean,
        comercio: nombreComercio,
        nombre: nombre,
        precioCentavos: precioCentavos,
        precioReferenciaCentavos: _centavosDesdeTexto(fila['productos_precio_referencia'] ?? ''),
        unidadReferencia: fila['productos_unidad_medida_referencia'],
      ),
    );
  }
  return resultado;
}

String? _contenidoTexto(Archive archivo, String nombre) {
  final entry = archivo.files.where((f) => f.name == nombre).firstOrNull;
  if (entry == null) return null;
  return utf8.decode(entry.content);
}

/// SEPA separa con "|", UTF-8 con BOM en la primera columna del
/// encabezado. Se parsea a mano (no con el paquete `csv` que ya usa
/// `importacion_csv.dart`) porque productos.csv puede pesar ~400MB sin
/// comprimir en un comercio grande — decodificarlo entero a una lista de
/// listas duplicaría esa memoria por las dudas; línea por línea alcanza,
/// el formato no trae campos entre comillas que puedan contener "|".
List<Map<String, String>> _filasConEncabezado(String contenido) {
  final limpio = contenido.startsWith('﻿') ? contenido.substring(1) : contenido;
  final lineas = const LineSplitter().convert(limpio);
  if (lineas.isEmpty) return const [];

  final encabezado = lineas.first.split('|');
  final filas = <Map<String, String>>[];
  for (var i = 1; i < lineas.length; i++) {
    final linea = lineas[i];
    if (linea.trim().isEmpty) continue;
    final valores = linea.split('|');
    if (valores.length < encabezado.length) continue; // pie del archivo ("Última actualización: ...")
    filas.add({for (var c = 0; c < encabezado.length; c++) encabezado[c]: valores[c]});
  }
  return filas;
}

/// SEPA usa formato "3050.00" (punto decimal, sin separador de miles) — no
/// es el formato argentino que parsea `parsearARS` (lib/domain/dinero.dart,
/// "1.500,50"), es un formato distinto de una fuente distinta.
int? _centavosDesdeTexto(String texto) {
  final valor = double.tryParse(texto.trim());
  if (valor == null) return null;
  return (valor * 100).round();
}

/// Promedia entre sucursales de Bariloche del mismo comercio para el mismo
/// producto (Bruno tiene 5 de La Anónima solas) en vez de quedarse con la
/// primera que aparezca, y delega el guardado real a
/// `reemplazarPreciosReferencia` (`repositorio_comparacion_precios.dart`,
/// compartida con `comparador_precios_todoatucasa.dart`) — esta fuente
/// nunca pisa las filas de la otra. Agrupa por EAN cuando hay uno válido,
/// si no por nombre normalizado (mismo criterio de búsqueda que el resto
/// de la app, `normalizarTexto`) — así un pesable sin código también
/// promedia entre sus sucursales en vez de guardar cinco filas sueltas.
Future<void> _guardarPreciosReferencia(AppDatabase db, List<_FilaEncontrada> filas) async {
  final acumulado = <(String, String), List<_FilaEncontrada>>{};
  for (final fila in filas) {
    final clave = fila.ean != null ? 'ean:${fila.ean}' : 'nombre:${normalizarTexto(fila.nombre)}';
    acumulado.putIfAbsent((clave, fila.comercio), () => []).add(fila);
  }

  int promedio(Iterable<int> valores) {
    final lista = valores.toList();
    return lista.reduce((a, b) => a + b) ~/ lista.length;
  }

  final aGuardar = [
    for (final grupo in acumulado.values)
      PrecioReferenciaFila(
        codigoBarras: grupo.first.ean ?? '',
        comercio: grupo.first.comercio,
        nombreProducto: grupo.first.nombre,
        precioCentavos: promedio(grupo.map((f) => f.precioCentavos)),
        precioReferenciaCentavos: grupo.any((f) => f.precioReferenciaCentavos != null)
            ? promedio(
                grupo.where((f) => f.precioReferenciaCentavos != null).map((f) => f.precioReferenciaCentavos!),
              )
            : null,
        unidadReferencia: grupo.firstWhere((f) => f.unidadReferencia != null, orElse: () => grupo.first).unidadReferencia,
      ),
  ];
  await reemplazarPreciosReferencia(db, fuente: 'sepa', filas: aGuardar);
}
