// Hoja modal — reemplazo de `AlertDialog` para lo que necesita más que un par
// de líneas de confirmación (El dueño, 2026-09-18: "los modales no me gustan,
// hay que desplazarse demasiado"). Sube desde abajo, con fondo plano del
// color de la pantalla, esquinas muy redondeadas y una sombra suave arriba
// (rediseño "antigravity"; el nombre del archivo viene de la versión de vidrio).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import '../kit/movimiento_ns.dart';
import '../kit/tokens_ns.dart';

/// Confirmación corta antes de una acción que no se puede deshacer — mismo
/// par título/contenido/Cancelar-Borrar que se repetía armado a mano en
/// varias pantallas (Regla 3, aplicada acá a un patrón de UI en vez de a
/// una fórmula de dominio: cuatro líneas idénticas en tres archivos
/// distintos ya cuentan como el mismo caso).
Future<bool> confirmarAccionDestructiva(
  BuildContext context, {
  required String titulo,
  required String contenido,
  String textoConfirmar = 'Borrar',
}) async {
  final confirmado = await mostrarHojaVidrio<bool>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.sm),
        Text(
          contenido,
          style: TextStyle(color: context.colores.textoSecundario),
        ),
        const SizedBox(height: Espaciado.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.colores.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(textoConfirmar),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmado ?? false;
}

/// Hoja inferior del mock (docs/01 §6.13): velo al 50 %, radio 40 arriba, asa de
/// 44×5, padding 12/20/24. Todas las hojas viejas de la companion pasan por
/// acá, así que adoptan el aspecto del mock sin tocarlas una por una.
Future<T?> mostrarHojaVidrio<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool esDescartable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: esDescartable,
    enableDrag: esDescartable,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: TokensNs.velo,
    sheetAnimationStyle: sinMovimiento(context)
        ? const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero)
        : const AnimationStyle(duration: Duration(milliseconds: 500), reverseDuration: Duration(milliseconds: 300), curve: curvaNs),
    builder: (context) {
      final colores = context.colores;
      return Padding(
        // Sube la hoja por encima del teclado cuando hay un campo de texto adentro.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: RepaintBoundary(
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
            decoration: BoxDecoration(
              color: colores.fondo,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            ),
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: TokensNs.asa, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  Builder(builder: builder),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
