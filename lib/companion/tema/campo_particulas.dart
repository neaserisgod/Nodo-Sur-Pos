// Campo de partículas — la firma visual del rediseño (igual que el canvas de
// la web de Nodo Sur): puntos y rayitas de color que giran muy despacio
// alrededor de un centro. Va detrás del contenido de las piezas "hero".
//
// Cuida la batería: se pausa solo si el sistema pidió menos animaciones
// (`MediaQuery.disableAnimations`) o si `animar` es false, y en ese caso
// dibuja un solo cuadro estático. Sin animación no hay ticker, así que no
// frena `pumpAndSettle` en los tests.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class CampoParticulas extends StatefulWidget {
  const CampoParticulas({
    super.key,
    required this.colores,
    this.centro = const Alignment(0.55, -0.1),
    this.densidad = 1,
    this.animar = true,
  });

  /// Colores de las partículas (se reparten al azar, con semilla fija).
  final List<Color> colores;

  /// Centro del giro, en coordenadas de `Alignment` (-1..1).
  final Alignment centro;

  /// 1 = densidad normal; 0.5 = la mitad de partículas.
  final double densidad;

  final bool animar;

  @override
  State<CampoParticulas> createState() => _CampoParticulasState();
}

class _CampoParticulasState extends State<CampoParticulas> with SingleTickerProviderStateMixin {
  AnimationController? _reloj;

  bool get _animado => widget.animar && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animado) {
      _reloj ??= AnimationController(vsync: this, duration: const Duration(seconds: 240))..repeat();
    } else {
      _reloj?.dispose();
      _reloj = null;
    }
  }

  @override
  void dispose() {
    _reloj?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PintorParticulas(
            reloj: _reloj,
            colores: widget.colores,
            centro: widget.centro,
            densidad: widget.densidad,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particula {
  _Particula(this.angulo, this.radio, this.velocidad, this.largo, this.color, this.alfa, this.fase);
  final double angulo;
  final double radio;
  final double velocidad;
  final double largo;
  final Color color;
  final double alfa;
  final double fase;
}

class _PintorParticulas extends CustomPainter {
  _PintorParticulas({required this.reloj, required this.colores, required this.centro, required this.densidad})
      : super(repaint: reloj);

  final Animation<double>? reloj;
  final List<Color> colores;
  final Alignment centro;
  final double densidad;

  List<_Particula>? _cache;
  Size? _cacheTamanio;

  List<_Particula> _generar(Size tamanio) {
    if (_cache != null && _cacheTamanio == tamanio) return _cache!;
    final azar = math.Random(41);
    final n = (math.min(220, math.max(40, tamanio.width * tamanio.height / 2600)) * densidad).round();
    final maximo = math.sqrt(tamanio.width * tamanio.width + tamanio.height * tamanio.height) * 0.6;
    _cacheTamanio = tamanio;
    return _cache = [
      for (var i = 0; i < n; i++)
        _Particula(
          azar.nextDouble() * math.pi * 2,
          math.pow(azar.nextDouble(), 0.7).toDouble() * maximo,
          (azar.nextDouble() - 0.5) * 2,
          azar.nextDouble() < 0.4 ? 4 + azar.nextDouble() * 4 : 1.2 + azar.nextDouble(),
          colores[azar.nextInt(colores.length)],
          0.25 + azar.nextDouble() * 0.7,
          azar.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || colores.isEmpty) return;
    final t = (reloj?.value ?? 0) * 240; // segundos
    final cx = size.width * (centro.x + 1) / 2;
    final cy = size.height * (centro.y + 1) / 2;
    final pincel = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final p in _generar(size)) {
      final a = p.angulo + p.velocidad * 0.02 * t;
      final r = p.radio + math.sin(t * 0.6 + p.fase) * 6;
      final x = cx + math.cos(a) * r;
      final y = cy + math.sin(a) * r * 0.72;
      if (x < -10 || y < -10 || x > size.width + 10 || y > size.height + 10) continue;
      pincel.color = p.color.withValues(alpha: p.alfa);
      canvas.drawLine(Offset(x, y), Offset(x + math.cos(a) * p.largo, y + math.sin(a) * p.largo * 0.72), pincel);
    }
  }

  @override
  bool shouldRepaint(_PintorParticulas viejo) =>
      viejo.colores != colores || viejo.centro != centro || viejo.densidad != densidad;
}

/// Paletas listas: sobre fondo claro (puntos suaves) y sobre fondo negro.
const particulasSobreClaro = [Color(0xFF3B6CFF), Color(0xFF8A5CF6), Color(0xFFD36BB5), Color(0xFF9AA3B5), Color(0xFFC9CFDB)];
const particulasSobreNegro = [Color(0xFF7DA0FF), Color(0xFF4F7CFF), Color(0xFFB59BFF), Color(0xFF3A4A78), Color(0xFF2A3350)];
