// Puente con WinSparkle (paquete `auto_updater`). Es la única parte que toca
// el plugin nativo: todo lo demás (`actualizaciones.dart`) se prueba sin él.
//
// Seguimos el README del paquete (setFeedURL + checkForUpdates), con una
// diferencia a propósito: NO se usa `setScheduledCheckInterval`. Las
// revisiones programadas de WinSparkle abren su ventana sola cuando hay una
// versión nueva, sin mirar si hay una venta en curso. Acá WinSparkle no se
// inicializa hasta que alguien toca "Instalar ahora" o "Buscar
// actualizaciones" (`setFeedURL` hace el `win_sparkle_init`).

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

bool _configurado = false;

class _EscuchaActualizador with UpdaterListener {
  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    // WinSparkle pide cerrar la app para correr el instalador. El permiso ya
    // lo dio quien tocó "Instalar": se cierra sin volver a preguntar por la
    // caja abierta (eso se decidió al elegir actualizar).
    windowManager.destroy();
  }

  @override
  void onUpdaterError(UpdaterError? error) =>
      debugPrint('Actualizador: error ${error?.message}');

  // El resto de los eventos no hace falta: WinSparkle ya muestra su propia
  // ventana con el avance.
  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {}

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {}

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {}

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {}
}

/// Abre la interfaz de WinSparkle contra [urlFeed]: busca, muestra las
/// novedades, descarga, verifica la firma y instala.
Future<void> abrirActualizadorNativo(String urlFeed) async {
  if (!_configurado) {
    autoUpdater.addListener(_EscuchaActualizador());
    await autoUpdater.setFeedURL(urlFeed);
    _configurado = true;
  }
  await autoUpdater.checkForUpdates(inBackground: false);
}
