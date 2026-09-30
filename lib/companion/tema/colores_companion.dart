// Identidad visual propia de la companion — El dueño, 2026-09-17: "mandá al
// demonio toda cosa establecida en [los] md, quiero que sea un
// rework/remake desde 0". Deja de compartir la paleta ámbar/gris del
// escritorio (`lib/ui/tema/tokens.dart`, sin tocar — la app de escritorio
// sigue exactamente igual) y define la suya: verde-azulado vibrante como
// acento, fondo casi negro azulado, y un color propio por medio de pago en
// vez de que los cuatro compartan un solo acento.
//
// Reutiliza el MISMO tipo `ColoresPlazoleta` (`lib/ui/tema/tokens.dart`) en
// vez de inventar una clase paralela: ese tipo ya es genérico (diez colores
// con rol fijo, sin ningún valor hardcodeado de escritorio adentro), y todo
// el kit compartido (`Bloque`, `CampoTexto`, `EstadoVacio` del escritorio,
// etc.) ya lee sus colores a través de `context.colores` — instanciarlo con
// valores nuevos y registrarlo en el `ThemeData` de la companion
// (`tema_companion.dart`) alcanza para que toda la app cambie de paleta sin
// tocar un solo archivo compartido.

import 'package:flutter/material.dart';

import '../../ui/tema/acentos.dart' show acentosEscritorioClaro, acentosEscritorioOscuro;
import '../../ui/tema/colores_escritorio.dart';

// "Dark glass premium" (El dueño, rediseño 2026-09-25) — espejo exacto de
// `coloresEscritorioOscuro` (`lib/ui/tema/colores_escritorio.dart`), mismo
// motivo: negro más profundo, texto secundario/tenue con más margen de
// contraste, acento sin cambios (ver ese archivo para el detalle de
// contraste WCAG verificado).
// Misma paleta que el escritorio ("Lenguaje de diseño", 2026-09-26): una
// sola fuente de verdad para los colores de las dos apps.
const coloresCompanionOscuro = coloresEscritorioOscuro;
const coloresCompanionClaro = coloresEscritorioClaro;

@immutable
class AcentosCompanion extends ThemeExtension<AcentosCompanion> {
  const AcentosCompanion({
    required this.dinero,
    required this.qr,
    required this.debito,
    required this.mixto,
    required this.textoSobreColor,
    required this.gradienteAcento,
    required this.gradienteDinero,
  });

  final Color dinero;
  final Color qr;
  final Color debito;
  final Color mixto;

  /// Blanco/casi-blanco para texto sobre cualquiera de los cuatro colores de
  /// arriba en modo sólido — todos son lo bastante saturados/oscuros como
  /// para que un solo valor sirva para los cuatro, a diferencia de
  /// `acentoTexto` (que sí cambia entre claro/oscuro porque el verde-azulado
  /// principal es más claro en modo oscuro).
  final Color textoSobreColor;

  /// Degradé de dos tonos para las piezas "hero" (el total del carrito, la
  /// tarjeta de ventas de hoy) — El dueño, 2026-09-18: "pensalo como una app
  /// moderna, útil y monetizable". Un relleno sólido plano se lee más
  /// genérico que un degradé sutil sobre la misma paleta: mismo acento,
  /// nunca un color nuevo, solo dos paradas en vez de una.
  final List<Color> gradienteAcento;
  final List<Color> gradienteDinero;

  @override
  AcentosCompanion copyWith({
    Color? dinero,
    Color? qr,
    Color? debito,
    Color? mixto,
    Color? textoSobreColor,
    List<Color>? gradienteAcento,
    List<Color>? gradienteDinero,
  }) {
    return AcentosCompanion(
      dinero: dinero ?? this.dinero,
      qr: qr ?? this.qr,
      debito: debito ?? this.debito,
      mixto: mixto ?? this.mixto,
      textoSobreColor: textoSobreColor ?? this.textoSobreColor,
      gradienteAcento: gradienteAcento ?? this.gradienteAcento,
      gradienteDinero: gradienteDinero ?? this.gradienteDinero,
    );
  }

  @override
  AcentosCompanion lerp(ThemeExtension<AcentosCompanion>? other, double t) {
    if (other is! AcentosCompanion) return this;
    return t < 0.5 ? this : other;
  }
}

// Mismos valores que `acentosEscritorio*` (`lib/ui/tema/acentos.dart`, con
// el porqué de cada color). Tipo propio a propósito — ver el comentario de
// `AcentosPlazoleta` —, pero hoy los dos se leen del mismo lugar.
final acentosCompanionOscuro = AcentosCompanion(
  dinero: acentosEscritorioOscuro.dinero,
  qr: acentosEscritorioOscuro.qr,
  debito: acentosEscritorioOscuro.debito,
  mixto: acentosEscritorioOscuro.mixto,
  textoSobreColor: acentosEscritorioOscuro.textoSobreColor,
  gradienteAcento: acentosEscritorioOscuro.gradienteAcento,
  gradienteDinero: acentosEscritorioOscuro.gradienteDinero,
);

final acentosCompanionClaro = AcentosCompanion(
  dinero: acentosEscritorioClaro.dinero,
  qr: acentosEscritorioClaro.qr,
  debito: acentosEscritorioClaro.debito,
  mixto: acentosEscritorioClaro.mixto,
  textoSobreColor: acentosEscritorioClaro.textoSobreColor,
  gradienteAcento: acentosEscritorioClaro.gradienteAcento,
  gradienteDinero: acentosEscritorioClaro.gradienteDinero,
);

extension AcentosDelContexto on BuildContext {
  AcentosCompanion get acentos => Theme.of(this).extension<AcentosCompanion>()!;
}
