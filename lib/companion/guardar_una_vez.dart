// Para los botones que guardan algo (El dueño, 2026-10-14: revisión de Nodo Sur Servicios). Dos cosas que se repetían pantalla
// por pantalla: un doble toque guardaba dos veces (dos turnos, una compra sumada dos veces al stock) y solo se mostraban los
// errores de validación; cualquier otra falla se perdía sin aviso.

import 'package:flutter/widgets.dart';

import '../servicios/registro_errores.dart' show registrarSiNoEsDeRed;
import 'mensaje_error.dart';

mixin GuardarUnaVezNs<T extends StatefulWidget> on State<T> {
  /// Hay un guardado en curso: el botón va apagado (`guardando ? null : _guardar`).
  bool guardando = false;

  /// Corre [accion] si no hay otra corriendo. Una validación (`ArgumentError`, `FormatException`) llega a [alFallar] con su
  /// texto; cualquier otra falla, con un mensaje entendible, y queda anotada.
  Future<void> unaVez(Future<void> Function() accion, {required void Function(String mensaje) alFallar}) async {
    if (guardando) return;
    setState(() => guardando = true);
    try {
      await accion();
    } on ArgumentError catch (e) {
      if (mounted) alFallar('${e.message}');
    } on FormatException catch (e) {
      if (mounted) alFallar(e.message);
    } catch (e, st) {
      await registrarSiNoEsDeRed('Guardar', e, st);
      if (mounted) alFallar(mensajeDeError(e));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }
}
