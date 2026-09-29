// Un solo botón primario y uno secundario, altura `Medidas.alturaControl`
// siempre. `ElevatedButton`/`OutlinedButton` ya toman color y forma del tema
// (`TemaPlazoleta`) — lo único que agregan estos widgets es la altura fija y,
// en el primario, el color de texto explícito sobre el acento.
//
// Ese color explícito no es capricho: es el mismo bug ya encontrado en el
// botón "Cobrar" (`columna_cobro.dart`) — `textTheme.labelLarge` trae
// `textoPrimario` horneado adentro del `TextStyle`, y ese color puede
// ganarle al `foregroundColor` del botón en la resolución de Flutter. Se
// fuerza acá una sola vez para que ningún botón primario nuevo repita ese
// mismo bug.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';

class BotonPrimario extends StatelessWidget {
  const BotonPrimario({super.key, required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Medidas.alturaControl,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(texto, style: TextStyle(color: context.colores.acentoTexto)),
      ),
    );
  }
}

class BotonSecundario extends StatelessWidget {
  const BotonSecundario({super.key, required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Medidas.alturaControl,
      child: OutlinedButton(
        onPressed: onPressed,
        // `colores.borde` (el borde global de `OutlinedButton`) casi no
        // contrasta contra `colores.fondo` en tema claro — ahí es donde vive
        // este botón la mayoría de las veces (ej. la acción de un
        // `EncabezadoPantalla`), no dentro de un `Bloque` — así que
        // "Cancelar"/"Abrir modal" desaparecían en claro y solo se veían en
        // oscuro. `textoSecundario` contrasta en los dos temas por diseño
        // (es un color de texto de lectura, no decorativo).
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: context.colores.textoSecundario, width: Bordes.fino),
        ),
        child: Text(texto),
      ),
    );
  }
}
