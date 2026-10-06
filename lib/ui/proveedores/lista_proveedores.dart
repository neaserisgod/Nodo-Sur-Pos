// Columna izquierda de Proveedores, hecha desde el mock v4 (`SCR.proveedores`, `provRows`): el buscador grande, los
// filtros Todos / Con deuda, y una fila por proveedor con cuántos productos tiene, qué día se le pide, "Pedir hoy" si
// toca, y lo que se le debe (o "Al día"). "Todos los productos" y "Sin proveedor" van arriba, como en el mock.

import 'package:flutter/material.dart';

import '../../domain/periodo.dart' show tocaPedirHoy;
import '../kit/kit.dart';
import 'proveedores_controlador.dart';

/// Ancho de la columna en el mock (`grid-template-columns:470px 1fr`); a 1366 se angosta para que el detalle entre.
double anchoListaProveedores(double anchoVentana) => anchoVentana >= 1700 ? 470 : 380;

String _productos(int n) => '$n producto${n == 1 ? '' : 's'}';

class ListaProveedores extends StatefulWidget {
  const ListaProveedores({super.key, required this.controlador});

  final ProveedoresControlador controlador;

  @override
  State<ListaProveedores> createState() => _ListaProveedoresState();
}

class _ListaProveedoresState extends State<ListaProveedores> {
  bool _soloConDeuda = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    final hoy = DateTime.now();
    final filas = <Widget>[
      if (!_soloConDeuda) ...[
        Rowb(
          key: const Key('proveedor_todos'),
          titulo: 'Todos los productos',
          detalle: _productos(c.todosLosProductos.length),
          izquierda: const Ibox(Ic.box),
          elegida: c.vista == SeleccionProveedor.todos,
          onTap: c.seleccionarTodos,
        ),
        if (c.sinProveedorVisible)
          Rowb(
            key: const Key('proveedor_sin'),
            titulo: 'Sin proveedor',
            detalle: _productos(c.cantidadDeProductos(null)),
            izquierda: const Ibox(Ic.warn),
            elegida: c.vista == SeleccionProveedor.sinProveedor,
            onTap: c.seleccionarSinProveedor,
          ),
      ],
      for (final r in c.resumenes)
        if (c.proveedorVisible(r.proveedor) && (!_soloConDeuda || c.deudaDe(r.proveedor.id) > 0))
          Rowb(
            key: Key('proveedor_${r.proveedor.id}'),
            titulo: r.proveedor.nombre,
            lineasTitulo: 2,
            lineasDetalle: 2,
            detalle: [
              _productos(c.cantidadDeProductos(r.proveedor.id)),
              if (r.proveedor.diaPedido != null) 'pedido ${r.proveedor.diaPedido!.toLowerCase()}',
            ].join(' · '),
            izquierda: const Ibox(Ic.truck),
            elegida: c.vista == SeleccionProveedor.proveedor && c.seleccionado?.id == r.proveedor.id,
            onTap: () => c.seleccionar(r.proveedor.id),
            derecha: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (tocaPedirHoy(r.proveedor.diaPedido, hoy)) ...[
                  const Etiqueta('Pedir hoy', tono: TonoMock.w),
                  const SizedBox(height: 6),
                ],
                if (c.deudaDe(r.proveedor.id) > 0)
                  Etiqueta('Le debés ${pesos(c.deudaDe(r.proveedor.id))}', tono: TonoMock.b)
                else
                  const Etiqueta('Al día', tono: TonoMock.g),
              ],
            ),
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BuscadorPagina(
          campoKey: const Key('busqueda_contextual'),
          pista: 'Buscar un proveedor o un producto…',
          onCambio: c.buscar,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ChipMock('Todos', elegido: !_soloConDeuda, onTap: () => setState(() => _soloConDeuda = false)),
            const SizedBox(width: 8),
            ChipMock('Con deuda', elegido: _soloConDeuda, onTap: () => setState(() => _soloConDeuda = true)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: filas.isEmpty
              ? const Vacio(texto: 'Sin coincidencias', icono: null, padding: EdgeInsets.symmetric(vertical: 50))
              : ListView.separated(
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: filas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => Aparecer.tarjeta(orden: i < 8 ? i : 8, child: filas[i]),
                ),
        ),
      ],
    );
  }
}
