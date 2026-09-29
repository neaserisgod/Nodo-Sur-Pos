// Panel derecho de Proveedores. "Lenguaje de diseño" (Bruno, 2026-09-26,
// mock `Proveedores.dc.html`): encabezado del proveedor (iniciales, nombre,
// cómo se le paga y qué días viene, "Avanzado"/"Ver lata" y "Nuevo
// producto"), una fila de cifras del período, y los productos en tarjetas
// con precio, margen, costo, vendidos y stock contra el mínimo, con un
// filtro "Stock bajo". Editar un producto sigue siendo tocar su tarjeta
// (`Modal`, `dialogo_editar_producto.dart`); mantener apretado o el
// casillero marca para edición masiva.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositorio_reposicion.dart' show ProductoDeProveedor;
import '../../domain/dinero.dart';
import '../comun/boton_destacado.dart';
import '../comun/botones.dart';
import '../comun/estado_vacio.dart';
import '../comun/tarjetas.dart';
import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'dialogo_avanzado_proveedor.dart';
import 'dialogo_cuenta_corriente.dart';
import 'dialogo_edicion_masiva.dart';
import 'dialogo_editar_producto.dart';
import 'proveedores_controlador.dart';
import 'selector_porcentaje.dart';

Future<void> _abrirCuentaCorriente(
  BuildContext context,
  ProveedoresControlador c,
) async {
  await mostrarDialogoCuentaCorriente(
    context,
    db: c.db,
    proveedor: c.seleccionado!,
    usuarioId: c.usuarioId,
    sesionCajaId: c.sesionCajaId,
  );
  await c.cargarTodo();
}

class DetalleProveedor extends StatelessWidget {
  const DetalleProveedor({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProveedoresControlador>();
    final cifras = c.cifras;
    if (cifras == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final proveedor = c.seleccionado;

    final subtitulo = switch (c.vista) {
      SeleccionProveedor.todos => 'Los productos de todos los proveedores',
      SeleccionProveedor.sinProveedor =>
        'Productos que todavía no tienen proveedor',
      SeleccionProveedor.proveedor => [
        'Se le paga en ${proveedor!.medioPago.toLowerCase()}',
        if (proveedor.diaPedido != null) 'pedido: ${proveedor.diaPedido}',
        if (proveedor.diaEntrega != null) 'entrega: ${proveedor.diaEntrega}',
      ].join(' · '),
    };

    final bajos = c.productos.where(c.avisaStock).length;
    final cajas = <(String, String, Tono?)>[
      ('Vendido', formatearARS(cifras.venta), null),
      ('Ganancia', formatearARS(cifras.ganancia), Tono.ganancia),
      ('Stock a costo', formatearARS(cifras.costo), null),
      ('Stock a precio', formatearARS(cifras.stock), null),
      if (cifras.separado != null)
        ('Separado', formatearARS(cifras.separado!), null),
      if (c.esProveedorReal && c.deudaDe(proveedor!.id) > 0)
        ('Le debés', formatearARS(c.deudaDe(proveedor.id)), Tono.alerta),
    ];

    return Superficie(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.xl,
        Espaciado.xl,
        Espaciado.xl,
        Espaciado.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarIniciales(
                texto: inicialesDe(c.tituloSeleccion),
                icono: c.esProveedorReal
                    ? null
                    : (c.vista == SeleccionProveedor.todos
                          ? IconosPlazoleta.inventory2Outlined
                          : IconosPlazoleta.helpOutline),
                elegido: true,
                tamanio: 56,
              ),
              const SizedBox(width: Espaciado.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.tituloSeleccion, style: textTheme.titleLarge),
                    Text(subtitulo, style: textTheme.bodySmall),
                  ],
                ),
              ),
              if (c.esProveedorReal) ...[
                // Cuenta corriente (2026-09-29): lo que se le debe a este
                // proveedor, con cargar deuda y pagar desde ahí. Con texto
                // cuando hay lugar; solo ícono (con tooltip) a media
                // pantalla, donde la fila de acciones no da para más.
                if (MediaQuery.sizeOf(context).width >= 1300)
                  BotonSecundario(
                    texto: c.deudaDe(proveedor!.id) > 0
                        ? 'Deuda ${formatearARS(c.deudaDe(proveedor.id))}'
                        : 'Deuda',
                    onPressed: () => _abrirCuentaCorriente(context, c),
                  )
                else
                  Tooltip(
                    message: 'Cuenta corriente (lo que le debés)',
                    child: Presionable(
                      radio: 999,
                      color: c.deudaDe(proveedor!.id) > 0
                          ? context.acentosPlazoleta.alertaSuave
                          : context.colores.fondo,
                      onTap: () => _abrirCuentaCorriente(context, c),
                      child: Padding(
                        padding: const EdgeInsets.all(Espaciado.md),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 22,
                          color: c.deudaDe(proveedor.id) > 0
                              ? context.acentosPlazoleta.alerta
                              : context.colores.textoSecundario,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: Espaciado.sm),
                BotonSecundario(
                  // Serra Cigarros: sus Separar/Pagar genéricos siempre
                  // daban $0 (Regla 6) — ahí el mismo diálogo muestra la
                  // lata (ver `dialogo_avanzado_proveedor.dart`).
                  texto: c.esSerraCigarros ? 'Ver lata' : 'Avanzado',
                  onPressed: () => mostrarDialogoAvanzadoProveedor(
                    context,
                    proveedor: c.seleccionado!,
                    controlador: c,
                  ),
                ),
                const SizedBox(width: Espaciado.sm),
              ],
              BotonDestacado(
                texto: 'Nuevo producto',
                icono: IconosPlazoleta.add,
                onTap: () => mostrarDialogoEditarProducto(
                  context,
                  controlador: c,
                  proveedorIdPreseleccionado: c.esProveedorReal
                      ? c.seleccionado!.id
                      : null,
                ),
              ),
            ],
          ),
          if (c.esProveedorReal && !c.esSerraCigarros) ...[
            const SizedBox(height: Espaciado.lg),
            SelectorPorcentajeProveedor(controlador: c),
          ],
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              for (var i = 0; i < cajas.length; i++) ...[
                if (i > 0) const SizedBox(width: Espaciado.md),
                Expanded(
                  child: CajaCifra(
                    etiqueta: cajas[i].$1,
                    valor: cajas[i].$2,
                    tono: cajas[i].$3,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Espaciado.xl),
          if (c.enModoSeleccionMasiva)
            _BarraSeleccionMasiva(controlador: c)
          else
            Row(
              children: [
                Text(
                  'Productos',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: Pesos.fuerte,
                  ),
                ),
                const SizedBox(width: Espaciado.lg),
                GrupoPildoras<bool>(
                  opciones: [
                    (false, 'Todos (${c.productos.length})'),
                    (true, 'Stock bajo ($bajos)'),
                  ],
                  elegida: c.soloStockBajo,
                  onElegir: c.cambiarSoloStockBajo,
                ),
              ],
            ),
          const SizedBox(height: Espaciado.md),
          Expanded(child: _GrillaProductos(controlador: c)),
        ],
      ),
    );
  }
}

class _GrillaProductos extends StatelessWidget {
  const _GrillaProductos({required this.controlador});

  final ProveedoresControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    final productos = c.productosVisibles;
    if (productos.isEmpty) {
      return EstadoVacio(
        mensaje: c.soloStockBajo
            ? 'Nada con stock bajo acá'
            : 'No hay productos acá',
      );
    }
    final enModoSeleccion = c.enModoSeleccionMasiva;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: Espaciado.md,
        crossAxisSpacing: Espaciado.md,
        mainAxisExtent: 168,
      ),
      itemCount: productos.length,
      itemBuilder: (context, i) {
        final producto = productos[i];
        return _TarjetaProductoProveedor(
          producto: producto,
          vendidos: c.vendidoEnPeriodo[producto.id] ?? 0,
          avisaStock: c.avisaStock(producto),
          seleccionado: c.seleccionMasiva.contains(producto.id),
          onTap: enModoSeleccion
              ? () => c.alternarSeleccionMasiva(producto.id)
              : () => mostrarDialogoEditarProducto(
                  context,
                  controlador: c,
                  productoId: producto.id,
                ),
          onToggleSeleccion: () => c.alternarSeleccionMasiva(producto.id),
        );
      },
    );
  }
}

/// Nombre y casillero arriba; precio grande con su margen; costo y
/// vendidos; y el stock contra el mínimo abajo — el orden del mock.
class _TarjetaProductoProveedor extends StatelessWidget {
  const _TarjetaProductoProveedor({
    required this.producto,
    required this.vendidos,
    required this.avisaStock,
    required this.seleccionado,
    required this.onTap,
    required this.onToggleSeleccion,
  });

  final ProductoDeProveedor producto;
  final int vendidos;
  final bool avisaStock;
  final bool seleccionado;
  final VoidCallback onTap;
  final VoidCallback onToggleSeleccion;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final unidad = producto.esPesable ? ' g' : '';
    final porKilo = producto.esPesable ? '/kg' : '';
    final precio = producto.precioCentavos == null
        ? 'Sin precio'
        : '${formatearARS(producto.precioCentavos!)}$porKilo';
    final costo = producto.costoCentavos == null
        ? 'sin costo'
        : formatearARS(producto.costoCentavos!);
    final agotado = producto.stock <= 0;
    final colorStock = agotado && avisaStock
        ? colores.error
        : (avisaStock ? acentos.alerta : colores.textoSecundario);

    return Presionable(
      radio: radioControlEscritorio + 2,
      onTap: onTap,
      onLongPress: onToggleSeleccion,
      color: seleccionado
          ? colores.destacado
          : Color.lerp(colores.fondo, colores.fondoBloque, 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Espaciado.lg,
          Espaciado.md,
          Espaciado.sm,
          Espaciado.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: Pesos.fuerte,
                    ),
                  ),
                ),
                // Casillero de edición masiva (Bruno, 2026-09-16: "subir el
                // precio de 3 productos... a la vez").
                Checkbox(
                  value: seleccionado,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => onToggleSeleccion(),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(precio, style: textTheme.titleLarge?.tabular),
                  ),
                ),
                if (producto.margenBp != null) ...[
                  const SizedBox(width: Espaciado.sm),
                  Insignia(
                    texto: '+${(producto.margenBp! / 100).round()}%',
                    tono: Tono.ganancia,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Costo $costo · vendidos $vendidos$unidad',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: Espaciado.sm),
            Row(
              children: [
                if (avisaStock) ...[
                  Icon(
                    IconosPlazoleta.errorOutline,
                    size: 16,
                    color: colorStock,
                  ),
                  const SizedBox(width: Espaciado.xs),
                ],
                Text(
                  agotado ? 'Sin stock' : 'Stock ${producto.stock}$unidad',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorStock,
                    fontWeight: Pesos.fuerte,
                  ),
                ),
                const Spacer(),
                if (producto.stockMinimo != null && producto.stockMinimo! > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: Espaciado.sm),
                    child: Text(
                      'mín. ${producto.stockMinimo}$unidad',
                      style: textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reemplaza la fila "Productos + filtro" mientras hay algo marcado — mismo
/// lugar de la pantalla (nunca dos elementos compitiendo por el mismo
/// espacio). "Editar" abre `DialogoEdicionMasiva` (precio, costo, categoría,
/// proveedor, activar/desactivar); "Cancelar" limpia la selección.
class _BarraSeleccionMasiva extends StatelessWidget {
  const _BarraSeleccionMasiva({required this.controlador});

  final ProveedoresControlador controlador;

  @override
  Widget build(BuildContext context) {
    final cantidad = controlador.seleccionMasiva.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$cantidad producto${cantidad == 1 ? '' : 's'} marcado${cantidad == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: Espaciado.sm),
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: controlador.limpiarSeleccionMasiva,
        ),
        const SizedBox(width: Espaciado.sm),
        BotonPrimario(
          texto: 'Editar',
          onPressed: () =>
              mostrarDialogoEdicionMasiva(context, controlador: controlador),
        ),
      ],
    );
  }
}
