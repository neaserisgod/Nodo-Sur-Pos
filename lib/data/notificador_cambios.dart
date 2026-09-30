// Aviso de "algo cambió en la base" para la sync instantánea por wifi
// (El dueño, 2026-09-28: "hagamos 100% fluida y efectiva la sync mediante
// wifi" — hubo que cerrar y abrir la app del celular para que se enterara de
// una caja abierta en la PC).
//
// Dos salidas, para dos oyentes distintos:
//   - [cambiosDeLaBase]: cualquier escritura en la base de la PC, sea de la
//     PC misma o del celular. La escucha `/companion/eventos`
//     (`servidor_companion.dart`) para avisarle al celular en el momento.
//   - [cambiosDelCelular]: solo lo que escribió el celular (un pedido que
//     modifica algo, o filas que subió por `/sync/cambios`). La escuchan las
//     pantallas de la PC para refrescarse solas sin reaccionar a sus propias
//     escrituras (Venta no tiene que recargar el catálogo en cada cobro
//     propio).
//
// Las filas que aplica la sincronización (`aplicarCambios`) usan
// `customInsert`/`customUpdate` sin `updates:` a propósito (ver
// `sincronizacion_supabase.dart`), así que no llegan por `tableUpdates()`:
// por eso el servidor también llama a [cambioDelCelular] a mano.

import 'dart:async';

import 'database.dart';

class NotificadorCambios {
  NotificadorCambios(AppDatabase db) {
    _sub = db.tableUpdates().listen((_) => _avisarBase());
  }

  late final StreamSubscription<void> _sub;
  final _base = StreamController<int>.broadcast();
  final _celular = StreamController<void>.broadcast();
  Timer? _esperaBase;
  Timer? _esperaCelular;

  /// Sube con cada aviso: el celular lo usa para no sincronizar dos veces
  /// por el mismo cambio.
  int version = 0;

  /// Espera corta antes de avisar: una venta escribe varias tablas casi
  /// juntas (venta, líneas, pagos, stock, caja) — un solo aviso alcanza.
  static const _agrupar = Duration(milliseconds: 120);

  Stream<int> get cambiosDeLaBase => _base.stream;
  Stream<void> get cambiosDelCelular => _celular.stream;

  void _avisarBase() {
    _esperaBase?.cancel();
    _esperaBase = Timer(_agrupar, () {
      version++;
      if (!_base.isClosed) _base.add(version);
    });
  }

  /// El celular modificó algo (ver cabecera).
  void cambioDelCelular() {
    _avisarBase();
    _esperaCelular?.cancel();
    _esperaCelular = Timer(_agrupar, () {
      if (!_celular.isClosed) _celular.add(null);
    });
  }

  void cerrar() {
    _sub.cancel();
    _esperaBase?.cancel();
    _esperaCelular?.cancel();
    _base.close();
    _celular.close();
  }
}

/// Una sola instancia por proceso de la PC (la arma `main.dart` junto con la
/// base); null en el celular y en los tests que no la necesitan.
NotificadorCambios? notificadorCambios;
