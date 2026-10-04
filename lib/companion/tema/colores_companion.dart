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

// Paleta del mock "Nodo Sur · App del celular" (docs/01 §2): blanco de fondo,
// superficies gris claro, tinta como acción primaria y un solo azul de marca.
// En oscuro el primario pasa a ser el azul. Los valores salen de `TokensNs`
// (`lib/companion/kit/tokens_ns.dart`), que es la fuente de verdad del mock;
// esto solo los traduce al tipo que usa el kit compartido (`ColoresPlazoleta`).
const coloresCompanionClaro = ColoresPlazoleta(
  fondo: Color(0xFFFFFFFF),
  fondoBloque: Color(0xFFF3F4F7),
  borde: Color(0xFFE1E4EA),
  textoPrimario: Color(0xFF121317),
  textoSecundario: Color(0xFF566070),
  textoTenue: Color(0xFF566070),
  acento: Color(0xFF121317),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFA4231B),
  errorTexto: Color(0xFFFFFFFF),
);

const coloresCompanionOscuro = ColoresPlazoleta(
  fondo: Color(0xFF0E0F13),
  fondoBloque: Color(0xFF1A1D24),
  borde: Color(0xFF2A2E38),
  textoPrimario: Color(0xFFEEF0F4),
  textoSecundario: Color(0xFFA0A8B6),
  textoTenue: Color(0xFFA0A8B6),
  acento: Color(0xFF2F5BE8),
  acentoTexto: Color(0xFFFFFFFF),
  error: Color(0xFFFF918A),
  errorTexto: Color(0xFF3A1613),
);

// El mock no usa degradés: las piezas "hero" son un color plano (`--hero`).
const _heroClaro = [Color(0xFF121317), Color(0xFF121317)];
const _heroOscuro = [Color(0xFF1C2231), Color(0xFF1C2231)];

/// Colores con significado de la companion: un color por medio de pago
/// (efectivo verde, Mercado Pago azul de marca, débito gris, mixto ámbar),
/// la ganancia en verde y las alertas en ámbar.
const acentosPlazoletaCompanionClaro = AcentosPlazoleta(
  dinero: Color(0xFF0B7A5E),
  qr: Color(0xFF2F5BE8),
  debito: Color(0xFF4B5563),
  mixto: Color(0xFFB45309),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: _heroClaro,
  gradienteDinero: _heroClaro,
  ganancia: Color(0xFF0B6A52),
  gananciaSuave: Color(0xFFE3F6EF),
  alerta: Color(0xFF7D3B03),
  alertaSuave: Color(0xFFFDECD6),
);

const acentosPlazoletaCompanionOscuro = AcentosPlazoleta(
  dinero: Color(0xFF0B7A5E),
  qr: Color(0xFF2F5BE8),
  debito: Color(0xFF4B5563),
  mixto: Color(0xFFB45309),
  textoSobreColor: Color(0xFFFFFFFF),
  gradienteAcento: _heroOscuro,
  gradienteDinero: _heroOscuro,
  ganancia: Color(0xFF63D9B0),
  gananciaSuave: Color(0xFF10342A),
  alerta: Color(0xFFF5B56C),
  alertaSuave: Color(0xFF392510),
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
