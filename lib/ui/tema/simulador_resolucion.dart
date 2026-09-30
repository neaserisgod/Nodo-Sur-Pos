// Selector de resolución SOLO para debug (fase 11, actualizado en fase 13):
// simula el monitor real del local. Antes de fase 13 forzaba 1366×768 y
// 1280×720 — las dos resoluciones candidatas de la PC de 2008, porque no se
// sabía cuál hasta probarlo ahí. Esa PC ya no existe: el local tiene un
// monitor de 1920×1080 o más, así que esa pasa a ser la resolución de
// diseño real. 1366×768 se conserva como el piso — la resolución mínima
// que tiene que seguir viéndose digna si la app corre en una pantalla
// chica — no como objetivo. `kDebugMode` lo saca del árbol entero en
// release — ni el chip queda armado, ni se llama a `window_manager`.
//
// 960×1080 agregado en la fase 13, "mitad de pantalla" (El dueño, 2026-09-07:
// "prepara la app desktop para funcionar en la mitad de la pantalla de
// 1920×1080") — es más angosto que el piso de 1366; sigue sirviendo como
// piso de prueba angosto aunque la venta ya no tenga una columna dedicada
// que replegar (rediseño 2026-09-25, ver `pantalla_venta.dart`).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class SimuladorResolucion extends StatelessWidget {
  const SimuladorResolucion({super.key, required this.child});

  final Widget child;

  static const _resoluciones = {
    '1920×1080': Size(1920, 1080),
    '1366×768 (piso)': Size(1366, 768),
    '960×1080 (mitad)': Size(960, 1080),
  };

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    return Stack(
      children: [
        child,
        // Arriba, centrado: el AppBar de cada pantalla tiene título a la
        // izquierda y acciones a la derecha, con el centro vacío en las dos
        // resoluciones que este selector simula (bug real: abajo a la
        // derecha tapaba el botón "Cobrar"). Los diálogos van centrados
        // verticalmente, así que tampoco los pisa.
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in _resoluciones.entries)
                      _BotonResolucion(etiqueta: entry.key, tamanio: entry.value),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BotonResolucion extends StatelessWidget {
  const _BotonResolucion({required this.etiqueta, required this.tamanio});

  final String etiqueta;
  final Size tamanio;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      onPressed: () => windowManager.setSize(tamanio),
      child: Text(etiqueta, style: const TextStyle(fontSize: 11)),
    );
  }
}
