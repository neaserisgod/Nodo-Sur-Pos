// La base propia de la companion Android (fase 2 del rediseño "sin depender
// del escritorio") — vive una sola vez por proceso, igual que `AppDatabase`
// en `main.dart` del lado escritorio. Hasta acá, `lib/companion/` evitaba a
// propósito importar `data/database.dart` (ver el comentario de
// `MedioGastoCompanion` en `cliente_companion.dart`, "no meter drift en el
// build de Android") — deja de ser cierto a partir de este archivo: el
// celular ahora sí necesita su propia base SQLite para guardar la copia
// sincronizada. Todo lo demás de `lib/companion/` le sigue hablando al
// servidor por HTTP (`ClienteCompanion`) — esta base solo la usa
// `ServicioSincronizacion` para escribir lo que llega y leer lo que hay que
// mandar de vuelta.

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/database.dart';

/// Nombre de la base del celular (`AppDatabase._abrirConexion`, `driftDatabase(name: 'la_plazoleta')`): el archivo es
/// `la_plazoleta.sqlite` en la carpeta de documentos.
const nombreBaseCelular = 'la_plazoleta';

AppDatabase? _instancia;
bool _bloqueada = false;

/// Se pidió la base en medio de un cambio de negocio (`reinicio_companion.dart`). Es lo que llega tarde de la cuenta anterior:
/// falla en vez de abrir una base vacía en el lugar de la activa, que el cambio movería encima de la verdadera.
class BaseLocalBloqueada implements Exception {
  const BaseLocalBloqueada();
  @override
  String toString() => 'La base del celular está cerrada mientras se cambia de negocio.';
}

/// La base local de este celular. Se abre una sola vez, recién la primera
/// vez que algo la pide (el primer pull tras emparejar, o un sync
/// automático al reabrir la companion con una conexión ya guardada) — nunca
/// al arrancar la app, para no demorar ni un frame la pantalla que sea que
/// esté mostrando (mismo criterio de arranque que ya sigue el servidor
/// companion del escritorio).
AppDatabase baseLocalCompanion() {
  if (_bloqueada) throw const BaseLocalBloqueada();
  return _instancia ??= AppDatabase();
}

/// La demo del navegador (`demo/demo.dart`) trabaja sobre una base en memoria, armada antes de que nada la pida.
void usarBaseLocal(AppDatabase db) {
  _bloqueada = false;
  _instancia = db;
}

/// Solo para tests y capturas: reemplaza la base local por una en memoria.
@visibleForTesting
void usarBaseLocalDeTest(AppDatabase db) {
  _bloqueada = false;
  _instancia = db;
}

/// Cierra la base local si está abierta, para poder moverla o borrar su archivo (`borrar_celular.dart`). Con [bloquear], nadie
/// la puede volver a abrir hasta [desbloquearBaseLocal]; sin él, la próxima vez que algo la pida se abre de nuevo.
Future<void> cerrarBaseLocalCompanion({bool bloquear = false}) async {
  if (bloquear) _bloqueada = true;
  final db = _instancia;
  _instancia = null;
  await db?.close();
}

/// Terminado el cambio de negocio, la base (ya la del negocio nuevo) se puede abrir otra vez.
void desbloquearBaseLocal() => _bloqueada = false;
