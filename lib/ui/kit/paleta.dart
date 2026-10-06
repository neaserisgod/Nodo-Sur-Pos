// Paleta del mock v4 de la PC (`NodoSurPC-v4.html`, variables CSS de `:root`), valor por valor, en claro y en oscuro.
//
// Por qué una paleta aparte de `ColoresPlazoleta`: el dueño pidió fidelidad 1:1 con el mock (2026-10-06) y el mock
// trabaja con más matices que los tres grises de la paleta vieja (`--s`, `--s2`, `--s3`, `--soft`, `--hair`...). Las
// pantallas hechas desde cero con el kit (`lib/ui/kit/`) leen SOLO de acá, con los mismos nombres que el CSS, así una
// medida o un color del mock se busca y se copia sin traducir.

import 'package:flutter/material.dart';

@immutable
class PaletaMock extends ThemeExtension<PaletaMock> {
  const PaletaMock({
    required this.tinta,
    required this.papel,
    required this.s,
    required this.s2,
    required this.s3,
    required this.mute,
    required this.soft,
    required this.linea,
    required this.pelo,
    required this.azul,
    required this.azulOscuro,
    required this.azulClaro,
    required this.prim,
    required this.sobrePrim,
    required this.hero,
    required this.sobreHero,
    required this.heroSub,
    required this.heroChip,
    required this.efe,
    required this.mix,
    required this.tar,
    required this.mp,
    required this.gbg,
    required this.g,
    required this.bbg,
    required this.b,
    required this.wbg,
    required this.w,
    required this.ibg,
    required this.i,
    required this.scrim,
    required this.navbg,
    required this.navbg2,
    required this.navline,
    required this.toast,
    required this.sobreToast,
    required this.oscuro,
  });

  /// `--ink`: texto principal y botones oscuros.
  final Color tinta;

  /// `--paper`: fondo de la ventana y tarjetas blancas.
  final Color papel;

  /// `--s`, `--s2`, `--s3`: bloque gris, su hover, y rieles/barras vacías.
  final Color s;
  final Color s2;
  final Color s3;

  /// `--mute` texto secundario, `--soft` texto tenue (cabeceras de tabla, "c/u").
  final Color mute;
  final Color soft;

  /// `--line` contorno de chips y botones `out`; `--hair` separadores finísimos.
  final Color linea;
  final Color pelo;

  /// `--blue`, `--blue-d` (hover) y `--blue-l` (fondo azul suave: tarjeta elegida, Asistente).
  final Color azul;
  final Color azulOscuro;
  final Color azulClaro;

  /// `--prim` / `--onprim`: el botón `.btn` por defecto (tinta en claro, azul en oscuro).
  final Color prim;
  final Color sobrePrim;

  /// `--hero` y lo que va encima (`--onhero`, `--herosub`, `--herochip`).
  final Color hero;
  final Color sobreHero;
  final Color heroSub;
  final Color heroChip;

  /// Colores de los medios: efectivo, mixto, tarjeta y Mercado Pago.
  final Color efe;
  final Color mix;
  final Color tar;
  final Color mp;

  /// Pares fondo/texto con significado: ok/ganancia, error, aviso, info.
  final Color gbg;
  final Color g;
  final Color bbg;
  final Color b;
  final Color wbg;
  final Color w;
  final Color ibg;
  final Color i;

  final Color scrim;
  final Color navbg;
  final Color navbg2;
  final Color navline;
  final Color toast;
  final Color sobreToast;
  final bool oscuro;

  /// `--focus`: el aro de foco (igual en los dos temas).
  static const foco = Color(0xFF3B6CFF);

  /// Insignia roja de la campanita (`.ci .bd`).
  static const rojoInsignia = Color(0xFFD93025);

  @override
  PaletaMock copyWith() => this;

  @override
  PaletaMock lerp(ThemeExtension<PaletaMock>? other, double t) {
    if (other is! PaletaMock) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PaletaMock(
      tinta: l(tinta, other.tinta),
      papel: l(papel, other.papel),
      s: l(s, other.s),
      s2: l(s2, other.s2),
      s3: l(s3, other.s3),
      mute: l(mute, other.mute),
      soft: l(soft, other.soft),
      linea: l(linea, other.linea),
      pelo: l(pelo, other.pelo),
      azul: l(azul, other.azul),
      azulOscuro: l(azulOscuro, other.azulOscuro),
      azulClaro: l(azulClaro, other.azulClaro),
      prim: l(prim, other.prim),
      sobrePrim: l(sobrePrim, other.sobrePrim),
      hero: l(hero, other.hero),
      sobreHero: l(sobreHero, other.sobreHero),
      heroSub: l(heroSub, other.heroSub),
      heroChip: l(heroChip, other.heroChip),
      efe: l(efe, other.efe),
      mix: l(mix, other.mix),
      tar: l(tar, other.tar),
      mp: l(mp, other.mp),
      gbg: l(gbg, other.gbg),
      g: l(g, other.g),
      bbg: l(bbg, other.bbg),
      b: l(b, other.b),
      wbg: l(wbg, other.wbg),
      w: l(w, other.w),
      ibg: l(ibg, other.ibg),
      i: l(i, other.i),
      scrim: l(scrim, other.scrim),
      navbg: l(navbg, other.navbg),
      navbg2: l(navbg2, other.navbg2),
      navline: l(navline, other.navline),
      toast: l(toast, other.toast),
      sobreToast: l(sobreToast, other.sobreToast),
      oscuro: t < 0.5 ? oscuro : other.oscuro,
    );
  }
}

const paletaMockClara = PaletaMock(
  tinta: Color(0xFF121317),
  papel: Color(0xFFFFFFFF),
  s: Color(0xFFF3F4F7),
  s2: Color(0xFFE6E9EF),
  s3: Color(0xFFDDE1E9),
  mute: Color(0xFF566070),
  soft: Color(0xFF7B8494),
  linea: Color(0x1F121317), // rgba(18,19,23,.12)
  pelo: Color(0x12121317), // rgba(18,19,23,.07)
  azul: Color(0xFF2F5BE8),
  azulOscuro: Color(0xFF1F3FA8),
  azulClaro: Color(0xFFE8EDFF),
  prim: Color(0xFF121317),
  sobrePrim: Color(0xFFFFFFFF),
  hero: Color(0xFF121317),
  sobreHero: Color(0xFFFFFFFF),
  heroSub: Color(0x9EFFFFFF), // .62
  heroChip: Color(0x1AFFFFFF), // .1
  efe: Color(0xFF0B7A5E),
  mix: Color(0xFFB45309),
  tar: Color(0xFF4B5563),
  mp: Color(0xFF2F5BE8),
  gbg: Color(0xFFE3F6EF),
  g: Color(0xFF0B6A52),
  bbg: Color(0xFFFBE0DE),
  b: Color(0xFFA4231B),
  wbg: Color(0xFFFDECD6),
  w: Color(0xFF7D3B03),
  ibg: Color(0xFFE0E9FF),
  i: Color(0xFF1D3A9A),
  scrim: Color(0x75121317), // .46
  navbg: Color(0xA8FFFFFF), // .66
  navbg2: Color(0xE6FFFFFF), // .9
  navline: Color(0x140D1017), // rgba(13,16,23,.08)
  toast: Color(0xFF121317),
  sobreToast: Color(0xFFFFFFFF),
  oscuro: false,
);

const paletaMockOscura = PaletaMock(
  tinta: Color(0xFFEEF0F4),
  papel: Color(0xFF0E0F13),
  s: Color(0xFF171A21),
  s2: Color(0xFF232733),
  s3: Color(0xFF2D3240),
  mute: Color(0xFFA0A8B6),
  soft: Color(0xFF7E8696),
  linea: Color(0x29FFFFFF), // .16
  pelo: Color(0x14FFFFFF), // .08
  azul: Color(0xFF3D68F2),
  azulOscuro: Color(0xFF2F5BE8),
  azulClaro: Color(0xFF17254F),
  prim: Color(0xFF3D68F2),
  sobrePrim: Color(0xFFFFFFFF),
  hero: Color(0xFF1C2231),
  sobreHero: Color(0xFFFFFFFF),
  heroSub: Color(0x9EFFFFFF),
  heroChip: Color(0x1AFFFFFF),
  efe: Color(0xFF0B7A5E),
  mix: Color(0xFFB45309),
  tar: Color(0xFF4B5563),
  mp: Color(0xFF2F5BE8),
  gbg: Color(0xFF10342A),
  g: Color(0xFF63D9B0),
  bbg: Color(0xFF3A1613),
  b: Color(0xFFFF918A),
  wbg: Color(0xFF392510),
  w: Color(0xFFF5B56C),
  ibg: Color(0xFF17254F),
  i: Color(0xFFA3BCFF),
  scrim: Color(0x9E000000), // .62
  navbg: Color(0x9E0E0F13), // .62
  navbg2: Color(0xE60E0F13), // .9
  navline: Color(0x1AFFFFFF), // .1
  toast: Color(0xFF2A2E38),
  sobreToast: Color(0xFFEEF0F4),
  oscuro: true,
);

/// Colores de rubro de los avatares de producto (`NS.CATC` del mock): pares fondo/letra. Una categoría sin par propio
/// toma uno de la lista por su posición, así el mismo rubro tiene siempre el mismo color.
const List<(Color, Color)> paresRubro = [
  (Color(0xFFE3F6EF), Color(0xFF0B6A52)), // Bebidas
  (Color(0xFFFDECD6), Color(0xFF7D3B03)), // Almacén
  (Color(0xFFFBE0DE), Color(0xFFA4231B)), // Fiambres
  (Color(0xFFE0E9FF), Color(0xFF1D3A9A)), // Lácteos
  (Color(0xFFF1E6FF), Color(0xFF6B2FB3)), // Golosinas
  (Color(0xFFE6E9EF), Color(0xFF3B4150)), // Cigarrillos
  (Color(0xFFFFF0C9), Color(0xFF7A5A00)), // Panificados
];

const Map<String, int> _rubroPorNombre = {
  'bebidas': 0,
  'almacen': 1,
  'fiambres': 2,
  'fiambreria': 2,
  'lacteos': 3,
  'golosinas': 4,
  'cigarrillos': 5,
  'panificados': 6,
  'panaderia': 6,
};

String _sinAcentos(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .trim();

/// Par fondo/letra del avatar de un producto según su rubro. [indice] desempata rubros que el mock no nombra.
(Color, Color) parDeRubro(String? nombreRubro, {int indice = 0}) {
  final porNombre = nombreRubro == null ? null : _rubroPorNombre[_sinAcentos(nombreRubro)];
  return paresRubro[(porNombre ?? indice).abs() % paresRubro.length];
}

extension PaletaDelContexto on BuildContext {
  /// La paleta del mock del tema actual. Si el tema no la trae (un test que arma su propio `ThemeData`), la clara.
  PaletaMock get p => Theme.of(this).extension<PaletaMock>() ?? paletaMockClara;
}
