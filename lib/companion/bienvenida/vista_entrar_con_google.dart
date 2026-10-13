// Entrar (o crear la cuenta) con Google: lo que se ve en "Entrá con tu cuenta" (mock 02g–02j). Solo la vista; el ingreso de
// verdad (elegir la cuenta, vincular el celular, tomar el perfil) lo sigue haciendo `pantalla_entrar_con_cuenta.dart`.
//
// Con Google no hay dos caminos: la primera vez que alguien entra, horsepos.com le crea la cuenta sola. Por eso es un
// solo botón y la pantalla lo dice, en vez de un "registrarse" aparte que haría lo mismo.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';

class VistaEntrarConGoogle extends StatelessWidget {
  const VistaEntrarConGoogle({
    super.key,
    required this.alEntrar,
    this.trabajando = false,
    this.error,
    this.alReintentar,
    this.alEntrarConNavegador,
    this.volverACuenta,
  });

  final VoidCallback alEntrar;

  /// Esperando a Google, tomando el perfil o bajando los datos: el botón muestra que está trabajando y no se puede
  /// tocar de nuevo.
  final bool trabajando;

  /// Qué salió mal, dicho para la persona (sin internet, la invitación era para otro mail, etc.).
  final String? error;

  /// Reintentar sin volver a abrir el navegador (cuando la cuenta ya quedó vinculada y falló otra cosa).
  final VoidCallback? alReintentar;

  /// La salida de siempre (abrir el navegador para entrar), cuando entrar con Google desde la app no anduvo: un teléfono sin
  /// servicios de Google, o la app todavía sin registrar en Google Cloud.
  final VoidCallback? alEntrarConNavegador;

  /// Se tocó "Agregar otra cuenta" y hay otra guardada en el celular: la salida para volver a ella sin entrar con ninguna.
  final ({String titulo, VoidCallback alTocar})? volverACuenta;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PaginaArranqueNs(
      titulo: 'Entrá con tu cuenta',
      bajada: kIsWeb ? 'Lo que hagas desde acá queda a tu nombre.' : 'Lo que hagas desde este celular queda a tu nombre.',
      cuerpo: [
        if (error != null) KeyedSubtree(key: const Key('entrar_error'), child: InfoNs(error!, tono: TonoNs.bad)),
        if (error != null && alReintentar != null)
          KeyedSubtree(key: const Key('entrar_reintentar'), child: BotonNs(texto: 'Reintentar', onTap: trabajando ? null : alReintentar, alto: 48, tamanio: 15, fondo: ns.s, color: ns.ink, rellenar: false, paddingH: 22)),
        _BotonGoogle(trabajando: trabajando, onTap: trabajando ? null : alEntrar),
        if (alEntrarConNavegador != null)
          KeyedSubtree(
            key: const Key('entrar_con_navegador'),
            child: BotonNs.secundario(context, 'Entrar con el navegador', trabajando ? null : alEntrarConNavegador),
          ),
        if (volverACuenta != null)
          KeyedSubtree(
            key: const Key('volver_a_cuenta'),
            child: BotonNs.secundario(context, 'Volver a ${volverACuenta!.titulo}', trabajando ? null : volverACuenta!.alTocar),
          ),
        const InfoNs('¿Primera vez? Tu cuenta se crea sola al entrar con Google. Es la misma de horsepos.com.'),
        const InfoNs('¿Te invitaron a un negocio? Entrá con el mismo mail al que te llegó la invitación.'),
        // En el navegador se entra en la misma pestaña y la app trabaja con internet (lo que carga queda guardado en el navegador).
        InfoNs(kIsWeb
            ? 'Entrás con tu cuenta de Google en esta misma pestaña. Lo que cargues queda guardado y llega solo a los otros equipos del negocio.'
            : 'Internet, una sola vez, para entrar. Después el celular sigue andando sin conexión.'),
      ],
    );
  }
}

/// El botón de Google: blanco con borde y la "G" de colores, como lo pide Google para "Continuar con Google".
class _BotonGoogle extends StatelessWidget {
  const _BotonGoogle({required this.trabajando, required this.onTap});

  final bool trabajando;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: trabajando ? 'Entrando' : 'Continuar con Google',
      child: Container(
        key: const Key('entrar_con_cuenta'),
        height: 56,
        decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(999), border: Border.all(color: ns.line, width: 1.5)),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: trabajando
              ? Row(
                  key: const ValueKey('trabajando'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: ns.mute)),
                    const SizedBox(width: 12),
                    Flexible(child: Text('Entrando…', overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w600, color: ns.mute))),
                  ],
                )
              : Row(
                  key: const ValueKey('listo'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 22, height: 22, child: CustomPaint(painter: _LogoGoogle())),
                    const SizedBox(width: 12),
                    Flexible(child: Text('Continuar con Google', overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w600, color: ns.ink))),
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
