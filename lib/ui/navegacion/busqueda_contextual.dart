// Buscador contextual de la navbar (El dueño, 2026-09-28: "quiero que el
// buscador sea contextual, que busque según la pantalla que estemos").
// Una pantalla de gestión que pasa una [BusquedaContextual] a
// `PantallaGestion` cambia lo que hace el campo de arriba: deja de buscar
// productos para mandar a Venta y pasa a filtrar en vivo lo que esa pantalla
// muestra (proveedores, ventas, secciones...). Sin [BusquedaContextual],
// sigue el buscador de productos de siempre (`BarraBusquedaGlobal`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/normalizacion_texto.dart';
import '../tema/iconos.dart';
import '../tema/tokens.dart';
import '../venta/tacto_venta.dart';

/// Qué busca el campo de arriba en una pantalla puntual.
class BusquedaContextual {
  const BusquedaContextual({required this.pista, required this.alCambiar});

  /// Texto gris del campo vacío: dice qué se busca acá ("Buscar proveedor o
  /// producto…").
  final String pista;

  /// Cada tecla, con el texto ya recortado (vacío = sin filtro).
  final ValueChanged<String> alCambiar;
}

const double _radioPildora = 999;

/// Mismo aspecto que el buscador de productos (`BarraBusquedaGlobal`): los
/// dos son "el buscador de arriba", solo cambia qué buscan.
InputDecoration decoracionBuscadorNavbar(BuildContext context, {required String pista, Widget? sufijo}) {
  final colores = context.colores;
  final borde = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_radioPildora),
    borderSide: BorderSide(color: colores.borde.withValues(alpha: 0.6)),
  );
  return InputDecoration(
    hintText: pista,
    prefixIcon: Icon(IconosPlazoleta.search, size: TactoVenta.icono, color: colores.textoSecundario),
    suffixIcon: sufijo,
    contentPadding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm),
    filled: true,
    fillColor: colores.fondoBloque,
    border: borde,
    enabledBorder: borde,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_radioPildora),
      borderSide: BorderSide(color: colores.acento, width: Bordes.fino * 1.5),
    ),
  );
}

class CampoBusquedaContextual extends StatefulWidget {
  const CampoBusquedaContextual({super.key, required this.busqueda, this.foco, this.alSalir});

  final BusquedaContextual busqueda;

  /// De quien la abre (la navbar), para darle el foco al abrir la búsqueda.
  final FocusNode? foco;

  /// Esc con el campo vacío: cerrar la búsqueda.
  final VoidCallback? alSalir;

  @override
  State<CampoBusquedaContextual> createState() => _CampoBusquedaContextualState();
}

class _CampoBusquedaContextualState extends State<CampoBusquedaContextual> {
  final _texto = TextEditingController();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _cambio(String valor) {
    setState(() {});
    widget.busqueda.alCambiar(valor.trim());
  }

  void _limpiar() {
    _texto.clear();
    _cambio('');
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      // Esc borra el filtro, como en cualquier buscador.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _texto.text.isEmpty && widget.alSalir != null ? widget.alSalir!() : _limpiar(),
      },
      child: TextField(
        key: const Key('busqueda_contextual'),
        controller: _texto,
        focusNode: widget.foco,
        onChanged: _cambio,
        decoration: decoracionBuscadorNavbar(
          context,
          pista: widget.busqueda.pista,
          sufijo: _texto.text.isEmpty
              ? null
              : IconButton(tooltip: 'Borrar', icon: const Icon(IconosPlazoleta.close), onPressed: _limpiar),
        ),
      ),
    );
  }
}

/// ¿[texto] contiene [busqueda]? Sin importar mayúsculas ni acentos, como el
/// buscador de Venta (`normalizarTexto`).
bool coincideBusqueda(String texto, String busqueda) {
  if (busqueda.isEmpty) return true;
  return normalizarTexto(texto).contains(normalizarTexto(busqueda));
}
