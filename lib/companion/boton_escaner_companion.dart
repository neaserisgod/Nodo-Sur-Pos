// Botón de escanear que va al lado de un buscador (Productos, Consultar
// precio, Carrito), como en el mock completo del celular. Antes era el botón
// central de la navbar; ahora cada buscador lo lleva y decide qué hacer con
// el código (editar o dar de alta, mostrar el precio, sumar al carrito).

import 'package:flutter/material.dart';

import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';

class BotonEscanerCampo extends StatelessWidget {
  const BotonEscanerCampo({super.key, required this.onTap, this.cargando = false, this.tooltip = 'Escanear código de barras'});

  /// null deshabilita el botón (sin conexión o sin usuario elegido).
  final VoidCallback? onTap;
  final bool cargando;
  final String tooltip;

  static const double diametro = 56;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final deshabilitado = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: deshabilitado ? colores.borde : colores.acento,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: deshabilitado || cargando ? null : onTap,
          child: SizedBox(
            width: diametro,
            height: diametro,
            child: Center(
              child: cargando
                  ? SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: colores.acentoTexto))
                  : Icon(IconosPlazoleta.qrCodeScanner, color: colores.acentoTexto),
            ),
          ),
        ),
      ),
    );
  }
}
