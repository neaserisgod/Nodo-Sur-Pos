// Las pantallas de la PC se refrescan solas cuando el celular cambia algo
// (sync instantánea por wifi, 2026-09-28: antes, lo que hacía el celular —
// abrir la caja, cobrar, tocar un precio — recién se veía en la PC al
// cambiar de pantalla). Escucha solo lo que viene del celular
// (`NotificadorCambios.cambiosDelCelular`), no las escrituras propias de la
// PC: cobrar en Venta no tiene que recargar el catálogo entero.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/notificador_cambios.dart';

mixin RefrescoPorCelular<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _subCelular;

  /// Qué releer cuando el celular cambió algo.
  void alCambiarDesdeElCelular();

  @override
  void initState() {
    super.initState();
    _subCelular = notificadorCambios?.cambiosDelCelular.listen((_) {
      if (mounted) alCambiarDesdeElCelular();
    });
  }

  @override
  void dispose() {
    _subCelular?.cancel();
    super.dispose();
  }
}
