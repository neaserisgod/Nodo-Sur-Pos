// Navbar superior — rediseño "antigravity": la marca a la izquierda y las
// secciones como una fila de pastillas (la activa con fondo gris), igual que
// la barra de la web de Nodo Sur. Reemplaza al menú desplegable de un solo
// botón (2026-09-25/26): ahora se ve de un vistazo dónde se puede ir.
//
// Reutilizable a propósito: cada pantalla que la use arma su propia lista de
// `ItemNavbarSuperior` y su propia clave activa (`navegacion_gestion.dart`).
// Ocupa todo el ancho que le den (la fila de pastillas se desplaza si no
// entra), así que quien la use tiene que darle un ancho acotado (`Expanded`).

import 'package:flutter/material.dart';

import '../../domain/marca.dart';
import '../../servicios/marca_actual.dart';
import '../tema/presionable.dart';
import '../tema/tokens.dart';

class ItemNavbarSuperior {
  const ItemNavbarSuperior({required this.clave, required this.etiqueta});

  /// Clave estable de la sección (`secciones_menu.clave`, o `'venta'` /
  /// `'configuracion'` para las dos entradas fijas que no pasan por esa
  /// tabla).
  final String clave;
  final String etiqueta;
}

/// Alto de la barra: la búsqueda que la acompaña usa el mismo.
const double altoNavbarSuperior = 52;

class NavbarSuperior extends StatelessWidget {
  const NavbarSuperior({
    super.key,
    required this.claveActiva,
    required this.items,
    required this.onSeleccionar,
  });

  final String claveActiva;
  final List<ItemNavbarSuperior> items;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: SizedBox(
        height: altoNavbarSuperior,
        child: Row(
          children: [
            const _Marca(),
            const SizedBox(width: Espaciado.xl),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in items)
                      _Pastilla(
                        etiqueta: item.etiqueta,
                        activa: item.clave == claveActiva,
                        onTap: () => onSeleccionar(item.clave),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La insignia con las iniciales y el nombre del comercio.
class _Marca extends StatelessWidget {
  const _Marca();

  static String _iniciales(String nombre) {
    final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return 'NS';
    if (palabras.length == 1) return palabras.first.substring(0, palabras.first.length >= 2 ? 2 : 1).toUpperCase();
    return (palabras[0][0] + palabras[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<MarcaNegocio>(
      valueListenable: marcaActual,
      builder: (context, marca, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colores.acento, borderRadius: BorderRadius.circular(12)),
            child: Text(
              _iniciales(marca.nombre),
              style: textTheme.titleSmall?.copyWith(color: colores.acentoTexto, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: Espaciado.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              marca.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.etiqueta, required this.activa, required this.onTap});

  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Presionable(
        radio: 999,
        onTap: onTap,
        color: activa ? colores.fondoBloque : null,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
          alignment: Alignment.center,
          child: Text(
            etiqueta,
            maxLines: 1,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: activa ? Pesos.medium : FontWeight.w500,
              color: activa ? colores.textoPrimario : colores.textoSecundario,
            ),
          ),
        ),
      ),
    );
  }
}
