// Panel derecho de Proveedores, hecho desde el mock v4 (`provDet`, `kpiStrip`, `tabla`): arriba el proveedor (nombre,
// días, botones) y su cuenta corriente en el bloque oscuro; debajo las cifras del período, y la tabla de productos con
// casillero para la edición masiva. Para "Todos" y "Sin proveedor" el bloque oscuro cuenta productos en vez de deuda.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositorio_reposicion.dart' show ProductoDeProveedor;
import '../../domain/modulos.dart';
import '../../domain/periodo.dart';
import '../../domain/tablero.dart' show diasQueAlcanza;
import '../../servicios/modulos_activos.dart';
import '../comparar_precios/pantalla_comparar_precios.dart';
import '../kit/kit.dart';
import '../stock_proveedor/pantalla_stock_proveedor.dart';
import '../venta/dialogo_pagar_proveedor_rapido.dart';
import 'dialogo_avanzado_proveedor.dart';
import 'dialogo_cuenta_corriente.dart';
import 'dialogo_edicion_masiva.dart';
import 'dialogo_editar_producto.dart';
import 'pedir_por_whatsapp.dart';
import 'proveedores_controlador.dart';
import 'selector_porcentaje.dart';

Future<void> _abrirCuentaCorriente(BuildContext context, ProveedoresControlador c) async {
  await mostrarDialogoCuentaCorriente(
    context,
    db: c.db,
    proveedor: c.seleccionado!,
    usuarioId: c.usuarioId,
    sesionCajaId: c.sesionCajaId,
  );
  await c.cargarTodo();
}

/// "Pagar a proveedor": el pago rápido con este proveedor ya elegido. Sin caja abierta no hay de dónde sacar la plata
/// del cajón: abre la cuenta corriente, que ahí deja pagar "fuera de la caja".
Future<void> _pagar(BuildContext context, ProveedoresControlador c) async {
  final sesion = c.sesionCajaId;
  if (sesion == null) return _abrirCuentaCorriente(context, c);
  await pagarProveedorYAvisar(context, db: c.db, usuarioId: c.usuarioId, sesionCajaId: sesion, proveedorIdInicial: c.seleccionado!.id);
  await c.cargarTodo();
}

/// Edición masiva sin nada marcado: va sobre todos los productos que se ven (como el mock); se desmarcan al cerrar.
Future<void> _edicionMasiva(BuildContext context, ProveedoresControlador c) async {
  final marcadosAntes = c.seleccionMasiva.isNotEmpty;
  if (!marcadosAntes) {
    for (final p in c.productosVisibles) {
      c.alternarSeleccionMasiva(p.id);
    }
  }
  await mostrarDialogoEdicionMasiva(context, controlador: c);
  if (!marcadosAntes) c.limpiarSeleccionMasiva();
}

Future<void> _ganancia(BuildContext context, ProveedoresControlador c) => mostrarModalMock<void>(
  context,
  builder: (_) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => ModalMock(
      titulo: 'Ganancia sobre el precio',
      subtitulo: c.seleccionado?.nombre,
      ancho: AnchoModal.angosto,
      cuerpo: [
        SelectorPorcentajeProveedor(controlador: c),
        const Nota(texto: 'Los productos con precio fijo y los cigarrillos no se tocan. Cada cambio queda en el historial de precios.'),
      ],
    ),
  ),
);

class DetalleProveedor extends StatelessWidget {
  const DetalleProveedor({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProveedoresControlador>();
    if (c.cifras == null) return const SizedBox.shrink();
    // Los botones dependen de los módulos prendidos (Comparador).
    return ValueListenableBuilder(valueListenable: modulosActuales, builder: (context, _, _) => _cuerpo(c));
  }

  Widget _cuerpo(ProveedoresControlador c) {
    return LayoutBuilder(
      builder: (context, caja) {
        // Ventana baja (1366×768): arriba ocupa casi todo el alto, así que el detalle entero scrollea y la tabla va
        // completa debajo, en vez de quedar en una franja de dos filas.
        final bajo = caja.maxHeight < 640;
        final arriba = <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Aparecer.revelar(child: _Encabezado(c: c))),
                const SizedBox(width: 14),
                Expanded(child: Aparecer.revelar(orden: 1, child: _Cuenta(c: c))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Aparecer.revelar(orden: 2, child: _Cifras(c: c)),
          const SizedBox(height: 12),
          _CabeceraProductos(c: c),
          const SizedBox(height: 12),
        ];
        if (bajo) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...arriba, _TablaProductos(c: c, dentroDeScroll: true)],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...arriba,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Flexible(child: _TablaProductos(c: c))],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.c});
  final ProveedoresControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final real = c.esProveedorReal;
    final prov = c.seleccionado;
    final titulo = switch (c.vista) {
      SeleccionProveedor.todos => 'Todos los productos',
      SeleccionProveedor.sinProveedor => 'Sin proveedor',
      SeleccionProveedor.proveedor => prov!.nombre,
    };
    final detalle = switch (c.vista) {
      SeleccionProveedor.todos => 'Los productos de todos los proveedores',
      SeleccionProveedor.sinProveedor => 'Productos que todavía no tienen proveedor',
      SeleccionProveedor.proveedor => [
        if (prov!.diaPedido != null) 'Pedido ${prov.diaPedido}',
        if (prov.diaEntrega != null) 'entrega ${prov.diaEntrega}',
        'se le paga en ${prov.medioPago.toLowerCase()}',
        if (prov.colchonReposicionCentavos > 0) 'colchón de reposición ${pesos(prov.colchonReposicionCentavos)}',
      ].join(' · '),
    };
    void ir(Widget pantalla) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pantalla));
    final botones = <Widget>[
      Btn('Edición masiva', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, onTap: () => _edicionMasiva(context, c)),
      if (moduloActivo(Modulo.compararPrecios))
        Btn(
          'Comparar precios',
          tam: TamBtn.sm,
          variante: VarBtn.ton,
          sobreGris: true,
          onTap: () => ir(PantallaCompararPrecios(db: c.db, usuarioId: c.usuarioId, sesionCajaId: c.sesionCajaId)),
        ),
      if (real) ...[
        Btn('Contar stock', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, onTap: () => ir(PantallaStockProveedor(db: c.db, usuarioId: c.usuarioId))),
        if (!c.esCajaAparte) Btn('Ganancia %', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, onTap: () => _ganancia(context, c)),
        // Distribuidora de cigarrillos: separar y pagar por el camino genérico daban siempre $0 (Regla 6); el mismo
        // diálogo muestra la lata.
        Btn(
          c.esCajaAparte ? 'Ver lata' : 'Avanzado',
          tam: TamBtn.sm,
          variante: VarBtn.ton,
          sobreGris: true,
          onTap: () => mostrarDialogoAvanzadoProveedor(context, proveedor: prov!, controlador: c),
        ),
        Btn(
          'Pedir por WhatsApp',
          key: const Key('boton_pedir_whatsapp'),
          tam: TamBtn.sm,
          variante: VarBtn.ton,
          sobreGris: true,
          icono: Ic.phone,
          onTap: () => pedirPorWhatsApp(context, c),
        ),
      ],
    ];
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(28, 550, color: p.tinta, em: -.03, alto: 1.15)),
              ),
              if (real) ...[
                const SizedBox(width: 12),
                Btn(
                  'Editar',
                  tam: TamBtn.sm,
                  variante: VarBtn.ton,
                  sobreGris: true,
                  icono: Ic.edit,
                  etiqueta: 'Editar ${prov!.nombre}',
                  onTap: () => mostrarDialogoAvanzadoProveedor(context, proveedor: prov, controlador: c),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(detalle, style: estilo(15.5, 400, color: p.mute)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: botones),
        ],
      ),
    );
  }
}

class _Cuenta extends StatelessWidget {
  const _Cuenta({required this.c});
  final ProveedoresControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final prov = c.seleccionado;
    if (!c.esProveedorReal) {
      final todos = c.vista == SeleccionProveedor.todos;
      final bajos = c.productos.where(c.avisaStock).length;
      return BloqueHero(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(todos ? 'Productos en total' : 'Para completar', style: estilo(15, 600, color: p.heroSub)),
            NumeroQueCuenta(valor: c.productos.length, formato: (v) => '$v', estilo: estilo(42, 550, color: p.sobreHero, em: -.04, num: true)),
            Text(
              todos ? 'Con stock bajo: $bajos' : 'Asignales un proveedor desde Editar producto o la edición masiva.',
              style: estilo(14, 400, color: p.heroSub),
            ),
          ],
        ),
      );
    }
    final deuda = c.deudaDe(prov!.id);
    return BloqueHero(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Cuenta corriente · le debés', style: estilo(15, 600, color: p.heroSub)),
          const SizedBox(height: 6),
          NumeroQueCuenta(valor: deuda, formato: pesos, estilo: estilo(42, 550, color: p.sobreHero, em: -.04, num: true)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Btn('Pagar a proveedor', key: const Key('boton_pagar_a_proveedor'), tam: TamBtn.sm, variante: VarBtn.blue, onTap: () => _pagar(context, c)),
              _BotonSobreHero(texto: 'Ver movimientos', onTap: () => _abrirCuentaCorriente(context, c)),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.btn.sm` blanco translúcido sobre el bloque oscuro (`background:rgba(255,255,255,.14)`).
class _BotonSobreHero extends StatelessWidget {
  const _BotonSobreHero({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AlPasar(
      builder: (encima) => Tocable(
        onTap: onTap,
        radio: 999,
        etiqueta: texto,
        child: AnimatedContainer(
          duration: ms(200),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: p.sobreHero.withValues(alpha: encima ? .22 : .14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(texto, style: estilo(15, 550, color: p.sobreHero))]),
        ),
      ),
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.c});
  final ProveedoresControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final cifras = c.cifras!;
    final deuda = c.esProveedorReal
        ? c.deudaDe(c.seleccionado!.id)
        : (c.vista == SeleccionProveedor.todos ? c.deudaPorProveedor.values.fold(0, (a, b) => a + (b > 0 ? b : 0)) : 0);
    final celdas = <(String, int?, Color?)>[
      ('Vendido', cifras.venta, null),
      ('Ganancia', cifras.ganancia, p.g),
      ('Stock a costo', cifras.costo, null),
      ('Stock a precio', cifras.stock, null),
      // Sin un proveedor real no hay reposición: no hay nada separado que mostrar.
      if (cifras.separado != null) ('Separado', cifras.separado, null),
      ('Le debés', deuda, deuda > 0 ? p.b : null),
    ];
    final angosto = MediaQuery.sizeOf(context).width < 1700;
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Seg<PeriodoResumen>(
                alto: 40,
                tamanioTexto: 14,
                paddingOpcion: angosto ? 12 : 16,
                opciones: const [
                  (PeriodoResumen.hoy, 'Hoy'),
                  (PeriodoResumen.semana, 'Semana'),
                  (PeriodoResumen.mes, 'Mes'),
                  (PeriodoResumen.desdeUltimoPago, 'Desde el último pago'),
                ],
                valor: c.periodo,
                onCambio: c.cambiarPeriodo,
              ),
              const Spacer(),
              if (!angosto) Text('Con las ventas del período elegido', style: estilo(13, 400, color: p.mute)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, (etiqueta, valor, color)) in celdas.indexed) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(13, 600, color: p.mute)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: valor == null
                            ? Text('—', style: estilo(26, 550, color: p.mute, num: true))
                            : NumeroQueCuenta(valor: valor, formato: pesos, estilo: estilo(26, 550, color: color ?? p.tinta, em: -.03, num: true)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CabeceraProductos extends StatelessWidget {
  const _CabeceraProductos({required this.c});
  final ProveedoresControlador c;

  @override
  Widget build(BuildContext context) {
    final bajos = c.productos.where(c.avisaStock).length;
    final marcados = c.seleccionMasiva.length;
    return Row(
      children: [
        const Sec('Productos'),
        const SizedBox(width: 12),
        ChipMock('Todos (${c.productos.length})', chico: true, elegido: !c.soloStockBajo, onTap: () => c.cambiarSoloStockBajo(false)),
        const SizedBox(width: 8),
        ChipMock('Stock bajo ($bajos)', chico: true, elegido: c.soloStockBajo, onTap: () => c.cambiarSoloStockBajo(true)),
        const Spacer(),
        if (marcados > 0) ...[
          Btn('Desmarcar', tam: TamBtn.sm, variante: VarBtn.out, onTap: c.limpiarSeleccionMasiva),
          const SizedBox(width: 8),
          Btn(
            'Editar $marcados seleccionado${marcados == 1 ? '' : 's'}',
            key: const Key('boton_editar_seleccionados'),
            tam: TamBtn.sm,
            variante: VarBtn.dark,
            onTap: () => mostrarDialogoEdicionMasiva(context, controlador: c),
          ),
          const SizedBox(width: 8),
        ],
        Btn(
          'Nuevo producto',
          key: const Key('boton_nuevo_producto'),
          tam: TamBtn.sm,
          variante: VarBtn.ton,
          icono: Ic.plus,
          onTap: () => mostrarDialogoEditarProducto(
            context,
            controlador: c,
            proveedorIdPreseleccionado: c.esProveedorReal ? c.seleccionado!.id : null,
          ),
        ),
      ],
    );
  }
}

TonoMock _tonoGanancia(int porcentaje) => porcentaje >= 30 ? TonoMock.g : (porcentaje >= 22 ? TonoMock.neutro : TonoMock.w);

String _cantidad(ProductoDeProveedor x, int valor) =>
    x.esPesable ? '${(valor / 1000).toStringAsFixed(1).replaceAll('.', ',')} kg' : '$valor u.';

class _TablaProductos extends StatelessWidget {
  const _TablaProductos({required this.c, this.dentroDeScroll = false});
  final ProveedoresControlador c;
  final bool dentroDeScroll;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final productos = c.productosVisibles;
    final todosMarcados = productos.isNotEmpty && productos.every((x) => c.seleccionMasiva.contains(x.id));
    final angosto = MediaQuery.sizeOf(context).width < 1700;
    void editar(ProductoDeProveedor x) => mostrarDialogoEditarProducto(context, controlador: c, productoId: x.id);
    return Tabla(
      radio: 26,
      dentroDeScroll: dentroDeScroll,
      columnas: [
        const ColumnaTabla('', ancho: 64),
        const ColumnaTabla('Producto', flex: 5),
        if (!angosto) const ColumnaTabla('Código', flex: 3),
        const ColumnaTabla('Costo', flex: 2, derecha: true),
        const ColumnaTabla('Precio', flex: 2, derecha: true),
        const ColumnaTabla('Ganancia', flex: 2, derecha: true),
        const ColumnaTabla('Vendido 30 d', flex: 2, derecha: true),
        const ColumnaTabla('Stock', flex: 2, derecha: true),
        const ColumnaTabla('', ancho: 124, derecha: true),
      ],
      cabeceraPrimera: Casilla(
        valor: todosMarcados,
        etiqueta: 'Seleccionar todos',
        onCambio: (_) {
          for (final x in productos) {
            if (todosMarcados || !c.seleccionMasiva.contains(x.id)) c.alternarSeleccionMasiva(x.id);
          }
        },
      ),
      cantidad: productos.length,
      vacio: Vacio(texto: c.soloStockBajo ? 'Nada con stock bajo acá' : 'No hay productos acá', icono: null, padding: const EdgeInsets.symmetric(vertical: 36)),
      onTapFila: (i) => editar(productos[i]),
      celdas: (context, i) {
        final x = productos[i];
        final vendido = c.vendidoUltimos30[x.id] ?? 0;
        final dias = diasQueAlcanza(stock: x.stock, vendido30Dias: vendido);
        final gan = x.gananciaBp == null ? null : (x.gananciaBp! / 100).round();
        return [
          Casilla(valor: c.seleccionMasiva.contains(x.id), etiqueta: 'Seleccionar ${x.nombre}', onCambio: (_) => c.alternarSeleccionMasiva(x.id)),
          Row(
            children: [
              Flexible(child: celda(context, x.nombre, peso: 500)),
              if (x.esPesable) ...[const SizedBox(width: 8), const Etiqueta('pesable', alto: 26, tamanioTexto: 12.5, padding: 10)],
            ],
          ),
          if (!angosto) celda(context, x.codigoBarras ?? '—', num: true, color: p.mute, tamanio: 13.5),
          x.costoCentavos == null
              ? const _Ajustar(Etiqueta('Sin costo', tono: TonoMock.w))
              : celda(context, pesos(x.costoCentavos!), num: true, color: p.mute),
          x.precioCentavos == null
              ? const _Ajustar(Etiqueta('Sin precio', tono: TonoMock.w))
              : celda(context, '${pesos(x.precioCentavos!)}${x.esPesable ? '/kg' : ''}', num: true, peso: 600),
          gan == null ? celda(context, '—', color: p.mute) : _Ajustar(Etiqueta('$gan % gan.', tono: _tonoGanancia(gan))),
          celda(context, _cantidad(x, vendido), num: true, color: p.mute),
          x.stock <= 0
              ? const _Ajustar(Etiqueta('Sin stock', tono: TonoMock.b))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (c.avisaStock(x))
                      Etiqueta(_cantidad(x, x.stock), tono: TonoMock.w, alto: 26)
                    else
                      celda(context, _cantidad(x, x.stock), num: true),
                    if (dias != null)
                      Text('alcanza $dias d', style: estilo(12, 400, color: dias < 5 ? p.w : p.soft)),
                  ],
                ),
          Btn('Editar', tam: TamBtn.xs, variante: VarBtn.ton, sobreGris: true, etiqueta: 'Editar ${x.nombre}', onTap: () => editar(x)),
        ];
      },
    );
  }
}

/// Una etiqueta en una columna angosta (ventana de 1366): se achica entera antes que cortarse.
class _Ajustar extends StatelessWidget {
  const _Ajustar(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: child);
}
