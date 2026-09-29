// Hoja modal de vidrio — reemplazo de `AlertDialog` para lo que necesita más
// que un par de líneas de confirmación (Bruno, 2026-09-18: "los modales no
// me gustan, hay que desplazarse demasiado"). Una hoja que sube desde abajo
// da más aire real sin depender de scroll interno, y es el mismo lugar
// donde Apple aplica vidrio esmerilado en sus propias hojas — coherente con
// la navbar (`navbar_companion.dart`), no un tercer lenguaje visual más.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'tema_companion.dart';

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
    builder: (context) {
      final colores = context.colores;
      return Padding(
        // Sube la hoja por encima del teclado cuando hay un campo de texto
        // adentro (Bruno, 2026-09-07, mismo criterio ya usado en otros
        // formularios de la companion).
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(radioSuperficieCompanion),
            ),
            child: BackdropFilter(
              // Sigma 24 → 16 (Bruno, 2026-09-19: "revisa bien el tema
              // rendimiento") — mismo ajuste que la navbar: menos trabajo por
              // frame para `BackdropFilter`, vidrio esmerilado igual de
              // creíble. Acá el costo por sí solo es menor (lo de atrás queda
              // fijo mientras la hoja está abierta, no scrollea detrás), pero
              // mismo criterio para toda la app.
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colores.fondoBloque.withValues(alpha: 0.88),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  EspacioCompanion.lg,
                  EspacioCompanion.sm,
                  EspacioCompanion.lg,
                  EspacioCompanion.lg + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (esDescartable)
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(
                            bottom: EspacioCompanion.md,
                          ),
                          decoration: BoxDecoration(
                            color: colores.borde,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    Builder(builder: builder),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
