// Nivel 3 "Avanzado". Segunda corrección post-revisión (dibujo de Bruno):
// el panel principal de Proveedores pasó a ser puramente informativo ("es
// para mirar"), así que todo lo editable o accionable se mudó acá —
// colchón, medio de pago, código, días de pedido/entrega,
// activar/desactivar, y las acciones de separar y pagar. "Es donde
// correspondían según los tres niveles" (Bruno).
//
// Pasado al kit (corrección post-aprobación): `Modal` en vez de
// `AlertDialog`, `CampoTexto`/`BotonPrimario`/`BotonSecundario` en vez de
// controles sueltos. El desplegable de medio de pago sigue con su
// contenedor propio — el kit todavía no tiene una pieza de selección.
//
// Serra Cigarros (2026-09-25) usa este mismo diálogo como "Ver lata": la
// sección de arriba pasa a ser la de la lata (`SeccionLataCigarrillos`) en
// vez de separar/pagar, y no hay desplegable de medio de pago (Regla 6 lo
// fija en Efectivo). El resto del formulario es el mismo, a propósito — un
// solo lugar para editar nombre/código/días/activo.

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_reposicion.dart'
    show ResumenReposicionProveedor, mediosPagoProveedor;
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'dialogo_pagar_proveedor.dart';
import 'proveedores_controlador.dart';
import 'seccion_lata_cigarrillos.dart';

Future<void> mostrarDialogoAvanzadoProveedor(
  BuildContext context, {
  required Proveedor proveedor,
  required ProveedoresControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoAvanzadoProveedor(
      proveedor: proveedor,
      controlador: controlador,
    ),
  );
}

class _DialogoAvanzadoProveedor extends StatefulWidget {
  const _DialogoAvanzadoProveedor({
    required this.proveedor,
    required this.controlador,
  });

  final Proveedor proveedor;
  final ProveedoresControlador controlador;

  @override
  State<_DialogoAvanzadoProveedor> createState() =>
      _DialogoAvanzadoProveedorState();
}

class _DialogoAvanzadoProveedorState extends State<_DialogoAvanzadoProveedor> {
  late final _nombreCtrl = TextEditingController(text: widget.proveedor.nombre);
  late final _codigoCtrl = TextEditingController(text: widget.proveedor.codigo);
  late final _diaPedidoCtrl = TextEditingController(
    text: widget.proveedor.diaPedido ?? '',
  );
  late final _diaEntregaCtrl = TextEditingController(
    text: widget.proveedor.diaEntrega ?? '',
  );
  late bool _activo = widget.proveedor.activo;
  late String _medioPago = widget.proveedor.medioPago;
  String? _error;

  bool get _esLata => widget.proveedor.codigo == 'SC';

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final codigo = _codigoCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }
    if (codigo.isEmpty) {
      setState(() => _error = 'Falta el código');
      return;
    }

    try {
      await widget.controlador.guardarAvanzado(
        nombre: nombre,
        codigo: codigo,
        diaPedido: _diaPedidoCtrl.text.trim().isEmpty
            ? null
            : _diaPedidoCtrl.text.trim(),
        diaEntrega: _diaEntregaCtrl.text.trim().isEmpty
            ? null
            : _diaEntregaCtrl.text.trim(),
        activo: _activo,
        medioPago: _medioPago,
      );
    } catch (e) {
      // Mismo criterio que `crearProducto`/`actualizarProducto`
      // (`repositorio_productos.dart`): `codigo` es unique en la base — en
      // vez de interpretar el mensaje de sqlite3, se confirma buscando
      // directo si ya existe otro proveedor con este código.
      final db = widget.controlador.db;
      final otro =
          await (db.select(db.proveedores)..where(
                (p) =>
                    p.codigo.equals(codigo) &
                    p.id.equals(widget.proveedor.id).not(),
              ))
              .getSingleOrNull();
      if (mounted) {
        setState(
          () => _error = otro != null
              ? 'Ya hay un proveedor con el código "$codigo"'
              : 'No se pudo guardar: $e',
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _diaPedidoCtrl.dispose();
    _diaEntregaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: _esLata
          ? 'Lata — ${widget.proveedor.nombre}'
          : 'Avanzado — ${widget.proveedor.nombre}',
      contenido: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reactivo al controlador (no a `widget.proveedor`, que es una
            // foto fija de cuando se abrió el diálogo): separar/pagar
            // cambian estos números sin cerrar el diálogo.
            if (_esLata)
              SeccionLataCigarrillos(controlador: widget.controlador)
            else
              ListenableBuilder(
                listenable: widget.controlador,
                builder: (context, _) => _SeccionReposicion(
                  detalle: widget.controlador.detalleSeleccionado,
                  controlador: widget.controlador,
                ),
              ),
            const SizedBox(height: Espaciado.lg),
            CampoTexto(
              key: const Key('campo_nombre'),
              controller: _nombreCtrl,
              etiqueta: 'Nombre',
            ),
            const SizedBox(height: Espaciado.md),
            CampoTexto(
              key: const Key('campo_codigo'),
              controller: _codigoCtrl,
              etiqueta: 'Código',
            ),
            const SizedBox(height: Espaciado.md),
            CampoTexto(
              key: const Key('campo_dia_pedido'),
              controller: _diaPedidoCtrl,
              etiqueta: 'Día de pedido (opcional)',
            ),
            const SizedBox(height: Espaciado.md),
            CampoTexto(
              key: const Key('campo_dia_entrega'),
              controller: _diaEntregaCtrl,
              etiqueta: 'Día de entrega (opcional)',
            ),
            if (!_esLata) ...[
              const SizedBox(height: Espaciado.md),
              Text(
                'Medio de pago',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: Espaciado.xs),
              // `underline: SizedBox.shrink()`: sin esto el desplegable de
              // Material dibuja una línea propia bajo el control — el único
              // borde "de verdad" que le queda a la app es el de
              // `OutlinedButton`/`Switch` (`DISENO.md`, "Preferí espacio
              // antes que línea"), ningún control nuevo agrega uno más.
              Container(
                height: Medidas.alturaControl,
                padding: const EdgeInsets.symmetric(horizontal: Espaciado.md),
                decoration: BoxDecoration(
                  color: context.colores.fondo,
                  borderRadius: BorderRadius.circular(radioControlEscritorio),
                ),
                child: DropdownButton<String>(
                  value: _medioPago,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final medio in mediosPagoProveedor)
                      DropdownMenuItem(value: medio, child: Text(medio)),
                  ],
                  onChanged: (v) => setState(() => _medioPago = v!),
                ),
              ),
            ],
            const SizedBox(height: Espaciado.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: Espaciado.sm),
              Text(_error!, style: TextStyle(color: context.colores.error)),
            ],
          ],
        ),
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Guardar', onPressed: _guardar),
      ],
    );
  }
}

/// Costo real pendiente, cuánto separar, y la acción correspondiente
/// (separar o pagar) — el contexto que hace falta para decidir esa acción,
/// junto a la acción misma. Vivía en el nivel 2 antes de la segunda
/// corrección post-revisión.
class _SeccionReposicion extends StatelessWidget {
  const _SeccionReposicion({required this.detalle, required this.controlador});

  final ResumenReposicionProveedor? detalle;
  final ProveedoresControlador controlador;

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    if (d == null) return const SizedBox.shrink();
    final haySeparado = d.separadoCentavos > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filaDato(
          context,
          'Costo real pendiente',
          formatearARS(d.pendienteSinSepararCentavos),
        ),
        const SizedBox(height: Espaciado.sm),
        _filaDato(
          context,
          'Colchón (ganancia retenida)',
          formatearARS(d.colchonCentavos),
        ),
        const SizedBox(height: Espaciado.sm),
        _filaDato(
          context,
          'Cuánto separar',
          formatearARS(d.sugeridoASepararCentavos),
        ),
        const SizedBox(height: Espaciado.xs),
        // De dónde sale (Bruno, 2026-09-26): lo cobrado por MP, más lo que
        // los cigarrillos cobrados por MP le sacaron al efectivo, está en MP.
        _filaDato(
          context,
          '   del cajón',
          formatearARS(d.sugeridoASepararEfectivoCentavos),
        ),
        _filaDato(
          context,
          '   de Mercado Pago',
          formatearARS(d.costoRealMpCentavos),
        ),
        const SizedBox(height: Espaciado.md),
        if (haySeparado) ...[
          _filaDato(
            context,
            'Separado el ${_fecha(d.separadoFecha!)}',
            formatearARS(d.separadoCentavos),
          ),
          const SizedBox(height: Espaciado.xs),
          _filaDato(
            context,
            '   del cajón',
            formatearARS(d.separadoEfectivoCentavos),
          ),
          _filaDato(
            context,
            '   de Mercado Pago',
            formatearARS(d.separadoMpCentavos),
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Esperando pago.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.sm),
          BotonSecundario(
            texto: 'Pagar',
            onPressed: () => mostrarDialogoPagarProveedor(
              context,
              resumen: d,
              onPagar: controlador.pagar,
            ),
          ),
        ] else
          BotonSecundario(
            texto: 'Marcar separado',
            onPressed: d.pendienteSinSepararCentavos > 0
                ? controlador.separar
                : null,
          ),
      ],
    );
  }

  String _fecha(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}';

  Widget _filaDato(BuildContext context, String etiqueta, String valor) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            etiqueta,
            style: textTheme.bodyMedium?.copyWith(
              color: context.colores.textoSecundario,
            ),
          ),
        ),
        Text(valor, style: textTheme.titleMedium!.tabular),
      ],
    );
  }
}
