// Campo de búsqueda de productos, disponible en TODAS las pantallas de
// gestión (Bruno, tercera pasada de venta: "quiero que la barra de busqueda
// este en todos lados" — confirmado: en toda la app, no solo en Venta).
//
// Liviano y separado de `BarraBusquedaVenta` (venta/columna_busqueda.dart):
// esa versión agrega directo al carrito y está atada a `VentaControlador`,
// que solo existe dentro de la pantalla de venta — acá no hay carrito al
// que agregarle nada. Elegir un resultado (tap) o Enter NAVEGA a Venta con
// el texto ya escrito, dejando que termine ahí el mismo camino de siempre
// (incluidos los avisos, como un pesable sin gramos) — nunca agrega el
// producto por su cuenta. Mismo mecanismo de dropdown anclado
// (`CompositedTransformTarget`/`OverlayPortal`/`CompositedTransformFollower`,
// con el `UnconstrainedBox` que evita el scrim gris — ver
// `BarraBusquedaVenta` para el bug original) y mismo lenguaje visual, sin
// compartir el widget en sí porque resuelven cosas distintas.

import 'package:flutter/material.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../venta/tacto_venta.dart';
import 'busqueda_contextual.dart';

class BarraBusquedaGlobal extends StatefulWidget {
  const BarraBusquedaGlobal({
    super.key,
    required this.db,
    required this.anchoDropdown,
    required this.onElegir,
  });

  final AppDatabase db;
  final double anchoDropdown;

  /// Se llama con el texto elegido: el nombre exacto si se tocó un
  /// resultado, o el texto tal cual se escribió si fue Enter — quien use
  /// este widget decide a dónde ir con eso (en la práctica, siempre Venta).
  final ValueChanged<String> onElegir;

  @override
  State<BarraBusquedaGlobal> createState() => _BarraBusquedaGlobalState();
}

class _BarraBusquedaGlobalState extends State<BarraBusquedaGlobal> {
  final _controladorTexto = TextEditingController();
  final _foco = FocusNode();
  final _link = LayerLink();
  final _overlayController = OverlayPortalController();
  List<Producto> _catalogo = [];

  @override
  void initState() {
    super.initState();
    _overlayController.show();
    _controladorTexto.addListener(() => setState(() {}));
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    final catalogo = await widget.db.select(widget.db.productos).get();
    if (mounted) setState(() => _catalogo = catalogo);
  }

  void _elegir(String texto) {
    widget.onElegir(texto);
    _controladorTexto.clear();
    _foco.unfocus();
  }

  @override
  void dispose() {
    _controladorTexto.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final hayTexto = _controladorTexto.text.trim().isNotEmpty;
    final coincidencias = hayTexto
        ? buscarProductos(catalogo: _catalogo, textoBuscado: _controladorTexto.text)
        : const <Producto>[];

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        if (!hayTexto) return const SizedBox.shrink();
        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, Espaciado.sm),
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: widget.anchoDropdown,
              child: Superficie(
                relleno: colores.fondoBloque,
                child: coincidencias.isEmpty
                    ? Text(
                        'Sin coincidencias',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final producto in coincidencias) ...[
                            if (producto != coincidencias.first)
                              const SizedBox(height: Espaciado.md),
                            _FilaResultadoGlobal(
                              producto: producto,
                              onTap: () => _elegir(producto.nombre),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: TextField(
          controller: _controladorTexto,
          focusNode: _foco,
          // Mismo aspecto que el buscador contextual (`busqueda_contextual.dart`).
          decoration: decoracionBuscadorNavbar(context, pista: 'Buscar un producto…'),
          onSubmitted: (texto) {
            if (texto.trim().isEmpty) return;
            _elegir(texto.trim());
          },
        ),
      ),
    );
  }
}

/// Fila de resultado — más simple que `_FilaResultado` de Venta (sin stock
/// ni precio: acá no se está por agregar nada, solo eligiendo a dónde
/// saltar), pero mismo tacto (`SuperficieTactil`, mismo radio).
class _FilaResultadoGlobal extends StatelessWidget {
  const _FilaResultadoGlobal({required this.producto, required this.onTap});

  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SuperficieTactil(
      borderRadius: BorderRadius.circular(TactoVenta.radio),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espaciado.md,
          vertical: Espaciado.md,
        ),
        child: Text(producto.nombre, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
