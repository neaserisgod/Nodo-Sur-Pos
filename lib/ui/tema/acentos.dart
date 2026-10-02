// Familia de acentos del escritorio — puerto directo de
// `AcentosCompanion` (`lib/companion/tema/colores_companion.dart`), mismos
// cuatro colores semánticos (uno por medio de pago) más los dos degradés
// "hero". Reemplaza la regla de fase 11 "un solo acento, tres usos exactos"
// (`ColoresPlazoleta.acento`, `tokens.dart`) — ese acento único sigue
// existiendo (es el verde-azulado de `colores_escritorio.dart`, para
// selección/acción en general), pero deja de ser el único color con
// significado de la app: Venta reconcilia su paleta propia
// ("Bento con carácter", `color_categoria.dart`) contra esta familia en la
// Fase 5 del remake (ver el plan).
//
// Tipo propio, no una instancia más de `AcentosCompanion`: aunque hoy tiene
// los mismos valores, un cambio futuro de uno de los dos no debería mover
// al otro sin que alguien lo decida a propósito.

import 'package:flutter/material.dart';

@immutable
class AcentosPlazoleta extends ThemeExtension<AcentosPlazoleta> {
  const AcentosPlazoleta({
    required this.dinero,
    required this.qr,
    required this.debito,
    required this.mixto,
    required this.textoSobreColor,
    required this.gradienteAcento,
    required this.gradienteDinero,
    required this.ganancia,
    required this.gananciaSuave,
    required this.alerta,
    required this.alertaSuave,
  });

  final Color dinero;
  final Color qr;
  final Color debito;
  final Color mixto;

  /// Blanco/casi-blanco para texto sobre cualquiera de los cuatro colores de
  /// arriba en modo sólido — mismo motivo que en la companion: los cuatro
  /// son lo bastante saturados/oscuros como para que un solo valor alcance.
  final Color textoSobreColor;

  /// Degradé de dos tonos para las piezas "hero" (el total de Venta, el
  /// resumen del día del Dashboard) — mismo criterio que la companion:
  /// mismo acento, nunca un color nuevo, solo dos paradas en vez de una.
  final List<Color> gradienteAcento;
  final List<Color> gradienteDinero;

  /// Verde de "te queda" / ganancia / "cuadró" ("Lenguaje de diseño",
  /// 2026-09-26), con su fondo suave para chips y cajas. Nunca para otra
  /// cosa: si el verde también decorara, dejaría de decir "esto es plata
  /// tuya".
  final Color ganancia;
  final Color gananciaSuave;

  /// Aviso que no es un error (stock bajo, un sobrante chico, algo que
  /// conviene mirar): marrón sobre crema, como en los mocks. Lo que está
  /// MAL (faltante, eliminar) sigue siendo `ColoresPlazoleta.error`.
  final Color alerta;
  final Color alertaSuave;

  @override
  AcentosPlazoleta copyWith({
    Color? dinero,
    Color? qr,
    Color? debito,
    Color? mixto,
    Color? textoSobreColor,
    List<Color>? gradienteAcento,
    List<Color>? gradienteDinero,
    Color? ganancia,
    Color? gananciaSuave,
    Color? alerta,
    Color? alertaSuave,
  }) {
    return AcentosPlazoleta(
      dinero: dinero ?? this.dinero,
      qr: qr ?? this.qr,
      debito: debito ?? this.debito,
      mixto: mixto ?? this.mixto,
      textoSobreColor: textoSobreColor ?? this.textoSobreColor,
      gradienteAcento: gradienteAcento ?? this.gradienteAcento,
      gradienteDinero: gradienteDinero ?? this.gradienteDinero,
      ganancia: ganancia ?? this.ganancia,
      gananciaSuave: gananciaSuave ?? this.gananciaSuave,
      alerta: alerta ?? this.alerta,
      alertaSuave: alertaSuave ?? this.alertaSuave,
    );
  }

  @override
  AcentosPlazoleta lerp(ThemeExtension<AcentosPlazoleta>? other, double t) {
    if (other is! AcentosPlazoleta) return this;
    return t < 0.5 ? this : other;
  }
}

// Rediseño "antigravity": los mismos acentos con significado que la
// companion (`colores_companion.dart`) — efectivo ámbar, QR azul, débito
// verde-azulado, mixto violeta — y las piezas "hero" (el total, la acción
// principal) como el bloque negro con un velo de color de la web.
const _heroClaro = [Color(0xFF0A0B10), Color(0xFF1B1F3A)];
const _heroOscuro = [Color(0xFF14161C), Color(0xFF232A55)];

const acentosEscritorioClaro = AcentosPlazoleta(
  dinero: Color(0xFFB45309),
  qr: Color(0xFF3B6CFF),
  debito: Color(0xFF0E9F85),
  mixto: Color(0xFF8A5CF6),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: _heroClaro,
  gradienteDinero: _heroClaro,
  ganancia: Color(0xFF0E7C5A),
  gananciaSuave: Color(0xFFE3F6EF),
  alerta: Color(0xFF9A4A06),
  alertaSuave: Color(0xFFFFF1DC),
);

const acentosEscritorioOscuro = AcentosPlazoleta(
  dinero: Color(0xFFC26A12),
  qr: Color(0xFF4F7CFF),
  debito: Color(0xFF0E9F85),
  mixto: Color(0xFF8A5CF6),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: _heroOscuro,
  gradienteDinero: _heroOscuro,
  ganancia: Color(0xFF6FE3B8),
  gananciaSuave: Color(0xFF12332A),
  alerta: Color(0xFFFFB878),
  alertaSuave: Color(0xFF3A2410),
);

extension AcentosDelContexto on BuildContext {
  AcentosPlazoleta get acentosPlazoleta => Theme.of(this).extension<AcentosPlazoleta>()!;
}
