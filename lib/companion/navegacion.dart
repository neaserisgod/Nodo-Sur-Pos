// Bug real (El dueño, 2026-09-10): "si en un apartado ingreso al teclado, al
// volver al menú principal con el botón de atrás vuelve a salir el
// teclado". Flutter guarda qué widget tenía el foco en una pantalla justo
// antes de pushear otra encima (cada ruta tiene su propio FocusScopeNode);
// al hacer `pop`, el Navigator le devuelve el foco solo a ese mismo
// widget — si era un `TextField`, el teclado se abre de nuevo sin que el
// usuario haya tocado nada. Pasa en cualquier pantalla de la companion que
// tenga un buscador Y además navegue a otra pantalla, no solo en el menú
// principal — de ahí este helper único (Regla 3) en vez de desenfocar a
// mano después de cada `Navigator.push`.
import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'tema/hoja_vidrio.dart';

/// Empuja [builder] como ruta nueva, desenfocando antes y después. Usar en
/// vez de `Navigator.of(context).push(MaterialPageRoute(builder: builder))`
/// en cualquier pantalla que tenga un campo de texto.
Future<T?> pushSinTeclado<T>(
  BuildContext context,
  WidgetBuilder builder,
) async {
  // El desenfoque DESPUÉS de volver (lo único que hacía esto antes) no
  // alcanza — el bug reaparecía igual (El dueño, 2026-09-10: "sigue pasando").
  // El `FocusScopeNode` de esta ruta recuerda cuál era su "focusedChild" en
  // el momento en que la ruta nueva le sacó el foco ENCIMA — esa memoria
  // queda grabada ANTES de pushear, no después de volver. Si no se limpia
  // antes, el Navigator se la devuelve solo al volver sin importar qué se
  // haga después. El desenfoque real va ACÁ, antes del push, para que no
  // quede nada que restaurar.
  FocusScope.of(context).unfocus();
  final resultado = await Navigator.of(
    context,
  ).push<T>(MaterialPageRoute(builder: builder));
  // Por si algo dentro de la ruta pusheada le devolvió el foco a este
  // mismo árbol (poco probable, pero barato de cubrir igual).
  if (context.mounted) FocusScope.of(context).unfocus();
  return resultado;
}

/// Confirma antes de perder datos sin guardar — Precios (formulario) y
/// Conteo de stock (hasta 30-80 campos tipeados recorriendo la góndola)
/// dejaban salir con el botón atrás sin avisar nada. Un solo diálogo
/// (Regla 3) en vez de que cada pantalla arme el suyo.
Future<bool> confirmarSalirSinGuardar(BuildContext context) async {
  final confirmar = await mostrarHojaVidrio<bool>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Salir sin guardar?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.sm),
        Text(
          'Lo que cargaste todavía no se guardó — se pierde si salís ahora.',
          style: TextStyle(color: context.colores.textoSecundario),
        ),
        const SizedBox(height: Espaciado.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Seguir acá'),
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: context.colores.error),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Salir sin guardar'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmar ?? false;
}
