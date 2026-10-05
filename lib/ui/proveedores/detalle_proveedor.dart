// Panel derecho de Proveedores. "Lenguaje de diseño" (El dueño, 2026-09-26,
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
import '../tema/tema_inverso.dart';
import '../tema/superficie.dart';
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
                  // Distribuidora de Cigarrillos: sus Separar/Pagar genéricos siempre
                  // daban $0 (Regla 6) — ahí el mismo diálogo muestra la
                  // lata (ver `dialogo_avanzado_proveedor.dart`).
                  texto: c.esCajaAparte ? 'Ver lata' : 'Avanzado',
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
          if (c.esProveedorReal && !c.esCajaAparte) ...[
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

/// Los productos como una tabla de filas (igual que el mock): nombre con lo
/// vendido, stock, costo, precio y margen. Tocar una fila abre el editor;
/// mantener apretado (o el casillero) la marca para la edición masiva.
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
    final colores = context.colores;
    final estiloCabecera = Theme.of(context).textTheme.labelMedium?.copyWith(color: colores.textoTenue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.sm),
          child: Row(
            children: [
              const SizedBox(width: 32),
              Expanded(flex: 5, child: Text('Producto', style: estiloCabecera)),
              Expanded(flex: 3, child: Text('Stock', style: estiloCabecera)),
              Expanded(flex: 2, child: Text('Costo', textAlign: TextAlign.right, style: estiloCabecera)),
              Expanded(flex: 3, child: Text('Precio', textAlign: TextAlign.right, style: estiloCabecera)),
              Expanded(flex: 2, child: Text('Margen', textAlign: TextAlign.right, style: estiloCabecera)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: productos.length,
            separatorBuilder: (_, _) => const SizedBox(height: Espaciado.sm),
            itemBuilder: (context, i) {
              final producto = productos[i];
              return _FilaProductoProveedor(
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
          ),
        ),
      ],
    );
  }
}

/// Una fila de la tabla de productos: casillero, nombre (con lo vendido),
/// stock contra el mínimo, costo, precio y margen.
class _FilaProductoProveedor extends StatelessWidget {
  const _FilaProductoProveedor({
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
    final inv = coloresDeFila(context, seleccionado);
    final colores = inv.colores;
    final textTheme = inv.textTheme;
    final acentos = context.acentosPlazoleta;
    final unidad = producto.esPesable ? ' g' : '';
    final porKilo = producto.esPesable ? '/kg' : '';
    final precio = producto.precioCentavos == null
        ? 'Sin precio'
        : '${formatearARS(producto.precioCentavos!)}$porKilo';
    final costo = producto.costoCentavos == null
        ? 'sin costo'
        : formatearARS(producto.costoCentavos!);
    final agotado = producto.stock <= 0;
    final colorStock = seleccionado
        ? colores.textoSecundario
        : agotado && avisaStock
            ? colores.error
            : (avisaStock ? acentos.alerta : colores.textoSecundario);

    return Presionable(
      radio: 26,
      onTap: onTap,
      onLongPress: onToggleSeleccion,
      color: seleccionado ? colores.acento : colores.fondo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        child: Row(
          children: [
            SizedBox(
              width: Medidas.alturaControl,
              height: Medidas.alturaControl,
              // Casillero de edición masiva (El dueño, 2026-09-16: "subir el
              // precio de 3 productos... a la vez").
              child: Semantics(
                label: 'Seleccionar ${producto.nombre}',
                child: Checkbox(
                  value: seleccionado,
                  onChanged: (_) => onToggleSeleccion(),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                  Text('vendidos $vendidos$unidad', style: textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  if (avisaStock) ...[
                    IconoPlz(IconosPlazoleta.errorOutline, size: 16, color: colorStock),
                    const SizedBox(width: Espaciado.xs),
                  ],
                  Flexible(
                    child: Text(
                      agotado ? 'Sin stock' : '${producto.stock}$unidad',
                      style: textTheme.bodyMedium?.copyWith(color: colorStock, fontWeight: Pesos.medium).tabular,
                    ),
                  ),
                  if (producto.stockMinimo != null && producto.stockMinimo! > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: Espaciado.sm),
                      child: Text('mín. ${producto.stockMinimo}$unidad', style: textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(costo, textAlign: TextAlign.right, style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario).tabular),
            ),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(precio, style: textTheme.titleLarge?.tabular),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: producto.gananciaBp == null
                    ? const SizedBox.shrink()
                    : Insignia(texto: '${(producto.gananciaBp! / 100).round()} %', tono: Tono.ganancia),
              ),
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
