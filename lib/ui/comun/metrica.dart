// Etiqueta chica arriba, cifra tabular abajo. La unidad de "$Stock $Costo
// $Venta" (hoy, Proveedores). `valor` ya viene formateado por quien llama
// (`formatearARS` sigue siendo el único punto de conversión centavos →
// texto, Regla 1).
//
// Pasada de vida (2026-09-12, Bruno: "dale más vida a los layouts, cambialos
// al 100% si es necesario"): un ícono chico por métrica ayuda a reconocer
// cada número de un vistazo en vez de leer la etiqueta entera cada vez —
// mismo criterio que ya usan los medios de pago de la pantalla de venta.
// `FilaMetricas` ganó un `accion` opcional: antes "Avanzado"
// (`detalle_proveedor.dart`) flotaba solo entre este bloque y la tabla, dos
// elementos que hablan de lo mismo (el proveedor elegido) sin verse
// conectados — ahora vive adentro, a la derecha de las cifras, un solo
// panel en vez de dos.

import 'package:flutter/material.dart';

import '../tema/superficie.dart';
import '../tema/tokens.dart';

class Metrica extends StatelessWidget {
  const Metrica({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.icono,
  });

  final String etiqueta;
  final String valor;

  /// Null en cualquier pantalla que no necesite el repaso de reconocimiento
  /// rápido (ninguna hoy — todos los llamadores de `FilaMetricas` lo pasan).
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // FittedBox acá también, mismo motivo que el de `valor` abajo: en
        // "mitad de pantalla" cinco métricas más el botón "Avanzado" dejan
        // poco ancho por columna, y truncar la etiqueta con "..." ("Sto...",
        // "Ga...") es tan confuso como truncar una cifra — se pierde la
        // razón de ser del ícono (reconocer de un vistazo) para reemplazarla
        // por texto ilegible. Achicar la letra entera es la misma solución
        // aplicada dos veces.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[
                Icon(icono, size: 15, color: colores.textoSecundario),
                const SizedBox(width: Espaciado.xs),
              ],
              Text(
                etiqueta,
                maxLines: 1,
                style: TextStyle(color: colores.textoSecundario),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.xs),
        // FittedBox, no `overflow: ellipsis` (fase 13, "mitad de pantalla",
        // 2026-09-07): con la columna angosta, una cifra de plata partida
        // en dos líneas se sigue leyendo entera — truncarla con "..."
        // podría leerse como un monto distinto. Achicar la letra hasta que
        // entre en una sola línea es la opción seria para las dos cosas a
        // la vez (una sola línea, la cifra completa).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleLarge!.tabular,
          ),
        ),
      ],
    );
  }
}

/// Varias `Metrica` repartidas en partes iguales dentro de un solo `Bloque`,
/// con una acción propia del panel opcional a la derecha (ver comentario de
/// archivo).
class FilaMetricas extends StatelessWidget {
  const FilaMetricas({super.key, required this.metricas, this.accion});

  final List<Metrica> metricas;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < metricas.length; i++) ...[
            if (i != 0) const SizedBox(width: Espaciado.lg),
            Expanded(child: metricas[i]),
          ],
          if (accion != null) ...[const SizedBox(width: Espaciado.lg), accion!],
        ],
      ),
    );
  }
}
