// Qué pasa cuando se elige un modo de uso (`pantalla_elegir_modo.dart`).

import 'package:flutter/material.dart';

import 'bienvenida/pantalla_bienvenida.dart';
import 'emparejamiento.dart';
import 'escucha_pc.dart';
import 'modo_uso.dart';
import 'pantalla_elegir_modo.dart';
import 'pantalla_entrar_con_cuenta.dart';
import 'pantalla_emparejamiento.dart';
import 'pantalla_menu_companion.dart';
import 'sync_nube_companion.dart';

/// Deja el celular como único sistema: corta la escucha de la PC, olvida su emparejamiento y avisa al conmutador
/// de la sync de que ya no hay a quién esperar (la nube arranca sola si hay cuenta). No toca los datos ni el usuario.
Future<void> aplicarModoSoloCelular() async {
  escuchaPcCompanion?.detener();
  escuchaPcCompanion = null;
  await olvidarConexion();
  await guardarModoUso(ModoUso.soloCelular);
  syncNubeCompanion?.conmutador.definirPc(emparejada: false);
}

/// Lo primero que ve una instalación nueva: la bienvenida, y al terminarla (o saltarla) elegir el modo.
Widget pantallaDeBienvenidaInicial() => PantallaBienvenida(
  alTerminar: (context) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => pantallaDeElegirModoInicial()),
  ),
);

/// La pantalla de elegir el modo en el primer arranque (después de la bienvenida).
Widget pantallaDeElegirModoInicial() => PantallaElegirModo(
  alElegir: (context, modo) => elegirModo(context, modo, actual: null),
);

/// Se tocó [modo]. [actual] es el modo en uso hoy (null en el primer arranque).
Future<void> elegirModo(BuildContext context, ModoUso modo, {required ModoUso? actual}) async {
  final navigator = Navigator.of(context);
  if (modo == actual) {
    navigator.pop(); // ya está en ese modo: no hay nada que cambiar
    return;
  }
  switch (modo) {
    case ModoUso.pcYCelular:
      // El modo se guarda recién cuando el emparejamiento sale bien: si el usuario vuelve atrás sin emparejar,
      // queda como estaba.
      await navigator.push(MaterialPageRoute<void>(builder: (_) => const PantallaEmparejamiento()));
    case ModoUso.soloCelular:
      await aplicarModoSoloCelular();
      if (actual == null) {
        // Primer arranque: se entra con la cuenta de la persona. Eso vincula la sync por internet Y fija su perfil, así que
        // reemplaza al paso de "vincular la cuenta" y a la lista de usuarios (`pantalla_entrar_con_cuenta.dart`).
        navigator.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const PantallaEntrarConCuenta()),
          (route) => false,
        );
      } else {
        // Desde Gestión: se arma un menú nuevo, que lee el modo ya cambiado.
        navigator.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const PantallaMenuCompanion()),
          (route) => false,
        );
      }
  }
}
