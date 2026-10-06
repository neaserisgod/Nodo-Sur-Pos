// Íconos de trazo del mock v4 de la PC (`IC` en `p3_core.js`): grilla 24×24, trazo de 2, extremos redondeados. Se
// dibujan desde el mismo texto SVG que usa el mock (`pathDeSvg`, compartido con el celular), así son idénticos.

import 'package:flutter/material.dart';

import '../../companion/kit/iconos_ns.dart' show pathDeSvg;

enum Ic {
  home('M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10'),
  cart('M3 4h2l2.4 10.5a1 1 0 001 .8h8.9a1 1 0 001-.7L20 8H6.2M9 20h.01M17 20h.01'),
  box('M12 3l8 4v10l-8 4-8-4V7zM4 7l8 4 8-4M12 11v10'),
  wallet('M3 7h15a3 3 0 013 3v8a3 3 0 01-3 3H6a3 3 0 01-3-3V7zM3 7l12-4v4M17 14h.01'),
  dots('M5 12h.01M12 12h.01M19 12h.01'),
  scan('M3 7V5a2 2 0 012-2h2M17 3h2a2 2 0 012 2v2M21 17v2a2 2 0 01-2 2h-2M7 21H5a2 2 0 01-2-2v-2M7 12h10'),
  swap('M7 7h13l-3-3M17 17H4l3 3'),
  clip('M9 4h6v3H9zM7 5H6a2 2 0 00-2 2v13a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1M8 12h8M8 16h5'),
  sliders('M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M14 4v4M8 10v4M16 16v4'),
  cal('M4 6h16v14H4zM4 10h16M8 3v4M16 3v4'),
  down('M12 4v12M7 11l5 5 5-5M5 20h14'),
  cash('M3 7h18v10H3zM12 10a2 2 0 100 4 2 2 0 000-4zM6 10v.01M18 14v.01'),
  card('M3 6h18v12H3zM3 10h18M7 15h3'),
  search('M11 4a7 7 0 100 14 7 7 0 000-14zM20 20l-3.5-3.5'),
  bell('M6 9a6 6 0 0112 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9zM10 20a2 2 0 004 0'),
  back('M15 6l-6 6 6 6'),
  chev('M9 6l6 6-6 6'),
  chevd('M6 9l6 6 6-6'),
  arrow('M5 12h14M13 6l6 6-6 6'),
  plus('M12 5v14M5 12h14'),
  minus('M5 12h14'),
  check('M5 12.5l4.5 4.5L19 7.5'),
  lock('M6 11h12v10H6zM8 11V7a4 4 0 018 0v4'),
  warn('M12 4l9 16H3zM12 10v4M12 17h.01'),
  save('M5 4h11l3 3v13H5zM8 4v5h7V4M8 20v-6h8v6'),
  calc('M5 3h14v18H5zM8 7h8M8 12h.01M12 12h.01M16 12h.01M8 16h.01M12 16h.01M16 16h.01'),
  x('M6 6l12 12M18 6L6 18'),
  pc('M3 4h18v12H3zM8 20h8M12 16v4'),
  trash('M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3'),
  store('M4 9l1.5-5h13L20 9M4 9v11h16V9M4 9h16M9 20v-6h6v6'),
  clock('M12 4a8 8 0 100 16 8 8 0 000-16zM12 8v4l3 2'),
  print('M7 8V4h10v4M7 17H4v-7h16v7h-3M7 14h10v6H7z'),
  edit('M4 20h4L19 9l-4-4L4 16zM13 7l4 4'),
  phone('M8 3h8a1 1 0 011 1v16a1 1 0 01-1 1H8a1 1 0 01-1-1V4a1 1 0 011-1zM11 18h2'),
  sun('M12 8a4 4 0 100 8 4 4 0 000-8zM12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5'),
  chart('M4 20V10M10 20V4M16 20v-8M22 20H2'),
  truck('M3 6h11v10H3zM14 9h4l3 3v4h-7M7 19a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM17 19a1.5 1.5 0 100-3 1.5 1.5 0 000 3z'),
  list('M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01'),
  percent('M6 18L18 6M7.5 6.5a1.5 1.5 0 100 .01M16.5 17.5a1.5 1.5 0 100 .01'),
  wifi('M2 8.8a15 15 0 0120 0M5 12.5a10 10 0 0114 0M8.5 16a5 5 0 017 0M12 20h.01'),
  wifioff(
    'M3 3l18 18M2 8.8a15 15 0 015-3M10 5.2a15 15 0 0112 3.6M5 12.5a10 10 0 015.5-2.8M14 9.7a10 10 0 015 2.8M8.5 16a5 5 0 013-1.4M15.5 16a5 5 0 00-1.5-1.4M12 20h.01',
  ),
  reload('M20 11a8 8 0 10-2.3 5.7M20 4v7h-7'),
  mp('M4 7h16v10H4zM8 12h8M12 9v6'),
  smoke('M3 15h14v3H3zM19 15h2v3h-2zM18 5c0 2 2 2 2 4'),
  user('M12 4a4 4 0 100 8 4 4 0 000-8zM4 21a8 8 0 0116 0'),
  users('M9 5a3.5 3.5 0 100 7 3.5 3.5 0 000-7zM2.5 20a6.5 6.5 0 0113 0M17 6a3 3 0 010 6M18 14.5a6 6 0 013.5 5.5'),
  tag('M3 12V4h8l10 10-8 8zM7.5 8h.01'),
  file('M6 3h8l5 5v13H6zM14 3v5h5M9 13h6M9 17h6'),
  shield('M12 3l8 3v6c0 5-3.4 8.2-8 9-4.6-.8-8-4-8-9V6z'),
  info('M12 3a9 9 0 100 18 9 9 0 000-18zM12 11v5M12 8h.01'),
  bolt('M13 3L5 14h6l-1 7 8-11h-6z'),
  image('M4 5h16v14H4zM4 16l5-5 4 4 3-3 4 4M9 9h.01'),
  key('M14 10a4 4 0 11-3.9-3A4 4 0 0114 10zM11 12l-8 8v-3M6 17H3'),
  cloud('M7 18a4 4 0 010-8 5.5 5.5 0 0110.6 1.2A3.4 3.4 0 0117 18z'),
  star('M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z'),
  gear(
    'M12.22 2h-.44a2 2 0 00-2 2v.18a2 2 0 01-1 1.73l-.43.25a2 2 0 01-2 0l-.15-.08a2 2 0 00-2.73.73l-.22.38a2 2 0 00.73 2.73l.15.1a2 2 0 011 1.72v.51a2 2 0 01-1 1.74l-.15.09a2 2 0 00-.73 2.73l.22.38a2 2 0 002.73.73l.15-.08a2 2 0 012 0l.43.25a2 2 0 011 1.73V20a2 2 0 002 2h.44a2 2 0 002-2v-.18a2 2 0 011-1.73l.43-.25a2 2 0 012 0l.15.08a2 2 0 002.73-.73l.22-.39a2 2 0 00-.73-2.73l-.15-.08a2 2 0 01-1-1.74v-.5a2 2 0 011-1.74l.15-.09a2 2 0 00.73-2.73l-.22-.38a2 2 0 00-2.73-.73l-.15.08a2 2 0 01-2 0l-.43-.25a2 2 0 01-1-1.73V4a2 2 0 00-2-2zM12 9a3 3 0 100 6 3 3 0 000-6z',
  ),
  min('M5 19h14'),
  sq('M5 5h14v14H5z'),
  sparkle('M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9zM19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z'),
  undo('M9 14L4 9l5-5M4 9h10a6 6 0 010 12h-3');

  const Ic(this.trazo);
  final String trazo;
}

/// Un ícono del mock. [grosor] es el `stroke-width` sobre la grilla de 24 (el mock usa 1.9–2.6 según el lugar).
class Icono extends StatelessWidget {
  const Icono(this.ic, {super.key, this.size = 22, this.color, this.grosor = 2, this.etiqueta});

  final Ic ic;
  final double size;
  final Color? color;
  final double grosor;

  /// Texto para lectores de pantalla (y para encontrarlo en los tests); sin él el ícono es decorativo.
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final dibujo = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Pintor(ic, c, grosor)),
    );
    if (etiqueta == null) return ExcludeSemantics(child: dibujo);
    return Semantics(label: etiqueta, child: dibujo);
  }
}

class _Pintor extends CustomPainter {
  _Pintor(this.ic, this.color, this.grosor);

  final Ic ic;
  final Color color;
  final double grosor;

  static final Map<Ic, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cache.putIfAbsent(ic, () => pathDeSvg(ic.trazo));
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = grosor
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Pintor old) => old.ic != ic || old.color != color || old.grosor != grosor;
}
