// Movimiento del mock v4 (las reglas `transition`/`@keyframes` de `p1_head.html`), en piezas reutilizables. Todas
// respetan "reducir animaciones" del sistema (`MediaQuery.disableAnimations`): ahí lo que aparece ya está y lo que
// cambia cambia sin moverse. Nunca demoran lo que se tipea ni el cobro: el contenido nuevo se dibuja desde el primer
// cuadro y el movimiento solo lo acompaña.

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// `--ease`, `--back` (rebote) y `--quart` del CSS.
const curvaEase = Cubic(.2, .7, .1, 1);
const curvaBack = Cubic(.34, 1.85, .64, 1);
const curvaQuart = Cubic(.165, .84, .44, 1);

bool hayMovimiento(BuildContext context) => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

Duration ms(int n) => Duration(milliseconds: n);

/// Las animaciones en bucle (el aro que late, la ruedita) no corren bajo `flutter test`: no terminan nunca y
/// `pumpAndSettle` esperaría para siempre. En la app real siempre corren (salvo "reducir animaciones").
final bool bucleHabilitado = !Platform.environment.containsKey('FLUTTER_TEST');

/// Aparece una vez al montarse: sube [dy] px, se funde y (opcional) crece desde [escala]. Cubre los `@keyframes` del
/// mock que entran así: `.rv` (reveal: 10 px, 400 ms, ease), `tin` (tarjetas: 8 px, 300 ms), `up` (popovers: 18 px,
/// 220 ms, quart) y `msg` (línea nueva del carrito: 10 px + 0,96, 400 ms).
class Aparecer extends StatefulWidget {
  const Aparecer({
    super.key,
    this.dy = 10,
    this.escala = 1,
    this.duracion = const Duration(milliseconds: 400),
    this.demora = Duration.zero,
    this.curva = curvaEase,
    required this.child,
  });

  /// `.rv` del mock con la demora escalonada por posición (`min(i,4)*40ms`).
  Aparecer.revelar({Key? key, int orden = 0, required Widget child})
      : this(key: key, demora: Duration(milliseconds: (orden < 4 ? orden : 4) * 40), child: child);

  /// `tin` de las tarjetas de producto (`k*12ms`, hasta 14).
  Aparecer.tarjeta({Key? key, int orden = 0, required Widget child})
      : this(key: key, dy: 8, duracion: const Duration(milliseconds: 300), demora: Duration(milliseconds: (orden < 14 ? orden : 14) * 12), child: child);

  /// `up` de los popovers y el dropdown.
  const Aparecer.arriba({Key? key, Duration duracion = const Duration(milliseconds: 220), required Widget child})
      : this(key: key, dy: 18, duracion: duracion, curva: curvaQuart, child: child);

  /// `msg`: la línea recién agregada al carrito, la tira de la IA.
  const Aparecer.mensaje({Key? key, Duration duracion = const Duration(milliseconds: 400), required Widget child})
      : this(key: key, dy: 10, escala: .96, duracion: duracion, child: child);

  final double dy;
  final double escala;
  final Duration duracion;
  final Duration demora;
  final Curve curva;
  final Widget child;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.demora + widget.duracion);
  late final Animation<double> _k = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.demora.inMicroseconds / (widget.demora + widget.duracion).inMicroseconds, 1, curve: widget.curva),
  );
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (hayMovimiento(context)) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _k,
      child: widget.child,
      builder: (context, hijo) {
        final k = _k.value;
        // La curva puede pasarse de 1 un instante: la opacidad nunca.
        Widget w = Transform.translate(offset: Offset(0, (1 - k) * widget.dy), child: hijo);
        if (widget.escala != 1) w = Transform.scale(scale: widget.escala + (1 - widget.escala) * k, child: w);
        return Opacity(opacity: k.clamp(0.0, 1.0), child: w);
      },
    );
  }
}

/// `@keyframes pop`: un latido (1 → 1,045 → 1) cuando cambia [valor]. Con [alMontar] también late al aparecer (el
/// contador de una tarjeta, un medio de pago recién elegido).
class Pop extends StatefulWidget {
  const Pop({super.key, required this.valor, this.alMontar = false, this.duracion = const Duration(milliseconds: 450), this.escala = 1.045, required this.child});

  final Object? valor;
  final bool alMontar;
  final Duration duracion;
  final double escala;
  final Widget child;

  @override
  State<Pop> createState() => _PopState();
}

class _PopState extends State<Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duracion);
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (widget.alMontar && hayMovimiento(context)) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(Pop old) {
    super.didUpdateWidget(old);
    if (old.valor != widget.valor && hayMovimiento(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, hijo) {
        if (!_c.isAnimating) return hijo!;
        // 0 → 30 % sube con la curva ease, 30 → 100 % vuelve.
        final t = _c.value;
        final s = t < .3 ? curvaEase.transform(t / .3) : 1 - curvaEase.transform((t - .3) / .7);
        return Transform.scale(scale: 1 + (widget.escala - 1) * s, child: hijo);
      },
    );
  }
}

/// Número que cuenta (`countUp`/`tweenNum` del mock): al aparecer sube desde 0 en 700 ms; cuando cambia, va del valor
/// anterior al nuevo en 320 ms y late (`pop`). [formato] convierte el valor (en las mismas unidades que [valor]) a texto.
class NumeroQueCuenta extends StatefulWidget {
  const NumeroQueCuenta({
    super.key,
    required this.valor,
    required this.formato,
    required this.estilo,
    this.contarAlAparecer = true,
    this.latir = true,
    this.textAlign,
  });

  final int valor;
  final String Function(int) formato;
  final TextStyle estilo;
  final bool contarAlAparecer;
  final bool latir;
  final TextAlign? textAlign;

  @override
  State<NumeroQueCuenta> createState() => _NumeroQueCuentaState();
}

class _NumeroQueCuentaState extends State<NumeroQueCuenta> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  double _desde = 0;
  double _hasta = 0;
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    _hasta = widget.valor.toDouble();
    if (widget.contarAlAparecer && hayMovimiento(context) && widget.valor != 0) {
      _desde = 0;
      _c.duration = ms(700);
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(NumeroQueCuenta old) {
    super.didUpdateWidget(old);
    if (old.valor == widget.valor) return;
    _desde = _actual;
    _hasta = widget.valor.toDouble();
    if (hayMovimiento(context)) {
      _c.duration = ms(320);
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  double get _actual {
    final e = 1 - math.pow(1 - _c.value, 3).toDouble();
    return _desde + (_hasta - _desde) * e;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // La semántica lleva siempre el valor final: un lector de pantalla (o un test) nunca lee un número a medio contar.
    return Semantics(
      label: widget.formato(widget.valor),
      excludeSemantics: true,
      child: Pop(
        valor: widget.latir ? widget.valor : null,
        duracion: ms(500),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.isAnimating ? _actual.round() : widget.valor;
            return Text(widget.formato(v), style: widget.estilo, textAlign: widget.textAlign, maxLines: 1, softWrap: false);
          },
        ),
      ),
    );
  }
}

/// Hover que levanta (`.btn:hover`, `.medio:hover`, `.ci:hover`, `.hv:hover`): sube [dy] px en 300 ms con ease y, al
/// apretar, se achica a 0,98 (`:active`). [builder] recibe si el mouse está encima, para cambiar fondo o sombra.
class Levantable extends StatefulWidget {
  const Levantable({
    super.key,
    this.dy = 2,
    this.duracion = const Duration(milliseconds: 300),
    this.achicarAlApretar = true,
    this.habilitado = true,
    this.cursor = SystemMouseCursors.click,
    required this.builder,
  });

  final double dy;
  final Duration duracion;
  final bool achicarAlApretar;
  final bool habilitado;
  final MouseCursor cursor;
  final Widget Function(BuildContext context, bool encima) builder;

  @override
  State<Levantable> createState() => _LevantableState();
}

class _LevantableState extends State<Levantable> {
  bool _encima = false;
  bool _apretado = false;

  @override
  Widget build(BuildContext context) {
    final mov = hayMovimiento(context) && widget.habilitado;
    final dy = mov && _encima && !_apretado ? -widget.dy : 0.0;
    final escala = mov && _apretado && widget.achicarAlApretar ? .98 : 1.0;
    return MouseRegion(
      cursor: widget.habilitado ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() {
        _encima = false;
        _apretado = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _apretado = true),
        onPointerUp: (_) => setState(() => _apretado = false),
        onPointerCancel: (_) => setState(() => _apretado = false),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: dy),
          duration: widget.duracion,
          curve: curvaEase,
          builder: (context, y, hijo) => Transform.translate(
            offset: Offset(0, y),
            child: AnimatedScale(scale: escala, duration: ms(120), child: hijo),
          ),
          child: widget.builder(context, _encima && widget.habilitado),
        ),
      ),
    );
  }
}

/// `@keyframes ring` (`.ringp`): un aro azul que se agranda y se apaga, en bucle (1,8 s). Sin movimiento, un aro quieto.
class AnilloPulso extends StatefulWidget {
  const AnilloPulso({super.key, required this.color, this.diametro = 96, this.opacidad = 1});

  final Color color;
  final double diametro;
  final double opacidad;

  @override
  State<AnilloPulso> createState() => _AnilloPulsoState();
}

class _AnilloPulsoState extends State<AnilloPulso> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: ms(1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (hayMovimiento(context) && bucleHabilitado) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final k = curvaEase.transform(_c.value);
        final escala = _c.isAnimating ? .8 + .9 * k : 1.0;
        final op = _c.isAnimating ? .7 * (1 - k) : .5;
        return Opacity(
          opacity: (op * widget.opacidad).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: escala,
            child: Container(
              width: widget.diametro,
              height: widget.diametro,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: 3)),
            ),
          ),
        );
      },
    );
  }
}

/// `.spin`: gira sin parar (1 s por vuelta).
class Giro extends StatefulWidget {
  const Giro({super.key, required this.child});
  final Widget child;

  @override
  State<Giro> createState() => _GiroState();
}

class _GiroState extends State<Giro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: ms(1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (hayMovimiento(context) && bucleHabilitado && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _c, child: widget.child);
}

/// `.draw`: la tilde de "cobrada"/"aprobado" que se dibuja sola (600 ms, arranca a los 150 ms).
class TildeDibujada extends StatefulWidget {
  const TildeDibujada({super.key, required this.color, this.tamanio = 72, this.grosor = 2.6});

  final Color color;
  final double tamanio;
  final double grosor;

  @override
  State<TildeDibujada> createState() => _TildeDibujadaState();
}

class _TildeDibujadaState extends State<TildeDibujada> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: ms(750));
  late final Animation<double> _k = CurvedAnimation(parent: _c, curve: const Interval(.2, 1, curve: curvaEase));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value == 0 && !_c.isAnimating) {
      if (hayMovimiento(context)) {
        _c.forward();
      } else {
        _c.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _k,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.tamanio),
        painter: _PintorTilde(widget.color, widget.grosor, _k.value),
      ),
    );
  }
}

class _PintorTilde extends CustomPainter {
  _PintorTilde(this.color, this.grosor, this.k);
  final Color color;
  final double grosor;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(5, 12.5)
      ..lineTo(9.5, 17)
      ..lineTo(19, 7.5);
    final metricas = path.computeMetrics().toList();
    final total = metricas.fold<double>(0, (a, m) => a + m.length);
    var resto = total * k;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final m in metricas) {
      if (resto <= 0) break;
      canvas.drawPath(m.extractPath(0, math.min(resto, m.length)), p);
      resto -= m.length;
    }
  }

  @override
  bool shouldRepaint(_PintorTilde old) => old.k != k || old.color != color;
}

/// `.cbar`: la barrita que se vacía mientras se espera algo que pasa solo (la venta siguiente arranca a los 2,4 s).
class BarraRegresiva extends StatelessWidget {
  const BarraRegresiva({super.key, required this.duracion, required this.color, required this.fondo});

  final Duration duracion;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: ColoredBox(
          color: fondo,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: hayMovimiento(context) ? duracion : Duration.zero,
            builder: (context, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Algo que crece desde 0 hasta [factor] al aparecer (`.bar i` 700 ms, `.bars i` 600 ms con escalón de 25 ms):
/// [builder] recibe el factor actual (0..1) para dibujar el ancho o el alto.
class Crecer extends StatelessWidget {
  const Crecer({super.key, required this.factor, this.duracion = const Duration(milliseconds: 700), this.demora = Duration.zero, required this.builder});

  final double factor;
  final Duration duracion;
  final Duration demora;
  final Widget Function(BuildContext context, double factor) builder;

  @override
  Widget build(BuildContext context) {
    if (!hayMovimiento(context)) return builder(context, factor);
    return _CrecerAnimado(factor: factor, duracion: duracion, demora: demora, builder: builder);
  }
}

class _CrecerAnimado extends StatefulWidget {
  const _CrecerAnimado({required this.factor, required this.duracion, required this.demora, required this.builder});
  final double factor;
  final Duration duracion;
  final Duration demora;
  final Widget Function(BuildContext context, double factor) builder;

  @override
  State<_CrecerAnimado> createState() => _CrecerAnimadoState();
}

class _CrecerAnimadoState extends State<_CrecerAnimado> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.demora + widget.duracion)..forward();
  late final Animation<double> _k = CurvedAnimation(
    parent: _c,
    curve: Interval(widget.demora.inMicroseconds / (widget.demora + widget.duracion).inMicroseconds, 1, curve: curvaEase),
  );
  double _desde = 0;
  late double _hasta = widget.factor;

  @override
  void didUpdateWidget(_CrecerAnimado old) {
    super.didUpdateWidget(old);
    if (old.factor != widget.factor) {
      _desde = _desde + (_hasta - _desde) * _k.value;
      _hasta = widget.factor;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _k,
      builder: (context, _) => widget.builder(context, _desde + (_hasta - _desde) * _k.value),
    );
  }
}
