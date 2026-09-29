// Orquesta la sincronización fila por fila entre la base local del celular
// (`base_local.dart`) y la PC, hablando por HTTP con las dos rutas que
// agregó `servidor_companion.dart` (`/sync/cambios`). No decide NADA de
// merge acá — eso vive en `lib/data/repositorio_sincronizacion.dart`
// (`cambiosDesde`/`aplicarCambios`), la misma función que usa el servidor
// del lado de la PC (Regla 3). Esto solo mueve filas de un lado al otro, en
// el orden correcto (categorías/proveedores/productos antes que las ventas
// que los referencian — mismo orden de `tablasSincronizables`), y recuerda
// hasta dónde llegó la última vez.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_sincronizacion.dart';
import 'base_local.dart';
import 'cliente_companion.dart';

String _claveCursor(String direccion, String tabla) =>
    'companion_sync_${direccion}_$tabla';

Future<int> _leerCursor(SharedPreferences prefs, String direccion, String tabla) async {
  return prefs.getInt(_claveCursor(direccion, tabla)) ?? 0;
}

/// Sincroniza con la PC conectada en [cliente]: primero manda lo que este
/// celular escribió localmente desde la última vez (hoy, en la fase 2 del
/// rediseño, siempre vacío — nada escribe todavía en la base local; queda
/// listo para cuando `PuertoLocal` entre en producción), después trae lo
/// nuevo de la PC y lo aplica a la base propia.
///
/// Nunca deja escapar una falla de red hacia quien llama: devuelve `false`
/// en vez de propagar [ErrorCompanion] (token inválido, tabla rara) o
/// cualquier excepción de conexión (`SocketException`, timeout — la PC
/// apagada o fuera de la WiFi no tira `ErrorCompanion`, nunca llega a
/// responder nada) — sincronizar es best-effort (Bruno: "si las dos están
/// abiertas, se pasan los datos"; si no se puede en este momento, se sigue
/// funcionando contra la PC en vivo como siempre, o se reintenta en el
/// próximo pull-to-refresh).
Future<bool> sincronizarConPc(
  ClienteCompanion cliente, {
  /// La base del celular; null = la real (`baseLocalCompanion`). La usan
  /// los tests y `EscuchaPc`, que ya tiene la suya.
  AppDatabase? db,
}) async {
  // Ya hay una en curso: en vez de perder este pedido (un aviso de la PC
  // que llega mientras se baja el anterior), se anota y la que está
  // corriendo da una vuelta más al terminar (sync instantánea, 2026-09-28).
  if (_sincronizando) {
    _pedidaOtraVez = true;
    return false;
  }
  _sincronizando = true;
  try {
    var trajoAlgo = false;
    do {
      _pedidaOtraVez = false;
      if (await _unaVuelta(cliente, db)) trajoAlgo = true;
    } while (_pedidaOtraVez);
    return trajoAlgo;
  } catch (_) {
    // ErrorCompanion (token inválido, tabla rara) o cualquier falla de
    // conexión real (SocketException, timeout) — ninguna es fatal acá.
    return false;
  } finally {
    _sincronizando = false;
  }
}

bool _pedidaOtraVez = false;

/// Una ida y vuelta completa. Devuelve si bajó algo NUEVO de verdad.
///
/// Bug real (2026-09-28, "el celular me resetea la pantalla todo el rato"):
/// `cambiosDesde` es inclusivo (`>=`, ver su comentario), así que cada vuelta
/// volvía a subir y a bajar las filas del borde. La subida es un pedido que
/// modifica algo → la PC avisaba "cambió la base" → el celular sincronizaba
/// de nuevo → volvía a subir el borde: un bucle sin fin, y cada vuelta
/// refrescaba las pantallas. Mismo bug y mismo arreglo que el de Supabase
/// (2026-09-26): [filtrarYaSubidas] recuerda qué filas del borde ya pasaron
/// (en los dos sentidos) y solo cuenta las que cambiaron.
Future<bool> _unaVuelta(ClienteCompanion cliente, AppDatabase? base) async {
  var trajoAlgo = false;
  {
    final db = base ?? baseLocalCompanion();
    final prefs = await SharedPreferences.getInstance();
    final tablas = tablasSincronizables.keys.toList();

    // 1) Lo que este celular ya tenga para mandar (vacío hasta la fase 3) —
    // en orden, una tabla detrás de otra: un `INSERT` de `lineas_de_venta`
    // antes de que su `ventas` exista del otro lado rompería la clave
    // foránea, así que el push no se puede paralelizar entre tablas.
    for (final tabla in tablas) {
      final cursorPush = await _leerCursor(prefs, 'push', tabla);
      final candidatas = await cambiosDesde(db, tabla: tabla, desde: cursorPush);
      final plan = filtrarYaSubidas(
        tabla,
        filas: candidatas,
        cursor: cursorPush,
        borde: _leerBorde(prefs, 'push', tabla),
      );
      if (plan.aSubir.isNotEmpty) {
        await cliente.enviarCambios(tabla: tabla, filas: plan.aSubir);
        await prefs.setInt(_claveCursor('push', tabla), plan.cursor);
        await _guardarBorde(prefs, 'push', tabla, plan.borde);
      }
    }

    // 2) Lo que cambió del lado de la PC — PEDIR (`GET`) sí se puede en
    // paralelo, las 14 tablas a la vez: no hay ningún `INSERT` de por medio
    // todavía, así que el orden de las respuestas no importa (Bruno,
    // 2026-09-17: "todo tarda horrores" — 14 pedidos uno detrás del otro,
    // cada uno con su propio viaje de ida y vuelta por WiFi, era la mayor
    // parte de esa demora). Recién APLICAR (`aplicarCambios`, que si
    // inserta filas nuevas) se hace tabla por tabla, en el orden de
    // dependencias de siempre.
    final cursoresPull = {
      for (final tabla in tablas) tabla: await _leerCursor(prefs, 'pull', tabla),
    };
    final pulls = await Future.wait([
      for (final tabla in tablas)
        cliente.cambiosDesde(tabla: tabla, desde: cursoresPull[tabla]!),
    ]);
    for (var i = 0; i < tablas.length; i++) {
      final tabla = tablas[i];
      final recibido = pulls[i];
      // Mismo filtro del lado de la bajada: las filas del borde que ya se
      // aplicaron (misma huella) no cuentan como "llegó algo".
      final plan = filtrarYaSubidas(
        tabla,
        filas: recibido.filas,
        cursor: cursoresPull[tabla]!,
        borde: _leerBorde(prefs, 'pull', tabla),
      );
      if (plan.aSubir.isNotEmpty) {
        trajoAlgo = true;
        final noAplicadas = await aplicarCambios(db, tabla: tabla, filas: plan.aSubir);
        await prefs.setInt(_claveCursor('pull', tabla), plan.cursor);
        await _guardarBorde(prefs, 'pull', tabla, plan.borde);
        // Lo que se acaba de bajar no es un cambio de este celular: se
        // adelanta el cursor de push para no volver a subírselo a la PC en
        // la próxima vuelta (el mismo "eco" que se evita con Supabase).
        if (tablasSincronizables[tabla]!) {
          final aplicadas = plan.aSubir.where((f) => !noAplicadas.contains(f));
          if (aplicadas.isNotEmpty) {
            final maxEntrante = aplicadas
                .map((f) => (f['actualizado_en'] as num?)?.toInt() ?? 0)
                .reduce((a, b) => a > b ? a : b);
            final actual = await _leerCursor(prefs, 'push', tabla);
            if (maxEntrante > actual) await prefs.setInt(_claveCursor('push', tabla), maxEntrante);
          }
        }
      }
    }
  }
  return trajoAlgo;
}

Map<String, String> _leerBorde(SharedPreferences prefs, String direccion, String tabla) {
  final crudo = prefs.getString('companion_sync_borde_${direccion}_$tabla');
  if (crudo == null) return const {};
  try {
    return (jsonDecode(crudo) as Map<String, dynamic>).cast<String, String>();
  } on FormatException {
    return const {}; // peor caso: se repite el borde una vez
  }
}

Future<void> _guardarBorde(SharedPreferences prefs, String direccion, String tabla, Map<String, String> borde) =>
    prefs.setString('companion_sync_borde_${direccion}_$tabla', jsonEncode(borde));

bool _sincronizando = false;
