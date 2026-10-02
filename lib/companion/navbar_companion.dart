// Navbar inferior del mock completo del celular: una píldora flotante de
// tinta con cuatro pestañas de solo texto; la activa se marca con una píldora
// clara. Ya no lleva botón central de escáner: escanear vive dentro de los
// buscadores (Productos, Consultar precio, Carrito), donde se necesita.

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';

class NavbarCompanion extends StatelessWidget {
  const NavbarCompanion({
    super.key,
    required this.indice,
    required this.onSeleccionar,
  });

  /// 0 Inicio, 1 Productos, 2 Historial, 3 Gestión.
  final int indice;
  final ValueChanged<int> onSeleccionar;

  static const double _altura = 64;
  static const double _margenLateral = 16;
  static const double _margenInferior = 16;
  static const _etiquetas = ['Inicio', 'Productos', 'Historial', 'Gestión'];

  /// Cuánto padding inferior necesita el contenido de cada pestaña para no
  /// quedar tapado por la barra: `PantallaMenuCompanion` usa `extendBody`
  /// (el contenido pasa POR DEBAJO de la barra flotante) y cada pestaña suma
  /// esto a su lista o scroll para que el último elemento siga alcanzable.
  static const double espacioReservado = _altura + _margenInferior + Espaciado.lg;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final inferior = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(_margenLateral, 0, _margenLateral, _margenInferior + inferior),
      child: RepaintBoundary(
        child: Container(
          height: _altura,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colores.acento,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              for (var i = 0; i < _etiquetas.length; i++)
                Expanded(child: _Pestania(etiqueta: _etiquetas[i], activa: indice == i, onTap: () => onSeleccionar(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pestania extends StatelessWidget {
  const _Pestania({required this.etiqueta, required this.activa, required this.onTap});

  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Semantics(
      button: true,
      selected: activa,
      label: etiqueta,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: activa ? colores.acentoTexto : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              etiqueta,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: Pesos.fuerte,
                // Sobre la píldora de tinta el texto inactivo va apagado; el activo, en tinta sobre el claro.
                color: activa ? colores.acento : colores.acentoTexto.withValues(alpha: 0.82),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
