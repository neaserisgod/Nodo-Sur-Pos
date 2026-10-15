// Hoja inferior del mock (docs/01 §6.13): velo al 50 %, hoja de radio 40 arriba,
// asa de 44×5, título 28/450, texto 15 `mute`, bloques que scrollean (gap 10) y
// botones apilados abajo (gap 8). Alto máximo 92 %. El velo cierra la hoja al
// tocarlo (decisión del doc 07 §4) salvo cuando [descartable] es false
// ("Cobrando en la terminal", "¿Salir sin guardar?").

import 'package:flutter/material.dart';

import 'escritorio_ns.dart' show anchoLibreNs;
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

/// Contenido de una hoja. Es solo la parte visual: quien la usa arma los
/// bloques y los botones.
class HojaNs extends StatelessWidget {
  const HojaNs({super.key, required this.titulo, this.texto, this.bloques = const [], this.botones = const []});

  final String titulo;
  final String? texto;
  final List<Widget> bloques;
  final List<Widget> botones;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final alto = MediaQuery.sizeOf(context).height;
    final ventana = HojaComoVentanaNs.de(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: titulo,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: alto * 0.92),
        padding: EdgeInsets.fromLTRB(ventana ? 28 : 20, ventana ? 26 : 12, ventana ? 28 : 20, ventana ? 24 : 24 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: ns.paper, borderRadius: ventana ? BorderRadius.circular(28) : const BorderRadius.vertical(top: Radius.circular(40))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // El asa es para arrastrar la hoja con el dedo: en una ventana de la compu no va.
            if (!ventana) ...[
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: TokensNs.asa, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 12),
            ],
            Text(titulo, style: tituloNs(28, track: -0.045, altura: 1.08, color: ns.ink)),
            if (texto != null) ...[
              const SizedBox(height: 12),
              Text(texto!, style: estiloNs(15, altura: 1.45, color: ns.mute)),
            ],
            if (bloques.isNotEmpty) ...[
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < bloques.length; i++) ...[if (i > 0) const SizedBox(height: 10), bloques[i]],
                    ],
                  ),
                ),
              ),
            ],
            if (botones.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (var i = 0; i < botones.length; i++) ...[if (i > 0) const SizedBox(height: 8), botones[i]],
            ],
          ],
        ),
      ),
    );
  }
}

/// Muestra [contenido] como hoja inferior con el velo y la animación del mock.
Future<T?> mostrarHojaNs<T>(BuildContext context, {required WidgetBuilder builder, bool descartable = true}) {
  FocusScope.of(context).unfocus();
  // En la compu, con el menú lateral (`escritorio_ns.dart`), una hoja que sube desde abajo es cosa de celular: se abre como una
  // ventana al centro, del ancho de una hoja, con el mismo contenido (El dueño, 2026-10-15).
  if (anchoLibreNs.value) {
    return showDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: descartable,
      barrierColor: TokensNs.velo,
      builder: (ctx) => PopScope(
        canPop: descartable,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                type: MaterialType.transparency,
                // Las hojas propias (dar turno, cobrar) dibujan su fondo con las esquinas de abajo rectas: se redondean todas.
                child: ClipRRect(borderRadius: BorderRadius.circular(28), child: HojaComoVentanaNs(child: Builder(builder: builder))),
              ),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: descartable,
    enableDrag: descartable,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: TokensNs.velo,
    sheetAnimationStyle: sinMovimiento(context)
        ? const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero)
        : const AnimationStyle(duration: Duration(milliseconds: 500), reverseDuration: Duration(milliseconds: 300), curve: curvaNs),
    builder: (ctx) => PopScope(
      canPop: descartable,
      child: Padding(
        // Sube por encima del teclado cuando hay un campo adentro.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// Marca una hoja que se muestra como ventana al centro (la compu): sin asa y con las cuatro esquinas redondeadas.
class HojaComoVentanaNs extends InheritedWidget {
  const HojaComoVentanaNs({super.key, required super.child});

  static bool de(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HojaComoVentanaNs>() != null;

  @override
  bool updateShouldNotify(HojaComoVentanaNs oldWidget) => false;
}
