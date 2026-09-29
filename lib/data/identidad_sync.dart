// Identidad de sincronización compartida entre dispositivos (companion
// Android sin depender del escritorio, 2026-09-15) — ver el comentario de
// cabecera de la migración v29→v30 en `database.dart` para el diseño
// completo. Esta clave es lo que permite que dos bases SQLite
// independientes (escritorio y celular) sepan que una fila que cada una
// insertó por su cuenta es "la misma fila" al sincronizar, sin necesitar un
// servidor central que reparta ids.
//
// Mismo generador que ya usa `repositorio_cobro.dart` para no doble-cobrar
// un pago por terminal Point si la respuesta se pierde a mitad de camino —
// acá se reusa tal cual (Regla 3: una sola fórmula) en vez de reinventar
// otro generador de claves random para el mismo propósito.

import 'dart:math';

/// 128 bits de aleatoriedad criptográfica en hex (32 caracteres) — la misma
/// garantía de no-colisión que esta app ya acepta hoy para no duplicar un
/// cobro a Mercado Pago, sin agregar el paquete `uuid` para esto.
String generarGlobalId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Qué dispositivo está corriendo este proceso ahora mismo — va en
/// `origen_dispositivo` de cada fila nueva que crea un repositorio. 'desktop'
/// por defecto porque la PC nunca necesita configurarse (es el único
/// escritorio); la companion Android lo pisa una sola vez al arrancar, con
/// [establecerIdDispositivo], usando un id estable propio (ver
/// `lib/companion/identidad_dispositivo.dart`) — mismo mecanismo que espera
/// `dispositivoAperturaDesignadoId` en `tables/configuracion.dart`.
String _idDispositivoActual = 'desktop';

String get idDispositivoActual => _idDispositivoActual;

void establecerIdDispositivo(String id) {
  _idDispositivoActual = id;
}
