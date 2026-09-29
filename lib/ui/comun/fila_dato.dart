// Etiqueta a la izquierda, valor tabular a la derecha con ancho fijo — no es
// una fila de lista tocable (`FilaLista`) ni una celda apilada (`Metrica`):
// es una línea de dato suelta dentro de un `Bloque`, la unidad que ya
// repetían a mano Proveedores (nivel 2, antes del kit) y Cierre
// (`_FilaDato`) para lo mismo. Pieza agregada al kit en el paso 2 (fase 13,
// Bruno: "si algo no se puede armar con el kit, se agrega una pieza al
// kit").

import 'package:flutter/material.dart';

import '../tema/tokens.dart';

class FilaDato extends StatelessWidget {
  const FilaDato({super.key, required this.etiqueta, required this.valor, this.enfasis = false, this.color});

  final String etiqueta;
  final String valor;

  /// Resalta el valor (`titleMedium` en vez de `bodyMedium`, medio en vez de
  /// regular) — para la cifra que más importa de un bloque (ej. "Diferencia"
  /// contra "Caja esperada").
  final bool enfasis;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final estiloValor = enfasis
        ? textTheme.titleMedium!.copyWith(color: color, fontWeight: Pesos.medium)
        : textTheme.bodyMedium!.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(etiqueta, style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario)),
          ),
          const SizedBox(width: Espaciado.md),
          // Sin ancho fijo (a diferencia de una columna de varias filas
          // — `FilaLista`/`anchoValorLista`, donde varios valores DE LA
          // MISMA fila necesitan alinearse entre sí): acá cada fila es su
          // propia `Row` de ancho completo, así que el valor ya termina en
          // el borde derecho del bloque sin importar su ancho — fijarlo
          // solo arriesgaba partir en dos líneas una cifra grande
          // (`enfasis`, `titleMedium`) que no entraba en 110px.
          Text(valor, textAlign: TextAlign.right, style: estiloValor.tabular),
        ],
      ),
    );
  }
}
