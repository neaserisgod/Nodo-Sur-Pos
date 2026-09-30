// Comparador de precios — Todo a tu Casa (El dueño, 2026-09-14: "si hay
// publico, revisa, la ultima vez que scrapee habia una api expuesta").
//
// Confirmado: `todoatucasa.xrp.net` corre sobre una plataforma llamada
// "XRP" (de ahí el dominio) que expone un catálogo público vía
// `https://api.xrp.net/v2/Products/`. Las credenciales de acá abajo NO son
// nada obtenido de forma indebida — son las mismas que ya vienen
// hardcodeadas en el JavaScript público que el sitio le manda a
// CUALQUIER visitante (`/lib/js/Connection.js`, `party-id-from` inline en
// el HTML de `/main.asp`): el usuario por default de esa API es
// "Invitado", no hace falta cuenta ni login para navegar el catálogo. El
// intento anterior de leer `/main.asp` con `curl` sin persistir cookies
// caía en un loop de sesión de ASP clásico (`index.asp?login-error` ↔
// `main.asp`) que parecía un login real y no lo era — con cookies
// persistidas entre requests (como hace cualquier navegador) la página
// carga normal, sin ninguna cuenta.
//
// Mismo criterio que `comparador_precios.dart` (SEPA): solo esta pieza
// toca la red, se dispara sola desde `main.dart`, silenciosa si falla,
// nunca bloquea el arranque, y comparte `precios_referencia_externa` sin
// pisar las filas de la otra fuente (`fuente: 'todoatucasa'`).
//
// Autorización (El dueño, 2026-09-14): antes de dejar esto corriendo
// automático, el dueño habló con un conocido de Todo a tu Casa y confirmó que
// no hay problema en leer su catálogo de esta forma — no es un uso no
// autorizado de credenciales encontradas, es una automatización que el
// negocio dueño de los datos conoce y permite.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/normalizacion_texto.dart';
import '../data/repositorio_comparacion_precios.dart';

const _apiUrl = 'https://api.xrp.net/v2/Products/';

// Credenciales públicas del propio sitio (ver comentario de arriba) — no
// son un secreto de el dueño, son las que ya usa cualquier visitante.
const _accessToken = '96f9d37c8920b5f83806f09e51cd48e9';
const _apiKey = '96f9d37c8920b5f83806f09e51cd48e9';
const _partyIdFrom = 'fb2de06e-5378-452a-9eee-058bfcb21f34';
const _applicationId =
    '6c0c5eb13ae595242833ba9bd2145f4c078bf6c27fa16229c7d00fc79141976ac0ab5002dfcbc8d95231a06bb91fbf02a3b9336bbbb6fa4027023bac14930fad';

const _comercio = 'Todo a tu Casa';
const _tamanioPagina = 200;

/// Punto de entrada — mismo patrón que `actualizarComparacionPrecios`
/// (SEPA): no hace nada si esta fuente actualizó hace menos de 20 horas,
/// salvo [forzar] (el botón "Actualizar ahora" de la pantalla).
Future<void> actualizarComparacionPreciosTodoATuCasa(
  AppDatabase db, {
  bool forzar = false,
}) async {
  if (!forzar) {
    final ultima = await fechaUltimaActualizacionDeFuente(db, 'todoatucasa');
    if (ultima != null && DateTime.now().difference(ultima) < const Duration(hours: 20)) {
      return;
    }
  }

  final filas = await _bajarCatalogoCompleto();
  await reemplazarPreciosReferencia(db, fuente: 'todoatucasa', filas: filas);
}

/// Pagina todo el catálogo (`total_rows` en la respuesta ronda los 5.000
/// productos) — no hay forma de filtrar solo "lo que me interesa" como con
/// SEPA (no hay Bariloche que filtrar, es un solo local online), así que
/// se trae todo. Una pausa chica entre páginas por cortesía con el
/// servidor de un negocio ajeno, no porque haga falta para que funcione.
Future<List<PrecioReferenciaFila>> _bajarCatalogoCompleto() async {
  final porClave = <String, PrecioReferenciaFila>{};
  var offset = 0;
  while (true) {
    final pagina = await _pedirPagina(offset);
    if (pagina.isEmpty) break;

    for (final fila in filasDesdePagina(pagina)) {
      final clave = fila.codigoBarras.isNotEmpty
          ? 'ean:${fila.codigoBarras}'
          : 'nombre:${normalizarTexto(fila.nombreProducto)}';
      porClave[clave] = fila;
    }

    if (pagina.length < _tamanioPagina) break; // última página
    offset += _tamanioPagina;
    await Future.delayed(const Duration(milliseconds: 200));
  }
  return porClave.values.toList();
}

/// Convierte una página cruda de la API a filas listas para guardar —
/// separado de la paginación/red para poder probarlo sin pegarle a la API
/// real (`test/servicios/comparador_precios_todoatucasa_test.dart`).
/// Descarta productos sin nombre o sin precio (nada con qué compararlos ni
/// mostrarlos); sin código de barras válido, [PrecioReferenciaFila.codigoBarras]
/// queda vacío y `comparacionDePrecios` los cruza por nombre — mismo
/// camino que un pesable de SEPA sin EAN (El dueño, 2026-09-14: "todo lo que
/// esté en mi sistema").
List<PrecioReferenciaFila> filasDesdePagina(List<Map<String, dynamic>> pagina) {
  final resultado = <PrecioReferenciaFila>[];
  for (final producto in pagina) {
    final ean = (producto['bar_code'] as String?)?.trim();
    final nombre = (producto['description'] as String?)?.trim();
    final precio = producto['price'] as num?;
    if (nombre == null || nombre.isEmpty || precio == null) continue;
    final eanValido = ean != null && ean.isNotEmpty && ean != '0';
    final referencia = producto['reference_price'] as num?;
    resultado.add(
      PrecioReferenciaFila(
        codigoBarras: eanValido ? ean : '',
        comercio: _comercio,
        nombreProducto: nombre,
        precioCentavos: (precio.toDouble() * 100).round(),
        precioReferenciaCentavos: referencia == null ? null : (referencia.toDouble() * 100).round(),
        unidadReferencia: producto['reference_uom'] as String?,
      ),
    );
  }
  return resultado;
}

Future<List<Map<String, dynamic>>> _pedirPagina(int offset) async {
  final uri = Uri.parse(
    '$_apiUrl?description=&limit=$_tamanioPagina&offset=$offset&idcliente=0',
  );
  final respuesta = await http.get(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'Accept-Charset': 'iso-8859-1',
      'ACCESS-TOKEN': _accessToken,
      'API-KEY': _apiKey,
      'party-id-from': _partyIdFrom,
      'xrp-application-id': _applicationId,
    },
  );
  if (respuesta.statusCode != 200) return const [];

  final decodificado = jsonDecode(respuesta.body);
  if (decodificado is! List) return const [];
  return decodificado.cast<Map<String, dynamic>>();
}
