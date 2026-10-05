// Iconos del mock, con los trazos exactos del doc 01 §4.1: grilla 24×24, sin
// relleno, extremos y uniones redondeados. Se dibujan con un `CustomPainter`
// a partir del texto del path SVG, así el icono es idéntico al del mock y
// toma su color del token que le toque (no de la fuente de Material Icons).

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Trazos del catálogo del mock (viewBox 0 0 24 24).
enum IconoNs {
  inicio('M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10'),
  carrito('M3 4h2l2.4 10.5a1 1 0 001 .8h8.9a1 1 0 001-.7L20 8H6.2M9 20h.01M17 20h.01'),
  producto('M12 3l8 4v10l-8 4-8-4V7zM4 7l8 4 8-4M12 11v10'),
  billetera('M3 7h15a3 3 0 013 3v8a3 3 0 01-3 3H6a3 3 0 01-3-3V7zM3 7l12-4v4M17 14h.01'),
  mas('M5 12h.01M12 12h.01M19 12h.01'),
  escanear('M3 7V5a2 2 0 012-2h2M17 3h2a2 2 0 012 2v2M21 17v2a2 2 0 01-2 2h-2M7 21H5a2 2 0 01-2-2v-2M7 12h10'),
  intercambio('M7 7h13l-3-3M17 17H4l3 3'),
  portapapeles('M9 4h6v3H9zM7 5H6a2 2 0 00-2 2v13a2 2 0 002 2h12a2 2 0 002-2V7a2 2 0 00-2-2h-1M8 12h8M8 16h5'),
  ajustes('M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M14 4v4M8 10v4M16 16v4'),
  calendario('M4 6h16v14H4zM4 10h16M8 3v4M16 3v4'),
  enchufe('M9 7V3M15 7V3M6 7h12v4a6 6 0 01-12 0zM12 17v4'),
  descarga('M12 4v12M7 11l5 5 5-5M5 20h14'),
  billetes('M3 7h18v10H3zM12 10a2 2 0 100 4 2 2 0 000-4zM6 10v.01M18 14v.01'),
  tarjeta('M3 6h18v12H3zM3 10h18M7 15h3'),
  lupa('M11 4a7 7 0 100 14 7 7 0 000-14zM20 20l-3.5-3.5'),
  campana('M6 9a6 6 0 0112 0c0 6 2.5 7.5 2.5 7.5h-17S6 15 6 9zM10 20a2 2 0 004 0'),
  volver('M15 6l-6 6 6 6'),
  chevron('M9 6l6 6-6 6'),
  masMas('M12 5v14M5 12h14'),
  menos('M5 12h14'),
  tilde('M5 12.5l4.5 4.5L19 7.5'),
  candado('M6 11h12v10H6zM8 11V7a4 4 0 018 0v4'),
  alerta('M12 4l9 16H3zM12 10v4M12 17h.01'),
  guardar('M5 4h11l3 3v13H5zM8 4v5h7V4M8 20v-6h8v6'),
  calculadora('M5 3h14v18H5zM8 7h8M8 12h.01M12 12h.01M16 12h.01M8 16h.01M12 16h.01M16 16h.01'),
  cerrar('M6 6l12 12M18 6L6 18'),
  computadora('M3 4h18v12H3zM8 20h8M12 16v4'),
  sinWifi('M2 8.8a15 15 0 0120 0M5 12.5a10 10 0 0114 0M8.5 16a5 5 0 017 0M12 20h.01M4 4l16 16'),
  celular('M7 3h10a1 1 0 011 1v16a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1zM11 18h2'),
  sinNube('M3 3l18 18M7.5 18A4.5 4.5 0 016 9.2a6 6 0 0110.8-1M17.5 18H11'),
  reintentar('M20 12a8 8 0 11-2.3-5.7M20 4v5h-5'),
  papelera('M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 002 2h6a2 2 0 002-2l1-12M9 7V4h6v3'),
  camion('M3 6h11v10H3zM14 9h4l3 3v4h-7M7 19a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM17 19a1.5 1.5 0 100-3 1.5 1.5 0 000 3z'),
  editar('M4 20h4L19 9l-4-4L4 16zM13 7l4 4'),
  imprimir('M7 8V4h10v4M7 17H4v-7h16v7h-3M7 14h10v6H7z'),
  reloj('M12 4a8 8 0 100 16 8 8 0 000-16zM12 8v4l3 2'),
  tienda('M4 9l1.5-5h13L20 9M4 9v11h16V9M4 9h16M9 20v-6h6v6'),
  porcentaje('M6 18L18 6M7.5 6.5a1.5 1.5 0 100 .01M16.5 17.5a1.5 1.5 0 100 .01'),
  alertaCirculo('M12 8v5M12 16.5h.01M12 3a9 9 0 100 18 9 9 0 000-18z');

  const IconoNs(this.trazo);

  /// Texto `d` del path SVG.
  final String trazo;
}

/// Convierte el texto `d` de un path SVG a un [Path]. Soporta lo que usa el
/// catálogo: M, L, H, V, C, A, Z (absolutos y relativos).
Path pathDeSvg(String d) {
  final trozos = RegExp(r'([MmLlHhVvCcSsAaZz])|(-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?)').allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var x = 0.0, y = 0.0;
  var inicioX = 0.0, inicioY = 0.0;
  String? cmd;
  // Último punto de control de una curva cúbica, para reflejarlo en `S`.
  var ultimoCx = 0.0, ultimoCy = 0.0;
  var venciaCurva = false;
  double n() => double.parse(trozos[i++]);

  while (i < trozos.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(trozos[i])) cmd = trozos[i++];
    final c = cmd!;
    final rel = c == c.toLowerCase();
    final eraCurva = venciaCurva;
    venciaCurva = false;
    final mayus = c.toUpperCase();
    if (mayus == 'S') venciaCurva = eraCurva;
    switch (mayus) {
      case 'M':
        final nx = n(), ny = n();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        inicioX = x;
        inicioY = y;
        path.moveTo(x, y);
        // Los pares siguientes de un M son L implícitos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        final nx = n(), ny = n();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'H':
        final nx = n();
        x = rel ? x + nx : nx;
        path.lineTo(x, y);
      case 'V':
        final ny = n();
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'C':
        final x1 = n(), y1 = n(), x2 = n(), y2 = n(), x3 = n(), y3 = n();
        final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
        path.cubicTo(ox + x1, oy + y1, ox + x2, oy + y2, ox + x3, oy + y3);
        ultimoCx = ox + x2;
        ultimoCy = oy + y2;
        x = ox + x3;
        y = oy + y3;
        venciaCurva = true;
      case 'S':
        final sx2 = n(), sy2 = n(), sx3 = n(), sy3 = n();
        final sox = rel ? x : 0.0, soy = rel ? y : 0.0;
        final c1x = eraCurva ? 2 * x - ultimoCx : x;
        final c1y = eraCurva ? 2 * y - ultimoCy : y;
        path.cubicTo(c1x, c1y, sox + sx2, soy + sy2, sox + sx3, soy + sy3);
        ultimoCx = sox + sx2;
        ultimoCy = soy + sy2;
        x = sox + sx3;
        y = soy + sy3;
        venciaCurva = true;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final grande = _bandera(trozos, () => i, (v) => i = v);
        final barrido = _bandera(trozos, () => i, (v) => i = v);
        final nx = n(), ny = n();
        final ex = rel ? x + nx : nx, ey = rel ? y + ny : ny;
        path.arcToPoint(
          Offset(ex, ey),
          radius: Radius.elliptical(rx, ry),
          rotation: rot * math.pi / 180,
          largeArc: grande,
          clockwise: barrido,
        );
        x = ex;
        y = ey;
      case 'Z':
        path.close();
        x = inicioX;
        y = inicioY;
        cmd = null;
    }
  }
  return path;
}

/// Las banderas del arco pueden venir pegadas ("a4 4 0 018 0v4": `0 1 8 0`).
bool _bandera(List<String> trozos, int Function() leer, void Function(int) fijar) {
  final pos = leer();
  final t = trozos[pos];
  if (t == '0' || t == '1') {
    fijar(pos + 1);
    return t == '1';
  }
  // Pegadas a lo que sigue: "018" → bandera '0', bandera '1' y "8" sigue.
  final bandera = t[0] == '1';
  final resto = t.substring(1);
  if (resto.isEmpty) {
    fijar(pos + 1);
  } else {
    trozos[pos] = resto;
  }
  return bandera;
}

class IconoNsWidget extends StatelessWidget {
  const IconoNsWidget(this.icono, {super.key, this.tamanio = 22, this.color, this.grosor = 2});

  final IconoNs icono;
  final double tamanio;
  final Color? color;
  final double grosor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: tamanio,
      height: tamanio,
      child: CustomPaint(painter: _PintorIcono(icono, c, grosor)),
    );
  }
}

class _PintorIcono extends CustomPainter {
  _PintorIcono(this.icono, this.color, this.grosor);

  final IconoNs icono;
  final Color color;
  final double grosor;

  static final Map<IconoNs, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cache.putIfAbsent(icono, () => pathDeSvg(icono.trazo));
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        // El trazo se mide en la grilla de 24, igual que en el SVG del mock.
        ..strokeWidth = grosor
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorIcono old) => old.icono != icono || old.color != color || old.grosor != grosor;
}
