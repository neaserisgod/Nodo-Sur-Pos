// Qué combinaciones dibujan los tests de capturas (`test/ui/capturas_*`, `test/companion/capturas_companion_test.dart`).
//
// Por defecto, una sola por pantalla: tema claro y, en la PC, la ventana más chica (1366). Es la que encuentra lo que
// no entra, que es lo único que estos tests comprueban (no comparan píxeles), y cuesta un cuarto. Para mirar las
// imágenes con todas las combinaciones (claro y oscuro, 1920 y 1366):
//
//   flutter test test/ui/capturas_mock_test.dart --dart-define=CAPTURAS=todas
//
// (2026-10-06: las cuatro combinaciones de cada pantalla eran la parte más lenta de la suite.)

import 'dart:ui' show Size;

/// `--dart-define=CAPTURAS=todas`: claro y oscuro, en todos los tamaños.
const bool todasLasCapturas = String.fromEnvironment('CAPTURAS') == 'todas';

/// Los temas a dibujar: `false` = claro, `true` = oscuro.
const List<bool> temasDeCaptura = todasLasCapturas ? [false, true] : [false];

/// Los tamaños de ventana de la PC (el área útil: 1920×1080 y 1366×768 menos la barra de la ventana).
const List<Size> tamaniosDeCapturaPc = todasLasCapturas ? [Size(1920, 1040), Size(1366, 728)] : [Size(1366, 728)];
