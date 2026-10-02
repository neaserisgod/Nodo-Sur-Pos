// Quién sincroniza este celular: la PC por wifi, o la nube de Nodo Sur. Una sola a la vez (El dueño, 2026-10-01:
// "si está conectado a la PC y se apaga, conectar automáticamente con la base en Cloudflare").
//
// Por qué una a la vez y no las dos: con la PC conectada, lo que hace el celular le llega a la PC por wifi y la PC
// lo sube a la nube. Si el celular también lo subiera, la nube recibiría cada cambio dos veces y gastaría el doble.
// Por eso, mientras la PC contesta, la nube del celular queda en pausa (ni conexión de avisos ni consultas).
//
// El traspaso a la nube espera [esperaTraspaso] desde que la PC dejó de contestar: un corte de wifi de unos
// segundos no tiene por qué abrir una conexión nueva. La vuelta a la PC es inmediata. El servicio con el que
// trabajan las pantallas (local vs PC) cambia al instante por su lado: la base local siempre está al día.

import 'dart:async';

import 'package:flutter/foundation.dart';

enum ModoSync {
  /// La PC contesta: se sincroniza con ella por wifi.
  pc,

  /// Sin PC (o sin que conteste) y con cuenta vinculada: se sincroniza por internet.
  nube,

  /// Sin PC y sin cuenta: todo queda en este celular hasta que haya con qué sincronizar.
  local,
}

class ConmutadorSync {
  ConmutadorSync({
    required this.iniciarNube,
    required this.detenerNube,
    required this.hayCuenta,
    this.esperaTraspaso = const Duration(seconds: 10),
  });

  final void Function() iniciarNube;
  final void Function() detenerNube;
  final Future<bool> Function() hayCuenta;
  final Duration esperaTraspaso;

  final ValueNotifier<ModoSync> modo = ValueNotifier(ModoSync.local);

  // Sin decidir hasta que el menú diga si hay PC emparejada o no (la primera llamada siempre se evalúa).
  bool? _tienePc;
  bool _pcConectada = false;
  bool _nubeActiva = false;
  Timer? _espera;
  int _version = 0; // descarta respuestas de `hayCuenta` que llegan tarde

  /// Hay una PC emparejada (modo "PC y celular") o no (modo "solo celular").
  void definirPc({required bool emparejada}) {
    final antes = _tienePc;
    if (antes == emparejada) return;
    _tienePc = emparejada;
    if (!emparejada) _pcConectada = false;
    _evaluar();
  }

  /// La conexión de avisos con la PC se abrió o se cortó.
  void pcConectada(bool conectada) {
    if (_pcConectada == conectada) return;
    _pcConectada = conectada;
    _evaluar();
  }

  /// Algo cambió por fuera (se vinculó o desvinculó la cuenta): volver a decidir.
  void reevaluar() {
    _parar();
    _evaluar();
  }

  void _evaluar() {
    if (_tienePc == true && _pcConectada) {
      _espera?.cancel();
      _espera = null;
      _parar();
      modo.value = ModoSync.pc;
      return;
    }
    if (_tienePc != true) {
      // Modo "solo celular": no hay a quién esperar.
      _espera?.cancel();
      _espera = null;
      unawaited(_arrancar());
      return;
    }
    // Hay PC pero no contesta: se espera un poco antes de pasar a la nube.
    if (_nubeActiva || _espera != null) return;
    _espera = Timer(esperaTraspaso, () {
      _espera = null;
      if (!_pcConectada) unawaited(_arrancar());
    });
  }

  Future<void> _arrancar() async {
    if (_nubeActiva) return;
    final version = ++_version;
    final cuenta = await hayCuenta();
    if (version != _version) return; // mientras tanto cambió la situación
    if (!cuenta) {
      modo.value = ModoSync.local;
      return;
    }
    _nubeActiva = true;
    iniciarNube();
    modo.value = ModoSync.nube;
  }

  void _parar() {
    _version++;
    if (_nubeActiva) {
      _nubeActiva = false;
      detenerNube();
    }
  }

  void cerrar() {
    _espera?.cancel();
    _parar();
    modo.dispose();
  }
}
