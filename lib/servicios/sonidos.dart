// Sonidos cortos y suaves de la app (El dueño, 2026-10-18: "unos soniditos para cuando se recibe un pago, las notificaciones").
// Dos y nada más: [Sonido.pago] (dos notas que suben) cuando Mercado Pago aprueba un cobro o se paga una seña, y [Sonido.aviso] (dos
// notas que bajan) cuando el bot da un turno o toma un pedido. Una venta en efectivo no suena: en un almacén con mucho movimiento
// cansaría. Los archivos son `assets/sonidos/*.wav`, sintetizados para esto (sin licencias de terceros).
//
// Se cargan en memoria al arrancar (`main`) y no antes: así un test que abre el cobro no toca el plugin de audio, y la venta no
// espera a leer un archivo justo cuando se aprueba el pago. Se apagan en Más › Apariencia (celular) o Configuración › Apariencia
// (PC), por equipo.
//
// Nunca tira ni demora a quien lo llama: un celular sin audio, un navegador que todavía no dejó sonar nada o un plugin que falla
// no frenan un cobro.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sonido {
  pago('sonidos/pago.wav'),
  aviso('sonidos/aviso.wav');

  const Sonido(this.archivo);

  /// Relativo a `assets/` (como lo pide [AssetSource]).
  final String archivo;
}

/// Lo que de verdad hace ruido. Aparte para que los tests no dependan del plugin.
abstract class ReproductorSonidos {
  Future<void> preparar(Sonido s);
  Future<void> tocar(Sonido s);
}

class Sonidos {
  Sonidos({DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  static const _clave = 'sonidos.activos';

  /// Dos avisos del mismo sonido más juntos que esto suenan una vez: cuando el bot da tres turnos en una vuelta, o el aviso en
  /// vivo y la sync traen lo mismo, no tiene que sonar como una alarma.
  static const separacionMinima = Duration(milliseconds: 1500);

  final DateTime Function() _ahora;

  /// Prendidos salvo que se apaguen. Las pantallas de configuración lo escuchan.
  final ValueNotifier<bool> activos = ValueNotifier(true);

  ReproductorSonidos? _reproductor;
  final _ultimo = <Sonido, DateTime>{};

  /// Lee la preferencia y deja los sonidos en memoria. Hasta que se llama, [sonar] no hace nada.
  Future<void> cargar({ReproductorSonidos? reproductor}) async {
    _ultimo.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      activos.value = prefs.getBool(_clave) ?? true;
    } catch (_) {
      // sin preferencias: prendidos
    }
    final r = reproductor ?? _ReproductorAudioplayers();
    try {
      for (final s in Sonido.values) {
        await r.preparar(s);
      }
      _reproductor = r;
    } catch (_) {
      // equipo sin audio: la app sigue muda
    }
  }

  Future<void> guardarActivos(bool v) async {
    activos.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, v);
    } catch (_) {
      // queda para esta vez
    }
    if (v) sonar(Sonido.pago); // que se escuche cómo suena al prenderlos
  }

  /// Suena [s] sin esperar a que termine. No hace nada si están apagados, si todavía no se cargaron o si el mismo sonido sonó
  /// hace menos de [separacionMinima].
  void sonar(Sonido s) {
    final r = _reproductor;
    if (r == null || !activos.value) return;
    final ahora = _ahora();
    final antes = _ultimo[s];
    if (antes != null && ahora.difference(antes) < separacionMinima) return;
    _ultimo[s] = ahora;
    unawaited(r.tocar(s).catchError((Object _) {}));
  }
}

/// Los sonidos de toda la app.
final sonidos = Sonidos();

class _ReproductorAudioplayers implements ReproductorSonidos {
  final _jugadores = <Sonido, AudioPlayer>{};
  var _contextoPuesto = false;

  @override
  Future<void> preparar(Sonido s) async {
    if (!_contextoPuesto) {
      _contextoPuesto = true;
      try {
        // Que suene encima de la música del local en vez de pausarla, y por el canal de notificaciones (respeta el modo silencio).
        await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers, respectSilence: true).build());
      } catch (_) {
        // Windows y el navegador no tienen contexto de audio: suenan igual
      }
    }
    final j = AudioPlayer(playerId: 'sonido_${s.name}');
    // En Android, el modo de baja latencia usa SoundPool: suena al instante. En la PC y el navegador no existe.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) await j.setPlayerMode(PlayerMode.lowLatency);
    await j.setReleaseMode(ReleaseMode.stop);
    await j.setSource(AssetSource(s.archivo));
    _jugadores[s] = j;
  }

  @override
  Future<void> tocar(Sonido s) async {
    final j = _jugadores[s];
    if (j == null) return;
    await j.stop();
    await j.resume();
  }
}
