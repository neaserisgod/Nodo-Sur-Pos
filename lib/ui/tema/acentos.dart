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

// "Lenguaje de diseño" (El dueño, 2026-09-26): efectivo naranja y Mercado Pago
// azul, como en los mocks — QR es el azul de MP puro y Débito un azul más
// profundo de la misma familia, porque en la caja los dos son el mismo
// medio "Mercado Pago" (CLAUDE.md, pantalla de venta) y tienen que leerse
// como parientes; Mixto va en violeta, que no se confunde con ninguno de
// los dos ni con el verde de ganancia. Las piezas "hero" (el total, la
// acción principal) dejan de ser un degradé con brillo: son la tarjeta
// casi negra del mock en claro, y el azul de acento en oscuro (una tarjeta
// negra sobre un fondo oscuro no destaca nada). Los dos "degradés" quedan
// casi planos: se mantiene el tipo para no tocar a los llamadores.
const acentosEscritorioClaro = AcentosPlazoleta(
  dinero: Color(0xFFB45309),
  qr: Color(0xFF0B57D0),
  debito: Color(0xFF00639B),
  mixto: Color(0xFF6750A4),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: [Color(0xFF1F1F1F), Color(0xFF2D2F31)],
  gradienteDinero: [Color(0xFF1F1F1F), Color(0xFF2D2F31)],
  ganancia: Color(0xFF146C2E),
  gananciaSuave: Color(0xFFE6F4EA),
  alerta: Color(0xFF7A3A04),
  alertaSuave: Color(0xFFFEF1E0),
);

const acentosEscritorioOscuro = AcentosPlazoleta(
  dinero: Color(0xFFC26A12),
  qr: Color(0xFF3B7DE8),
  debito: Color(0xFF1A7FB8),
  mixto: Color(0xFF8A6FD1),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: [Color(0xFF0B57D0), Color(0xFF0842A0)],
  gradienteDinero: [Color(0xFF0B57D0), Color(0xFF0842A0)],
  ganancia: Color(0xFF6DD58C),
  gananciaSuave: Color(0xFF173A24),
  alerta: Color(0xFFFFB68A),
  alertaSuave: Color(0xFF3F2410),
);

extension AcentosDelContexto on BuildContext {
  AcentosPlazoleta get acentosPlazoleta => Theme.of(this).extension<AcentosPlazoleta>()!;
}
