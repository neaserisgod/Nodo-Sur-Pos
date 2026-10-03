// Entrar (o crear la cuenta) con Google: lo que se ve en "Entrá con tu cuenta". Solo la vista; el ingreso de verdad
// (abrir el navegador, vincular el celular, tomar el perfil) lo sigue haciendo `pantalla_entrar_con_cuenta.dart`.
//
// Con Google no hay dos caminos: la primera vez que alguien entra, horsepos.com le crea la cuenta sola. Por eso es un
// solo botón y la pantalla lo dice, en vez de un "registrarse" aparte que haría lo mismo.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import '../tema/campo_particulas.dart';
import '../tema/tema_companion.dart';
import 'aparecer.dart';
import 'marca_nodo_sur.dart';

class VistaEntrarConGoogle extends StatelessWidget {
  const VistaEntrarConGoogle({
    super.key,
    required this.alEntrar,
    this.trabajando = false,
    this.error,
    this.alReintentar,
  });

  final VoidCallback alEntrar;

  /// Esperando a Google, tomando el perfil o bajando los datos: el botón muestra que está trabajando y no se puede
  /// tocar de nuevo.
  final bool trabajando;

  /// Qué salió mal, dicho para la persona (sin internet, la invitación era para otro mail, etc.).
  final String? error;

  /// Reintentar sin volver a abrir el navegador (cuando la cuenta ya quedó vinculada y falló otra cosa).
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CampoParticulas(
              colores: oscuro ? particulasSobreNegro : particulasSobreClaro,
              centro: const Alignment(0, -0.35),
              densidad: 0.7,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, caja) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xxl, Espaciado.xl, Espaciado.xl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: caja.maxHeight - Espaciado.xxl - Espaciado.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Aparecer(orden: 0, child: Center(child: MarcaNodoSur(tamanio: 64))),
                      const SizedBox(height: Espaciado.xl),
                      Aparecer(
                        orden: 1,
                        child: Text('Entrá con tu cuenta', textAlign: TextAlign.center, style: textTheme.displayLarge?.copyWith(fontSize: 40)),
                      ),
                      const SizedBox(height: Espaciado.md),
                      Aparecer(
                        orden: 2,
                        child: Text(
                          'Lo que hagas desde este celular queda a tu nombre.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(color: colores.textoSecundario),
                        ),
                      ),
                      const SizedBox(height: Espaciado.xxl),
                      if (error != null) ...[
                        Aparecer(orden: 0, child: _Aviso(texto: error!)),
                        const SizedBox(height: Espaciado.lg),
                      ],
                      Aparecer(orden: 3, child: _BotonGoogle(trabajando: trabajando, onPressed: trabajando ? null : alEntrar)),
                      if (error != null && alReintentar != null) ...[
                        const SizedBox(height: Espaciado.sm),
                        SizedBox(
                          height: alturaControlCompanion,
                          child: OutlinedButton(key: const Key('entrar_reintentar'), onPressed: trabajando ? null : alReintentar, child: const Text('Reintentar')),
                        ),
                      ],
                      const SizedBox(height: Espaciado.lg),
                      Aparecer(
                        orden: 4,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '¿Primera vez? '),
                              TextSpan(text: 'Tu cuenta se crea sola', style: TextStyle(color: colores.textoPrimario, fontWeight: FontWeight.w600)),
                              const TextSpan(text: ' al entrar con Google. Es la misma de horsepos.com.'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: Espaciado.xxl),
                      Aparecer(
                        orden: 5,
                        child: Container(
                          padding: const EdgeInsets.all(Espaciado.lg),
                          decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
                          child: Column(
                            children: [
                              _Nota(
                                icono: Icons.group_outlined,
                                titulo: '¿Te invitaron a un negocio?',
                                detalle: 'Entrá con el mismo mail al que te llegó la invitación.',
                              ),
                              const SizedBox(height: Espaciado.md),
                              _Nota(
                                icono: Icons.wifi_off_rounded,
                                titulo: 'Internet, una sola vez',
                                detalle: 'Se abre el navegador para entrar. Después el celular sigue andando sin conexión.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El botón de Google: blanco con borde y la "G" de colores, como lo pide Google para "Continuar con Google".
class _BotonGoogle extends StatelessWidget {
  const _BotonGoogle({required this.trabajando, required this.onPressed});

  final bool trabajando;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: alturaControlCompanion + 4,
      child: OutlinedButton(
        key: const Key('entrar_con_cuenta'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: oscuro ? const Color(0xFF131314) : Colors.white,
          foregroundColor: oscuro ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F),
          disabledForegroundColor: colores.textoSecundario,
          side: BorderSide(color: oscuro ? const Color(0xFF8E918F) : const Color(0xFF747775)),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: familiaTipografica, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: trabajando
              ? Row(
                  key: const ValueKey('trabajando'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: colores.textoSecundario)),
                    const SizedBox(width: Espaciado.md),
                    const Flexible(child: Text('Entrando…', overflow: TextOverflow.ellipsis)),
                  ],
                )
              : const Row(
                  key: ValueKey('listo'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 22, height: 22, child: CustomPaint(painter: _LogoGoogle())),
                    SizedBox(width: Espaciado.md),
                    Flexible(child: Text('Continuar con Google', overflow: TextOverflow.ellipsis)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// La "G" de Google en sus cuatro colores, dibujada (sin asset).
class _LogoGoogle extends CustomPainter {
  const _LogoGoogle();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final grosor = s * 0.2;
    final r = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: (s - grosor) / 2);
    Paint pincel(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;
    const rad = 3.14159265 / 180;
    canvas.drawArc(r, -40 * rad, -95 * rad, false, pincel(const Color(0xFFEA4335))); // rojo, arriba
    canvas.drawArc(r, -135 * rad, -90 * rad, false, pincel(const Color(0xFFFBBC05))); // amarillo, izquierda
    canvas.drawArc(r, 135 * rad, -95 * rad, false, pincel(const Color(0xFF34A853))); // verde, abajo
    canvas.drawArc(r, 40 * rad, -40 * rad, false, pincel(const Color(0xFF4285F4))); // azul, derecha
    // La barra horizontal de la G.
    canvas.drawRect(Rect.fromLTWH(s / 2, s / 2 - grosor / 2, s / 2 - grosor / 2 + grosor / 2, grosor), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(_LogoGoogle viejo) => false;
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      key: const Key('entrar_error'),
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(
        color: colores.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radioSuperficieCompanion),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colores.error, size: 22),
          const SizedBox(width: Espaciado.md),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colores.error))),
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota({required this.icono, required this.titulo, required this.detalle});

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: colores.fondo, shape: BoxShape.circle),
          child: Icon(icono, size: 20, color: colores.textoPrimario),
        ),
        const SizedBox(width: Espaciado.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(detalle, style: textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
