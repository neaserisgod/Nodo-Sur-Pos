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

import '../../ui/tema/acentos.dart';
import '../../ui/tema/tokens.dart';

// Paleta del rediseño "antigravity" (misma que la web de Nodo Sur): blanco
// puro de fondo, bloques gris muy claro, tinta casi negra como acento (los
// botones principales son píldoras negras) y color solo donde significa algo
// (los medios de pago, la ganancia, las alertas). En oscuro, negro puro.
// Ya no es un espejo de la paleta del escritorio: la companion tiene la suya.
const coloresCompanionClaro = ColoresPlazoleta(
  fondo: Color(0xFFFFFFFF),
  fondoBloque: Color(0xFFF3F4F7),
  borde: Color(0xFFE2E4EA),
  textoPrimario: Color(0xFF121317),
  textoSecundario: Color(0xFF566070),
  textoTenue: Color(0xFF7B8494),
  acento: Color(0xFF121317),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFC5221F),
  errorTexto: Color(0xFFFFFFFF),
);

const coloresCompanionOscuro = ColoresPlazoleta(
  fondo: Color(0xFF0E0F12),
  fondoBloque: Color(0xFF14161C),
  borde: Color(0xFF2A2D36),
  textoPrimario: Color(0xFFF4F5F7),
  textoSecundario: Color(0xFFA9B0BF),
  textoTenue: Color(0xFF7D8597),
  acento: Color(0xFFFFFFFF),
  acentoTexto: Color(0xFF121317),
  error: Color(0xFFFF8A80),
  errorTexto: Color(0xFF3B0A08),
);

// Degradé de las piezas "hero" (el CTA de vender, el total a cobrar): negro
// con un velo de color, como el bloque de cierre de la web.
const _heroClaro = [Color(0xFF0A0B10), Color(0xFF1B1F3A)];
const _heroOscuro = [Color(0xFF14161C), Color(0xFF232A55)];

/// Acentos con significado propios de la companion (colores de la web).
const acentosPlazoletaCompanionClaro = AcentosPlazoleta(
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

const acentosPlazoletaCompanionOscuro = AcentosPlazoleta(
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
    required this.ganancia,
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

  /// Verde de "va bien" (vuelto, conectado): el mismo `ganancia` del escritorio.
  final Color ganancia;

  @override
  AcentosCompanion copyWith({
    Color? dinero,
    Color? qr,
    Color? debito,
    Color? mixto,
    Color? textoSobreColor,
    List<Color>? gradienteAcento,
    List<Color>? gradienteDinero,
    Color? ganancia,
  }) {
    return AcentosCompanion(
      dinero: dinero ?? this.dinero,
      qr: qr ?? this.qr,
      debito: debito ?? this.debito,
      mixto: mixto ?? this.mixto,
      textoSobreColor: textoSobreColor ?? this.textoSobreColor,
      gradienteAcento: gradienteAcento ?? this.gradienteAcento,
      gradienteDinero: gradienteDinero ?? this.gradienteDinero,
      ganancia: ganancia ?? this.ganancia,
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
  dinero: acentosPlazoletaCompanionOscuro.dinero,
  qr: acentosPlazoletaCompanionOscuro.qr,
  debito: acentosPlazoletaCompanionOscuro.debito,
  mixto: acentosPlazoletaCompanionOscuro.mixto,
  textoSobreColor: acentosPlazoletaCompanionOscuro.textoSobreColor,
  gradienteAcento: acentosPlazoletaCompanionOscuro.gradienteAcento,
  gradienteDinero: acentosPlazoletaCompanionOscuro.gradienteDinero,
  ganancia: acentosPlazoletaCompanionOscuro.ganancia,
);

final acentosCompanionClaro = AcentosCompanion(
  dinero: acentosPlazoletaCompanionClaro.dinero,
  qr: acentosPlazoletaCompanionClaro.qr,
  debito: acentosPlazoletaCompanionClaro.debito,
  mixto: acentosPlazoletaCompanionClaro.mixto,
  textoSobreColor: acentosPlazoletaCompanionClaro.textoSobreColor,
  gradienteAcento: acentosPlazoletaCompanionClaro.gradienteAcento,
  gradienteDinero: acentosPlazoletaCompanionClaro.gradienteDinero,
  ganancia: acentosPlazoletaCompanionClaro.ganancia,
);

extension AcentosDelContexto on BuildContext {
  AcentosCompanion get acentos => Theme.of(this).extension<AcentosCompanion>()!;
}
