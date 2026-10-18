// Entrar (o crear la cuenta) con Google. Solo la vista; el ingreso de
// verdad (elegir la cuenta, vincular el celular, tomar el perfil) lo sigue haciendo `pantalla_entrar_con_cuenta.dart`.
//
// Con Google no hay dos caminos: la primera vez que alguien entra, horsepos.com le crea la cuenta sola. Por eso es un
// solo botón y la pantalla lo dice, en vez de un "registrarse" aparte que haría lo mismo.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../edicion.dart';
import '../kit/kit_ns.dart';
import 'bienvenida_gastro.dart' show MarcaGastro;
import 'marca_nodo_sur.dart';

/// La pantalla de entrar como la de cualquier app de toda la vida (El dueño, 2026-10-18: "el login lo odio, se ve feo; quiero
/// que se vea como una app de toda la vida, con nuestra chicha"): la marca grande en el medio, y abajo, a mano del pulgar, un
/// solo botón. Lo que antes eran cuatro carteles grises queda en dos renglones chicos al pie.
class VistaEntrarConGoogle extends StatelessWidget {
  const VistaEntrarConGoogle({
    super.key,
    required this.alEntrar,
    this.trabajando = false,
    this.etapa,
    this.error,
    this.alReintentar,
    this.alEntrarConNavegador,
    this.volverACuenta,
  });

  final VoidCallback alEntrar;

  /// Esperando a Google, tomando el perfil o bajando los datos: el botón muestra que está trabajando y no se puede
  /// tocar de nuevo.
  final bool trabajando;

  /// Qué está haciendo mientras trabaja ("Bajando los datos del negocio…"): entrar puede tardar, y sin decir qué pasa parece
  /// que se colgó.
  final String? etapa;

  /// Qué salió mal, dicho para la persona (sin internet, la invitación era para otro mail, etc.).
  final String? error;

  /// Reintentar sin volver a abrir el navegador (cuando la cuenta ya quedó vinculada y falló otra cosa).
  final VoidCallback? alReintentar;

  /// La salida de siempre (abrir el navegador para entrar), cuando entrar con Google desde la app no anduvo: un teléfono sin
  /// servicios de Google, o la app todavía sin registrar en Google Cloud.
  final VoidCallback? alEntrarConNavegador;

  /// Se tocó "Agregar otra cuenta" y hay otra guardada en el celular: la salida para volver a ella sin entrar con ninguna.
  final ({String titulo, VoidCallback alTocar})? volverACuenta;

  String get _bajada => switch (edicionActual) {
        Edicion.gastronomia => 'Pedidos, cocina y caja en un solo lugar.',
        Edicion.servicios => 'Tu agenda y tus cobros en un solo lugar.',
        Edicion.almacen => 'Tu caja, tu stock y tus proveedores en orden.',
      };

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final pie = estiloNs(13, altura: 1.4, color: ns.mute);
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, caja) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: caja.maxHeight - 20),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 3),
                    Center(child: esEdicionGastronomia ? const MarcaGastro(tamanio: 76) : const MarcaNodoSur(tamanio: 76)),
                    const SizedBox(height: 20),
                    Text(nombreDeEdicion, textAlign: TextAlign.center, style: tituloNs(36, track: -0.045, color: ns.ink)),
                    const SizedBox(height: 8),
                    Text(_bajada, textAlign: TextAlign.center, style: estiloNs(17, altura: 1.35, color: ns.mute)),
                    const Spacer(flex: 4),
                    const SizedBox(height: 24),
                    Text('Entrá con tu cuenta', textAlign: TextAlign.center, style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
                    const SizedBox(height: 12),
                    if (error != null) ...[
                      KeyedSubtree(key: const Key('entrar_error'), child: InfoNs(error!, tono: TonoNs.bad)),
                      const SizedBox(height: 10),
                    ],
                    if (error != null && alReintentar != null) ...[
                      KeyedSubtree(
                        key: const Key('entrar_reintentar'),
                        child: BotonNs.secundario(context, 'Reintentar', trabajando ? null : alReintentar),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _BotonGoogle(trabajando: trabajando, etapa: etapa, onTap: trabajando ? null : alEntrar),
                    if (alEntrarConNavegador != null) ...[
                      const SizedBox(height: 10),
                      KeyedSubtree(
                        key: const Key('entrar_con_navegador'),
                        child: BotonNs.secundario(context, 'Entrar con el navegador', trabajando ? null : alEntrarConNavegador),
                      ),
                    ],
                    if (volverACuenta != null) ...[
                      const SizedBox(height: 10),
                      KeyedSubtree(
                        key: const Key('volver_a_cuenta'),
                        child: BotonNs.secundario(context, 'Volver a ${volverACuenta!.titulo}', trabajando ? null : volverACuenta!.alTocar),
                      ),
                    ],
                    const SizedBox(height: 18),
                    // Con Google no hay "registrarse" aparte: la primera vez la cuenta se crea sola.
                    Text('¿Primera vez? Tu cuenta se crea sola. Es la misma de horsepos.com.', textAlign: TextAlign.center, style: pie),
                    const SizedBox(height: 4),
                    Text(
                      kIsWeb
                          ? 'Si te invitaron a un negocio, entrá con el mail de la invitación.'
                          : 'Si te invitaron a un negocio, entrá con el mail de la invitación. Internet hace falta solo para entrar.',
                      textAlign: TextAlign.center,
                      style: pie,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El botón de Google: blanco con borde y la "G" de colores, como lo pide Google para "Continuar con Google".
class _BotonGoogle extends StatelessWidget {
  const _BotonGoogle({required this.trabajando, required this.onTap, this.etapa});

  final bool trabajando;
  final String? etapa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: trabajando ? (etapa ?? 'Entrando') : 'Continuar con Google',
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
                    Flexible(child: Text(etapa ?? 'Entrando…', overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w600, color: ns.mute))),
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
