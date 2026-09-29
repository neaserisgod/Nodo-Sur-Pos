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

import '../data/database.dart';

AppDatabase? _instancia;

/// La base local de este celular. Se abre una sola vez, recién la primera
/// vez que algo la pide (el primer pull tras emparejar, o un sync
/// automático al reabrir la companion con una conexión ya guardada) — nunca
/// al arrancar la app, para no demorar ni un frame la pantalla que sea que
/// esté mostrando (mismo criterio de arranque que ya sigue el servidor
/// companion del escritorio).
AppDatabase baseLocalCompanion() => _instancia ??= AppDatabase();
