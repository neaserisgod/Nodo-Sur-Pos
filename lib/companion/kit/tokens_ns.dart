// Tokens de color del celular, tal cual el mock "Nodo Sur · App del celular"
// (docs/01-sistema-de-diseno.md §2). Claro, oscuro y automático; en oscuro el
// primario pasa a ser el azul de marca. Todo el kit (`lib/companion/kit/`) lee
// sus colores de acá: nada de hex sueltos en las pantallas, porque el modo
// oscuro funciona solo si todo pasa por un token.
//
// Nodo Gastro tiene su propia paleta (la marca del sitio, mock docs/mock-gastro/NodoGastro.html): blanco y piedra, tinta y un solo
// acento naranja, siempre con texto negro encima. Las pantallas no preguntan la edición: piden los tokens con [TokensNs.paraBrillo]
// o `context.ns` y reciben los que tocan.

import 'package:flutter/material.dart';

import '../../edicion.dart';

@immutable
class TokensNs extends ThemeExtension<TokensNs> {
  const TokensNs({
    required this.ink,
    required this.paper,
    required this.s,
    required this.s2,
    required this.mute,
    required this.line,
    required this.prim,
    required this.hero,
    required this.toast,
    required this.gbg,
    required this.g,
    required this.bbg,
    required this.b,
    required this.wbg,
    required this.w,
    required this.ibg,
    required this.i,
    required this.oscuro,
    this.onPrim = const Color(0xFFFFFFFF),
    required this.acento,
    this.onAcento = const Color(0xFFFFFFFF),
  });

  /// Texto e iconos sobre [prim]. Blanco salvo en el oscuro de Gastro, donde el primario es claro.
  final Color onPrim;

  /// La acción que más importa de la pantalla (aceptar un pedido, cobrar, el "+"). En almacén y Servicios es el mismo
  /// [prim]; en Gastro, el naranja de la marca.
  final Color acento;

  /// Texto sobre [acento]: sobre el naranja va negro, nunca blanco (regla de la marca).
  final Color onAcento;

  /// Texto principal e iconos principales.
  final Color ink;

  /// Fondo de pantalla, de hojas y de la barra inferior.
  final Color paper;

  /// Superficie: tarjetas, campos, píldoras inactivas.
  final Color s;

  /// Superficie fuerte: pista de barras de progreso, botón apagado del conteo.
  final Color s2;

  /// Texto secundario, placeholders e iconos inactivos.
  final Color mute;

  /// Bordes de casillas sin marcar y pista del interruptor apagado.
  final Color line;

  /// Acción primaria / elemento activo (en oscuro es el azul de marca).
  final Color prim;

  /// Fondo de la tarjeta oscura "héroe".
  final Color hero;

  /// Fondo del aviso flotante y de la barra de lote.
  final Color toast;

  /// Verde (bien, cuadró, activo): fondo / texto.
  final Color gbg;
  final Color g;

  /// Rojo (error, faltante, sin stock): fondo / texto.
  final Color bbg;
  final Color b;

  /// Ámbar (aviso, poco stock, pendiente de separar): fondo / texto.
  final Color wbg;
  final Color w;

  /// Azul claro (informativo, seleccionado): fondo / texto.
  final Color ibg;
  final Color i;

  final bool oscuro;

  static const claro = TokensNs(
    ink: Color(0xFF121317),
    paper: Color(0xFFFFFFFF),
    s: Color(0xFFF3F4F7),
    s2: Color(0xFFE1E4EA),
    mute: Color(0xFF566070),
    line: Color(0xFFC4C9D4),
    prim: Color(0xFF121317),
    hero: Color(0xFF121317),
    toast: Color(0xFF121317),
    gbg: Color(0xFFE3F6EF),
    g: Color(0xFF0B6A52),
    bbg: Color(0xFFFBE0DE),
    b: Color(0xFFA4231B),
    wbg: Color(0xFFFDECD6),
    w: Color(0xFF7D3B03),
    ibg: Color(0xFFE0E9FF),
    i: Color(0xFF1D3A9A),
    oscuro: false,
    acento: Color(0xFF121317),
  );

  static const oscuroTokens = TokensNs(
    ink: Color(0xFFEEF0F4),
    paper: Color(0xFF0E0F13),
    s: Color(0xFF1A1D24),
    s2: Color(0xFF2A2E38),
    mute: Color(0xFFA0A8B6),
    line: Color(0xFF3B4150),
    prim: Color(0xFF2F5BE8),
    hero: Color(0xFF1C2231),
    toast: Color(0xFF2A2E38),
    gbg: Color(0xFF10342A),
    g: Color(0xFF63D9B0),
    bbg: Color(0xFF3A1613),
    b: Color(0xFFFF918A),
    wbg: Color(0xFF392510),
    w: Color(0xFFF5B56C),
    ibg: Color(0xFF17254F),
    i: Color(0xFFA3BCFF),
    oscuro: true,
    acento: Color(0xFF2F5BE8),
  );

  /// Nodo Gastro, claro: los colores de NodoSurPage/nodo.css.
  static const gastroClaro = TokensNs(
    ink: Color(0xFF1A1714),
    paper: Color(0xFFFFFFFF),
    s: Color(0xFFF5F4F2),
    s2: Color(0xFFECEAE6),
    mute: Color(0xFF57534E),
    line: Color(0xFFD6D2CC),
    prim: Color(0xFF1A1714),
    hero: Color(0xFF1A1714),
    toast: Color(0xFF000000),
    gbg: Color(0xFFE2F3EA),
    g: Color(0xFF1F7A4D),
    bbg: Color(0xFFFCE6E3),
    b: Color(0xFFC4291C),
    wbg: Color(0xFFFCEBDD),
    w: Color(0xFF9A3A07),
    ibg: Color(0xFFF5F4F2),
    i: Color(0xFF1A1714),
    oscuro: false,
    acento: Color(0xFFE4580B),
    onAcento: Color(0xFF1A1714),
  );

  /// Nodo Gastro, oscuro: de noche en la cocina cansa menos la vista. El primario es claro y lleva texto oscuro.
  static const gastroOscuro = TokensNs(
    ink: Color(0xFFF4F1EC),
    paper: Color(0xFF0F0E0D),
    s: Color(0xFF1B1917),
    s2: Color(0xFF272421),
    mute: Color(0xFFB8B1A9),
    line: Color(0xFF3A3632),
    prim: Color(0xFFF4F1EC),
    hero: Color(0xFF2A2724),
    toast: Color(0xFF000000),
    gbg: Color(0xFF12301F),
    g: Color(0xFF5FD49A),
    bbg: Color(0xFF3A1714),
    b: Color(0xFFFF7A6E),
    wbg: Color(0xFF3A1E0E),
    w: Color(0xFFFFA36B),
    ibg: Color(0xFF1B1917),
    i: Color(0xFFF4F1EC),
    oscuro: true,
    onPrim: Color(0xFF0F0E0D),
    acento: Color(0xFFF26A1B),
    onAcento: Color(0xFF140A03),
  );

  /// Los tokens de la edición para ese brillo.
  static TokensNs paraBrillo(Brightness brillo) => esEdicionGastronomia
      ? (brillo == Brightness.dark ? gastroOscuro : gastroClaro)
      : (brillo == Brightness.dark ? oscuroTokens : claro);

  // Colores fijos: no cambian con el tema (doc 01 §2.2).

  /// Azul de marca: "Nueva venta", botón central "Vender", medio Mercado Pago.
  static const marca = Color(0xFF2F5BE8);

  /// "Vender" cuando es la pestaña activa.
  static const marcaOscura = Color(0xFF1F3FA8);

  /// Ciruela del ícono de Nodo Sur Servicios (`DECISIONES.md`, 2026-10-14) y sus letras: la inicial del negocio en el menú
  /// lateral de la compu.
  static const ciruela = Color(0xFF5B1F45);
  static const ciruelaTexto = Color(0xFFF6E7EF);

  static const medioEfectivo = Color(0xFF0B7A5E);
  static const medioMercadoPago = marca;
  static const medioDebito = Color(0xFF4B5563);
  static const medioMixto = Color(0xFFB45309);

  /// Globo rojo de notificaciones (texto blanco).
  static const globo = Color(0xFFD92D20);

  /// Punto de "actualización disponible" sobre Más.
  static const puntoActualizacion = Color(0xFFFF8A3D);

  /// Puntito del cartel "sin conexión".
  static const puntoSinConexion = Color(0xFFE08A1E);

  /// Anillo de foco y línea de escaneo.
  static const foco = Color(0xFF3B6CFF);

  /// Texto "Eliminar esta venta" sobre la tarjeta oscura de la venta abierta.
  static const eliminarSobreOscuro = Color(0xFFFFB4AD);

  /// Asa de las hojas: no se tematiza.
  static const asa = Color(0xFFD3D7DF);

  /// Velo detrás de una hoja.
  static const velo = Color(0x80121317);

  /// Línea fina de separación (listas clave/valor y agrupadas).
  static const lineaFina = Color(0x14121317);

  /// Contorno del botón "outline" (`inset 0 0 0 1.5px rgba(18,19,23,.12)`).
  static const contorno = Color(0x1F121317);

  /// Texto sobre fondos oscuros o azules.
  static const blanco = Color(0xFFFFFFFF);

  @override
  TokensNs copyWith() => this;

  @override
  TokensNs lerp(ThemeExtension<TokensNs>? other, double t) {
    if (other is! TokensNs) return this;
    return t < 0.5 ? this : other;
  }
}

extension TokensNsDelContexto on BuildContext {
  /// Los tokens del tema; si el árbol no tiene el tema del celular (una pantalla
  /// armada con el tema del escritorio), se toman los del brillo que tenga.
  TokensNs get ns {
    final tema = Theme.of(this);
    return tema.extension<TokensNs>() ?? TokensNs.paraBrillo(tema.brightness);
  }
}
