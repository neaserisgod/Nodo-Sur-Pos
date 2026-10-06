// El cuerpo de Venta, armado como el mock v4 (1920×1080): a la izquierda el buscador grande con "Pagar proveedor", las categorías y
// la grilla de productos; a la derecha UN solo panel gris (radio 52) con las pestañas de ventas, el carrito, el total, los medios de pago
// y "Cobrar". Las medidas son las del mock a 1920 px de ancho; en ventanas más chicas (piso 1366×768) se reducen sin cambiar la
// composición: el panel pasa de 620 a ~440 px, los márgenes de 56 a 24, y con poca altura el total y los botones se compactan.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';
import 'columna_busqueda.dart';
import 'columna_carrito.dart';
import 'columna_cobro.dart';

/// Medidas de Venta que dependen del tamaño de la ventana. Una sola cuenta para todas las piezas.
class MedidasVenta {
  const MedidasVenta._(this.ancho, this.alto);

  factory MedidasVenta.de(BoxConstraints c) => MedidasVenta._(c.maxWidth, c.maxHeight);

  final double ancho;
  final double alto;

  /// Poca altura (1366×768 y parecidas): total, medios y "Cobrar" se compactan para que todo entre sin scroll.
  bool get compacto => alto < 840;

  double get margenLateral => ancho >= 1700 ? 56 : (ancho >= 1366 ? 32 : 24);
  double get anchoPanel => (ancho * 0.3229).clamp(440.0, 620.0);
  double get altoBuscador => compacto ? 60 : 72;
  double get altoTarjeta => compacto ? 128 : 150;
}

class CuerpoVenta extends StatelessWidget {
  const CuerpoVenta({
    super.key,
    required this.onPagarProveedor,
    required this.onImprimir,
    required this.ventaConfirmada,
    required this.totalConfirmadoCentavos,
    required this.usuarioId,
  });

  final VoidCallback onPagarProveedor;
  final VoidCallback onImprimir;
  final int? ventaConfirmada;
  final int? totalConfirmadoCentavos;
  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final m = MedidasVenta.de(restricciones);
        return Padding(
          padding: EdgeInsets.fromLTRB(m.margenLateral, Espaciado.md, m.margenLateral, compactoMargenInferior(m)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // El desplegable de resultados cuelga del campo pero mide todo el ancho de la columna (no solo el del
                    // campo, que se achica por el botón): si no, las filas pierden el stock.
                    LayoutBuilder(
                      builder: (context, r) => Row(
                        children: [
                          Expanded(
                            child: SizedBox(height: m.altoBuscador, child: BarraBusquedaVenta(anchoDropdown: r.maxWidth)),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(height: m.altoBuscador, child: BotonPagarProveedor(onTap: onPagarProveedor)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(child: RejillaProductos(altoTarjeta: m.altoTarjeta)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: m.anchoPanel,
                child: _PanelDerecho(
                  compacto: m.compacto,
                  ventaConfirmada: ventaConfirmada,
                  totalConfirmadoCentavos: totalConfirmadoCentavos,
                  onImprimir: onImprimir,
                  usuarioId: usuarioId,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double compactoMargenInferior(MedidasVenta m) => m.compacto ? 16 : 26;
}

/// El panel gris de la derecha: pestañas + carrito arriba (con scroll propio) y el cobro siempre visible abajo.
class _PanelDerecho extends StatelessWidget {
  const _PanelDerecho({
    required this.compacto,
    required this.ventaConfirmada,
    required this.totalConfirmadoCentavos,
    required this.onImprimir,
    required this.usuarioId,
  });

  final bool compacto;
  final int? ventaConfirmada;
  final int? totalConfirmadoCentavos;
  final VoidCallback onImprimir;
  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      key: const Key('panel_venta'),
      padding: EdgeInsets.all(compacto ? 16 : 22),
      decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(compacto ? 40 : 52)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColumnaCarrito(
              ventaConfirmada: ventaConfirmada,
              totalConfirmadoCentavos: totalConfirmadoCentavos,
              onImprimir: onImprimir,
            ),
          ),
          SizedBox(height: compacto ? 10 : 14),
          PanelCobro(usuarioId: usuarioId, compacto: compacto),
        ],
      ),
    );
  }
}
