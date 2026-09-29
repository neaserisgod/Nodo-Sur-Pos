// Transporte de sincronización sobre Supabase — reemplaza
// `transporte_firestore.dart`. El SDK de Supabase funciona igual en Windows
// y Android (no hay bug de plataforma que esquivar, a diferencia de
// `firebase_auth`/`cloud_firestore` en Windows), así que hay un solo camino
// para las dos plataformas, sin bifurcación.
//
// A diferencia de Firestore, Realtime de Postgres NO reproduce el historial
// completo al conectar un canal nuevo (solo entrega cambios que pasan
// DESPUÉS de suscribirse) y no garantiza reentrega de lo que se pierda
// durante un corte de conexión — por eso acá el pull tiene DOS caminos que
// se complementan, no uno solo:
//   - [escucharTablaSupabase]: Realtime, entrega cada cambio casi al
//     instante mientras el canal esté conectado (la parte "fino como la
//     seda").
//   - [descargarCambiosSupabase]: un pull con cursor, llamado cada
//     intervalo desde `sincronizacion_supabase.dart` — la red de seguridad
//     real, que también cubre la sincronización inicial completa (cursor 0)
//     y cualquier cosa que Realtime se haya perdido en un corte.
// La columna `rev` (ver `supabase/schema.sql`) es el cursor de este segundo
// camino: un entero que un trigger en el servidor asigna en cada INSERT o
// UPDATE, desde una secuencia compartida entre las tablas — no viaja nunca
// al dominio ni a SQLite, se saca de cada fila antes de devolverla o
// entregarla: es maquinaria de transporte pura, invisible para
// `repositorio_sincronizacion.dart`.
//
// Sin traducción de tipos a mano (a diferencia de `firebase_rest_escritorio.dart`,
// que tenía que envolver cada valor en `{"integerValue": ...}` a mano):
// PostgREST serializa/deserializa JSON directo, y las columnas booleanas de
// Postgres acá son `smallint` (no `boolean`) a propósito, para que el 0/1
// crudo que ya produce `repositorio_sincronizacion.dart` (ver su comentario:
// "enteros para fechas y booleanos") viaje sin ninguna conversión, mismo
// principio que ya regía con Firestore.
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get _cliente => Supabase.instance.client;

const _maximoFilasPorLote = 500;

/// El `id` autoincrement de SQLite es local a cada dispositivo — la tabla
/// de Postgres ni siquiera tiene esa columna (`global_id` es la identidad
/// real ahí, ver `supabase/schema.sql`), así que mandarla revienta el
/// upsert (`PGRST204: Could not find the 'id' column`). Mismo criterio que
/// ya usa `_aplicarUnaFila` del lado del INSERT local.
Map<String, dynamic> _sinIdLocal(Map<String, dynamic> fila) =>
    Map<String, dynamic>.of(fila)..remove('id');

Future<void> subirFilasASupabase(String tabla, List<Map<String, dynamic>> filas) async {
  final sinId = filas.map(_sinIdLocal).toList();
  for (var inicio = 0; inicio < sinId.length; inicio += _maximoFilasPorLote) {
    final tanda = sinId.skip(inicio).take(_maximoFilasPorLote).toList();
    await _cliente.from(tabla).upsert(tanda, onConflict: 'global_id');
  }
}

Map<String, dynamic> _sinRev(Map<String, dynamic> fila) =>
    Map<String, dynamic>.of(fila)..remove('rev');

/// Filas nuevas o cambiadas desde el cursor [desde] (0 la primera vez: "traeme
/// todo"), más el cursor más alto entre ellas — mismo contrato que
/// `cambiosDesde`/`cursorMaximo` de `repositorio_sincronizacion.dart`, pero
/// del lado del pull en vez del push, y sobre `rev` (servidor) en vez de
/// `actualizado_en`/`id` (local).
Future<({List<Map<String, dynamic>> filas, int cursorMaximo})> descargarCambiosSupabase(
  String tabla, {
  required int desde,
}) async {
  final filas = await _cliente.from(tabla).select().gt('rev', desde).order('rev');
  if (filas.isEmpty) return (filas: <Map<String, dynamic>>[], cursorMaximo: desde);
  final cursorMaximo = filas
      .map((f) => (f['rev'] as num).toInt())
      .reduce((a, b) => a > b ? a : b);
  return (filas: filas.map(_sinRev).toList(), cursorMaximo: cursorMaximo);
}

class SuscripcionSupabase {
  SuscripcionSupabase._(this._canal);
  final RealtimeChannel _canal;
  Future<void> cancel() => Supabase.instance.client.removeChannel(_canal);
}

/// Solo la parte "instantánea" del pull — ver el comentario de cabecera de
/// este archivo. Nunca es la única fuente de la verdad:
/// [descargarCambiosSupabase], llamado periódicamente, es el que garantiza
/// que no se pierda nada.
SuscripcionSupabase escucharTablaSupabase(
  String tabla,
  void Function(List<Map<String, dynamic>> filas) alCambiar,
) {
  final canal = _cliente.channel('sync_$tabla');
  canal.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: tabla,
    callback: (payload) {
      if (payload.eventType == PostgresChangeEvent.delete) return;
      alCambiar([_sinRev(payload.newRecord)]);
    },
  );
  canal.subscribe();
  return SuscripcionSupabase._(canal);
}

/// Credenciales de cobro por terminal Point — documento/fila fija aparte de
/// las 14 tablas, nunca mezclada con el resto por ser un token de pago.
Future<void> escribirConfigCobro({
  required String? mpAccessToken,
  required String? mpTerminalCobroId,
}) async {
  await _cliente.from('configuracion_cobro').upsert({
    'id': 1,
    'mp_access_token': mpAccessToken,
    'mp_terminal_cobro_id': mpTerminalCobroId,
  });
}

Future<({String? mpAccessToken, String? mpTerminalCobroId})?> leerConfigCobro() async {
  final fila = await _cliente.from('configuracion_cobro').select().eq('id', 1).maybeSingle();
  if (fila == null) return null;
  return (
    mpAccessToken: fila['mp_access_token'] as String?,
    mpTerminalCobroId: fila['mp_terminal_cobro_id'] as String?,
  );
}
