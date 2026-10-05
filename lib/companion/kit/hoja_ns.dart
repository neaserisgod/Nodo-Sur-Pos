// Hoja inferior del mock (docs/01 §6.13): velo al 50 %, hoja de radio 40 arriba,
// asa de 44×5, título 28/450, texto 15 `mute`, bloques que scrollean (gap 10) y
// botones apilados abajo (gap 8). Alto máximo 92 %. El velo cierra la hoja al
// tocarlo (decisión del doc 07 §4) salvo cuando [descartable] es false
// ("Cobrando en la terminal", "¿Salir sin guardar?").

import 'package:flutter/material.dart';

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
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: titulo,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: alto * 0.92),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: ns.paper, borderRadius: const BorderRadius.vertical(top: Radius.circular(40))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: TokensNs.asa, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 12),
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
