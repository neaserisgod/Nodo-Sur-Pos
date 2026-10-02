// Nombre a la izquierda, hasta cuatro valores tabulares a la derecha.
// Reemplaza las filas armadas a mano en Proveedores y Productos (`_FilaProveedor`,
// `_FilaProducto`): mismo Material+InkWell, mismo criterio de resaltado
// (`colores.destacado`, nunca un color propio) y el mismo ancho de valor
// compacto para que varias cifras entren una al lado de la otra.
//
// Los valores necesitan una fila ANCHA para entrar sin comerse el nombre (una
// tabla de productos en el panel de detalle, no `Medidas.anchoListaMaestra`,
// que son apenas 360px). En una `ListaMaestra` angosta el uso correcto es
// CERO valores — las cifras del elegido van al panel de detalle
// (`FilaMetricas`), no a cada fila de la lista (corrección post-aprobación
// del kit, el dueño, dibujo de Proveedores: "Distribuidora Distribui..." truncado con
// dos cifras al lado no entraba en 360px).

import 'package:flutter/material.dart';

import '../tema/presionable.dart';
import '../tema/tema_inverso.dart';
import '../tema/tokens.dart';

class FilaLista extends StatelessWidget {
  const FilaLista({
    super.key,
    required this.nombre,
    this.valores = const [],
    this.seleccionada = false,
    this.apagada = false,
    this.tienePendiente = false,
    this.leading,
    this.onTap,
  }) : assert(valores.length <= 4, 'FilaLista admite hasta cuatro valores');

  final String nombre;

  /// Slot genérico antes del nombre — hoy solo lo usa el casillero de
  /// edición masiva de Proveedores (`Checkbox`, ver `detalle_proveedor.dart`),
  /// pero no le pertenece a ese caso: cualquier lista futura que necesite
  /// algo antes del nombre (un ícono, un avatar) lo agrega sin tocar este
  /// widget de nuevo.
  final Widget? leading;

  /// Hasta cuatro cifras ya formateadas, de izquierda a derecha. En
  /// `ListaMaestra` (ancho angosto) dejar esto vacío — ver comentario de
  /// archivo.
  final List<String> valores;

  final bool seleccionada;

  /// Fila sin movimiento / inactiva: mismo criterio que las listas actuales
  /// (`textoTenue`), para que no compita por atención con las que sí importan.
  final bool apagada;

  /// Punto de acento antes del nombre (2026-09-12, el dueño: "el gris sin
  /// explicar es confuso") — señal explícita de "esto tiene algo que
  /// requiere tocarlo" (ej. Reportes: reposición o ganancia sin revisar),
  /// en vez de que la única pista sea que el resto de la lista está
  /// apagada. Cuarto uso del acento (`tokens.dart` documentaba tres) — se
  /// pensó dos veces a propósito: es la misma idea de fondo ("esto importa
  /// ahora"), no un adorno.
  final bool tienePendiente;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inv = coloresDeFila(context, seleccionada);
    final colores = inv.colores;
    final textTheme = inv.textTheme;
    final colorTexto = apagada && !seleccionada ? colores.textoTenue : null;

    return Presionable(
      radio: 22,
      color: seleccionada ? colores.acento : null,
      onTap: onTap,
      child: TemaInverso(
        activo: seleccionada,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Espaciado.sm,
            vertical: Espaciado.sm,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: Espaciado.sm),
              ],
              if (tienePendiente) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colores.acento,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Espaciado.sm),
              ],
              Expanded(
                child: Text(
                  nombre,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorTexto,
                    fontWeight: seleccionada ? Pesos.medium : Pesos.regular,
                  ),
                ),
              ),
              for (final valor in valores) ...[
                const SizedBox(width: Espaciado.sm),
                SizedBox(
                  width: Medidas.anchoValorListaCompacto,
                  child: Text(
                    valor,
                    textAlign: TextAlign.right,
                    style: textTheme.bodyMedium!
                        .copyWith(color: colorTexto)
                        .tabular,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
