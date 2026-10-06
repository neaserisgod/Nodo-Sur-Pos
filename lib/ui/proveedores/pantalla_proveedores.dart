// Proveedores (fase 13) — reemplaza a Reposición, y absorbe Productos y
// Stock por proveedor (corrección post-aprobación del kit: esas dos
// pantallas salieron del menú). Tres niveles de información (El dueño,
// principio de fatiga visual, `DISENO.md`): la lista muestra solo el nombre
// (nivel 1), entrar a un proveedor (o "Todos"/"Sin proveedor") trae el
// detalle (nivel 2), y "Avanzado" (nivel 3) queda detrás de un botón.
//
// "Lenguaje de diseño" (El dueño, 2026-09-26, mock `Proveedores.dc.html`,
// "la distribución es la idea"): vuelve la lista + detalle — proveedores
// siempre a la izquierda (`ListaProveedores`), el elegido a la derecha
// (`DetalleProveedor`). Reemplaza al dropdown de proveedor (cuarta pasada
// del 2026-09-25) y al picker de tarjetas grandes (séptima pasada), que
// obligaban a abrir un menú o entrar y salir para cambiar de proveedor.
// Editar cualquier producto sigue siendo un `Modal`.
//
// Rediseño v4 (2026-10-06): hecha desde cero como el mock (`SCR.proveedores`). Las acciones vuelven a estar a la vista
// al lado del título (Leer factura, Promos, Importar CSV, Nuevo proveedor), el período pasa a las cifras del detalle, y
// "Conteo de stock"/"Comparar precios" van con el proveedor (también están en el mega-menú de Proveedores).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/armazon_gestion.dart';
import '../kit/kit.dart';
import '../navegacion/refresco_por_celular.dart';
import 'detalle_proveedor.dart';
import 'dialogo_importar_csv.dart';
import 'dialogo_leer_factura.dart';
import 'dialogo_nuevo_proveedor.dart';
import 'dialogo_promos.dart';
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

class _PantallaProveedoresState extends State<PantallaProveedores> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _c.cargarTodo();

  late final ProveedoresControlador _c;

  @override
  void initState() {
    super.initState();
    _c = ProveedoresControlador(widget.db, usuarioId: widget.usuarioId, sesionCajaId: widget.sesionCajaId);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.db;
    final usuarioId = widget.usuarioId;
    final ancho = MediaQuery.sizeOf(context).width;
    // A 1366 los cuatro botones no entran al lado del título en tamaño grande.
    final tam = ancho >= 1700 ? TamBtn.md : TamBtn.sm;
    return ChangeNotifierProvider<ProveedoresControlador>.value(
      value: _c,
      child: Consumer<ProveedoresControlador>(
        // Prender o apagar Promos/Comparador en Configuración cambia los botones sin salir de la pantalla.
        builder: (context, c, _) => ValueListenableBuilder(
          valueListenable: modulosActuales,
          builder: (context, _, _) => PantallaGestion(
            db: db,
            claveActiva: 'proveedores',
            usuarioId: usuarioId,
            sesionCajaId: widget.sesionCajaId,
            titulo: 'Proveedores',
            acciones: [
              // Lectura de facturas con IA (2026-10-05): todavía es una prueba, no guarda nada.
              Btn('Leer factura', tam: tam, variante: VarBtn.ai, icono: Ic.sparkle, onTap: () => mostrarDialogoLeerFactura(context, db: db)),
              if (moduloActivo(Modulo.promos))
                Btn('Promos', tam: tam, variante: VarBtn.ai, icono: Ic.sparkle, onTap: () => mostrarDialogoPromos(context, db: db, usuarioId: usuarioId)),
              Btn('Importar CSV', tam: tam, variante: VarBtn.ton, onTap: () => mostrarDialogoImportarCsv(context, db: db, usuarioId: usuarioId)),
              Btn(
                'Nuevo proveedor',
                key: const Key('boton_nuevo_proveedor'),
                tam: tam,
                variante: VarBtn.dark,
                icono: Ic.plus,
                onTap: () => mostrarDialogoNuevoProveedor(context, controlador: c),
              ),
            ],
            child: c.cargando
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: anchoListaProveedores(ancho), child: ListaProveedores(controlador: c)),
                      const SizedBox(width: 24),
                      const Expanded(child: DetalleProveedor()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
