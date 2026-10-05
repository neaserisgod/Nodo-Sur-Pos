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

// Mock "Nodo Sur" (2026-10-05, decisión del dueño): mismos acentos que el celular (`acentosPlazoletaCompanion*`):
// efectivo verde, Mercado Pago azul de marca, tarjeta gris y mixto ámbar (sin violeta). Las piezas "hero" (el total, la
// acción principal) son de un color plano, sin degradé.
const _heroClaro = [Color(0xFF121317), Color(0xFF121317)];
const _heroOscuro = [Color(0xFF1C2231), Color(0xFF1C2231)];

const acentosEscritorioClaro = AcentosPlazoleta(
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

const acentosEscritorioOscuro = AcentosPlazoleta(
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

/// Azul de marca del mock (`#2F5BE8`): la pestaña Venta de la navbar, "Nueva venta" y "Cobrar". No cambia con el tema.
const Color azulMarca = Color(0xFF2F5BE8);

/// El mismo azul, más oscuro: la pestaña Venta cuando es la pantalla activa.
const Color azulMarcaOscuro = Color(0xFF1F3FA8);

/// Fondo y texto de lo "seleccionado/activo" en azul claro (mock `--ibg` / `--i`): la burbuja de la sección activa de la
/// navbar. Cambian con el tema, por eso no son constantes.
extension AzulSuaveDelContexto on BuildContext {
  bool get _oscuro => Theme.of(this).brightness == Brightness.dark;
  Color get azulSuaveFondo => _oscuro ? const Color(0xFF17254F) : const Color(0xFFE0E9FF);
  Color get azulSuaveTexto => _oscuro ? const Color(0xFFA3BCFF) : const Color(0xFF2F5BE8);
}

extension AcentosDelContexto on BuildContext {
  AcentosPlazoleta get acentosPlazoleta => Theme.of(this).extension<AcentosPlazoleta>()!;
}
