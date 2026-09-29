// Proveedores (fase 13) — reemplaza a Reposición, y absorbe Productos y
// Stock por proveedor (corrección post-aprobación del kit: esas dos
// pantallas salieron del menú). Tres niveles de información (Bruno,
// principio de fatiga visual, `DISENO.md`): la lista muestra solo el nombre
// (nivel 1), entrar a un proveedor (o "Todos"/"Sin proveedor") trae el
// detalle (nivel 2), y "Avanzado" (nivel 3) queda detrás de un botón.
//
// "Lenguaje de diseño" (Bruno, 2026-09-26, mock `Proveedores.dc.html`,
// "la distribución es la idea"): vuelve la lista + detalle — proveedores
// siempre a la izquierda (`ListaProveedores`), el elegido a la derecha
// (`DetalleProveedor`). Reemplaza al dropdown de proveedor (cuarta pasada
// del 2026-09-25) y al picker de tarjetas grandes (séptima pasada), que
// obligaban a abrir un menú o entrar y salir para cambiar de proveedor.
// Editar cualquier producto sigue siendo un `Modal`.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navegacion/refresco_por_celular.dart';
import '../comparar_precios/pantalla_comparar_precios.dart';
import '../../data/database.dart';
import '../comun/armazon_gestion.dart';
import '../navegacion/busqueda_contextual.dart';
import '../comun/botones.dart';
import '../comun/tarjetas.dart';
import '../../domain/periodo.dart';
import '../stock_proveedor/pantalla_stock_proveedor.dart';
import '../tema/tokens.dart';
import 'detalle_proveedor.dart';
import 'dialogo_importar_csv.dart';
import 'dialogo_promos.dart';
import 'dialogo_nuevo_proveedor.dart';
import 'lista_proveedores.dart';
import 'proveedores_controlador.dart';

class PantallaProveedores extends StatefulWidget {
  const PantallaProveedores({
    super.key,
    required this.db,
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;

  /// Null si no hay sesión de caja abierta: la pantalla igual muestra todo,
  /// pero deshabilita pagar en efectivo/Mercado Pago (no hay dónde grabar
  /// el movimiento).
  final int? sesionCajaId;

  @override
  State<PantallaProveedores> createState() => _PantallaProveedoresState();
}

class _PantallaProveedoresState extends State<PantallaProveedores>
    with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _c.cargarTodo();

  late final ProveedoresControlador _c;

  @override
  void initState() {
    super.initState();
    _c = ProveedoresControlador(
      widget.db,
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
    );
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProveedoresControlador>.value(
      value: _c,
      child: Consumer<ProveedoresControlador>(
        builder: (context, c, _) {
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'proveedores',
            usuarioId: widget.usuarioId,
            sesionCajaId: widget.sesionCajaId,
            titulo: 'Proveedores',
            busqueda: BusquedaContextual(
              pista: 'Buscar producto, código o proveedor…',
              alCambiar: c.buscar,
            ),
            // Cuatro botones de igual peso al lado del título eran puro
            // ruido (Bruno, 2026-09-12: "no quiero 50 botones en cualquier
            // lado") — queda una sola acción visible, la más frecuente
            // ("+ Nuevo producto"); las otras tres (setup/mantenimiento, no
            // algo que se toque seguido) se juntan detrás del menú "Más
            // acciones", mismo patrón que ya usa la companion
            // (`pantalla_menu_companion.dart`). De paso se cae el `Wrap` a
            // dos líneas que hacía falta antes para que cuatro botones
            // entraran al piso mínimo de 1366px — con dos elementos ya no
            // hace falta.
            accion: c.cargando
                ? null
                : _AccionesProveedores(
                    controlador: c,
                    db: widget.db,
                    usuarioId: widget.usuarioId,
                  ),
            child: c.cargando
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: anchoListaProveedores,
                        child: ListaProveedores(controlador: c),
                      ),
                      const SizedBox(width: Espaciado.lg),
                      const Expanded(child: DetalleProveedor()),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// Fila de acción de `EncabezadoPantalla`: el período de las cifras, "Más
/// acciones" (lo que se toca poco) y dar de alta un proveedor. "Nuevo
/// producto" vive en el encabezado del proveedor elegido, a la derecha.
class _AccionesProveedores extends StatelessWidget {
  const _AccionesProveedores({
    required this.controlador,
    required this.db,
    required this.usuarioId,
  });

  final ProveedoresControlador controlador;
  final AppDatabase db;
  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GrupoPildoras<PeriodoResumen>(
          opciones: const [
            (PeriodoResumen.hoy, 'Hoy'),
            (PeriodoResumen.semana, 'Semana'),
            (PeriodoResumen.mes, 'Mes'),
            (PeriodoResumen.desdeUltimoPago, 'Desde el último pago'),
          ],
          elegida: c.periodo,
          onElegir: c.cambiarPeriodo,
        ),
        const SizedBox(width: Espaciado.sm),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Más acciones',
          onSelected: (accion) => accion(),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: () =>
                  mostrarDialogoPromos(context, db: db, usuarioId: usuarioId),
              child: const Text('Promos'),
            ),
            PopupMenuItem(
              value: () => mostrarDialogoImportarCsv(
                context,
                db: db,
                usuarioId: usuarioId,
              ),
              child: const Text('Importar CSV'),
            ),
            PopupMenuItem(
              value: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PantallaStockProveedor(db: db, usuarioId: usuarioId),
                ),
              ),
              child: const Text('Conteo de stock'),
            ),
            // Antes era un apartado propio del menú (2026-09-26, Bruno:
            // "que apartados podemos resumir, agrupar"): compara los precios
            // de los productos, que viven acá.
            PopupMenuItem(
              value: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PantallaCompararPrecios(
                    db: db,
                    usuarioId: usuarioId,
                    sesionCajaId: c.sesionCajaId,
                  ),
                ),
              ),
              child: const Text('Comparar precios'),
            ),
          ],
        ),
        const SizedBox(width: Espaciado.sm),
        BotonSecundario(
          texto: '+ Nuevo proveedor',
          onPressed: () =>
              mostrarDialogoNuevoProveedor(context, controlador: c),
        ),
      ],
    );
  }
}
