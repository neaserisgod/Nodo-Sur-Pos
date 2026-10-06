// Pantalla de conteo físico: recorrer la góndola por proveedor y corregir
// el stock, agotados/negativos primero (Regla 8).
//
// "Lenguaje de diseño" (mock `ConteoStock`): resumen arriba (cuánto se
// contó, cuántos con diferencia, cuánto falta y a qué costo), filtros, y
// una tabla con lo que dice el sistema, lo contado (−/+ o tipeado) y la
// diferencia en el momento. Nada toca la base hasta "Aplicar ajustes".

// Rediseño v4 (2026-10-06), desde cero como el mock (`SCR.conteo`): cuatro bloques (contados, con diferencia, lo que
// falta a costo, "marcar todo igual"), los filtros con el buscador, la tabla (dice el sistema / contado / diferencia) y
// "Aplicar ajustes" abajo a la derecha.

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart';
import '../comun/armazon_gestion.dart';
import '../comun/aviso_superior.dart';
import '../kit/kit.dart';
import 'stock_proveedor_controlador.dart';

class PantallaStockProveedor extends StatefulWidget {
  const PantallaStockProveedor({super.key, required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<PantallaStockProveedor> createState() => _PantallaStockProveedorState();
}

class _PantallaStockProveedorState extends State<PantallaStockProveedor> {
  late final StockProveedorControlador _c;

  @override
  void initState() {
    super.initState();
    _c = StockProveedorControlador(widget.db, usuarioId: widget.usuarioId);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _aplicar() async {
    final n = await _c.aplicarAjustes();
    if (!mounted || n == 0) return;
    mostrarAviso(context, n == 1 ? 'Se ajustó 1 producto' : 'Se ajustaron $n productos');
  }

  Future<void> _bajarPlanilla() async {
    final ubicacion = await getSaveLocation(
      suggestedName: 'conteo-de-stock.csv',
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (ubicacion == null) return;
    await File(ubicacion.path).writeAsString(Csv.excel().encode(_c.filasPlanilla()));
    if (!mounted) return;
    mostrarAviso(context, 'Planilla guardada');
  }

  /// "Marcar todo igual": lo que se ve y todavía no se contó queda contado con lo que dice el sistema.
  void _marcarIgual() {
    for (final p in _c.visibles) {
      if (_c.contado(p) == null) _c.contar(p, _c.sistema(p));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StockProveedorControlador>.value(
      value: _c,
      child: Consumer<StockProveedorControlador>(
        builder: (context, c, _) {
          final proveedor = c.proveedores.where((p) => p.id == c.proveedorIdFiltro).firstOrNull;
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'proveedores',
            usuarioId: widget.usuarioId,
            titulo: proveedor == null ? 'Contar stock' : 'Contar stock · ${proveedor.nombre}',
            subtitulo: 'Recorré la góndola y corregí el stock. Nada cambia hasta que apliques los ajustes.',
            acciones: [
              Btn('Bajar planilla', variante: VarBtn.ton, icono: Ic.down, onTap: _bajarPlanilla),
              Btn('Volver', variante: VarBtn.ton, icono: Ic.back, onTap: () => Navigator.of(context).maybePop()),
            ],
            child: c.cargando ? const SizedBox.shrink() : _contenido(context, c),
          );
        },
      ),
    );
  }

  Widget _contenido(BuildContext context, StockProveedorControlador c) {
    final p = context.p;
    final conDif = c.conDiferencia;
    final visibles = c.visibles;
    final ancho = MediaQuery.sizeOf(context).width;

    Widget bloque(String titulo, Widget valor, {TonoMock? tono, int orden = 0}) => Expanded(
      child: Aparecer.revelar(
        orden: orden,
        child: Tarjeta(
          tono: tono,
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: estilo(15, 600, color: tono == null ? p.mute : tono.colores(p).$2)),
              const SizedBox(height: 6),
              valor,
            ],
          ),
        ),
      ),
    );
    final fig = estilo(36, 550, color: p.tinta, em: -.04, num: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bloque('Contados', Text('${c.cantidadContados} / ${c.productos.length}', style: fig)),
              const SizedBox(width: 14),
              bloque(
                'Con diferencia',
                Text('${conDif.length}', style: fig.copyWith(color: (conDif.isEmpty ? TonoMock.g : TonoMock.w).colores(p).$2)),
                tono: conDif.isEmpty ? TonoMock.g : TonoMock.w,
                orden: 1,
              ),
              const SizedBox(width: 14),
              bloque('Falta, a costo', NumeroQueCuenta(valor: c.costoFaltanteCentavos, formato: pesos, estilo: fig), orden: 2),
              const SizedBox(width: 14),
              bloque(
                'Tilde “está igual”',
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Btn('Marcar todo igual', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, onTap: c.cantidadSinContar == 0 ? null : _marcarIgual),
                ),
                orden: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChipMock('Todos ${c.productos.length}', elegido: c.filtro == FiltroConteo.todos, onTap: () => c.elegirFiltro(FiltroConteo.todos)),
                    const SizedBox(width: 8),
                    ChipMock('Sin contar ${c.cantidadSinContar}', elegido: c.filtro == FiltroConteo.sinContar, onTap: () => c.elegirFiltro(FiltroConteo.sinContar)),
                    const SizedBox(width: 8),
                    ChipMock('Con diferencia ${conDif.length}', elegido: c.filtro == FiltroConteo.conDiferencia, onTap: () => c.elegirFiltro(FiltroConteo.conDiferencia)),
                    Container(width: 1, height: 26, color: p.linea, margin: const EdgeInsets.symmetric(horizontal: 14)),
                    _Desplegable<int?>(
                      clave: const Key('filtro_proveedor'),
                      texto: 'Proveedor: ${c.proveedores.where((x) => x.id == c.proveedorIdFiltro).firstOrNull?.nombre ?? 'todos'}',
                      opciones: [(null, 'Todos'), for (final x in c.proveedores) (x.id, x.nombre)],
                      onElegir: c.filtrarPorProveedor,
                    ),
                    const SizedBox(width: 8),
                    _Desplegable<String>(
                      clave: const Key('filtro_motivo'),
                      texto: 'Motivo: ${c.motivo}',
                      opciones: [for (final m in motivosAjusteDeStock) (m, m)],
                      onElegir: c.elegirMotivo,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: ancho >= 1700 ? 420 : 300,
              child: BuscadorPagina(campoKey: const Key('busqueda_contextual'), alto: 52, pista: 'Buscar o escanear producto', onCambio: c.buscar),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: Tabla(
                  radio: 28,
                  columnas: const [
                    ColumnaTabla('Producto', flex: 5),
                    ColumnaTabla('Dice el sistema', flex: 2, derecha: true),
                    ColumnaTabla('Contado', ancho: 220, derecha: true),
                    ColumnaTabla('Diferencia', ancho: 170, derecha: true),
                  ],
                  cantidad: visibles.length,
                  vacio: const Vacio(texto: 'No hay productos con este filtro.', icono: null, padding: EdgeInsets.symmetric(vertical: 36)),
                  celdas: (context, i) => _celdas(context, c, visibles[i]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: Btn(
            conDif.isEmpty ? 'Aplicar ajustes' : 'Aplicar ajustes (${conDif.length})',
            variante: VarBtn.blue,
            tam: TamBtn.lg,
            onTap: conDif.isEmpty || c.aplicando ? null : _aplicar,
          ),
        ),
      ],
    );
  }

  List<Widget> _celdas(BuildContext context, StockProveedorControlador c, Producto producto) {
    final p = context.p;
    final dif = c.diferencia(producto);
    final unidad = producto.esPesable ? ' g' : ' u.';
    final agotado = productoAgotado(producto);
    return [
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin stock en rojo (Regla 8): es lo primero que hay que mirar en la góndola.
          Text(producto.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(16, 500, color: agotado ? p.b : p.tinta)),
          Text(
            [producto.codigoBarras ?? 'sin código', c.nombreProveedor(producto)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estilo(13, 400, color: p.mute),
          ),
        ],
      ),
      celda(context, '${c.sistema(producto)}$unidad', num: true, color: p.mute),
      Container(
        key: ValueKey('contado_${producto.id}'),
        height: 42,
        decoration: BoxDecoration(color: p.papel, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Paso(icono: Ic.minus, etiqueta: 'Restar', onTap: () => c.sumar(producto, -1)),
            SizedBox(width: 80, child: _CampoContado(key: ValueKey(producto.id), c: c, producto: producto)),
            _Paso(icono: Ic.plus, etiqueta: 'Sumar', onTap: () => c.sumar(producto, 1)),
          ],
        ),
      ),
      switch (dif) {
        null => const Etiqueta('Sin contar'),
        0 => const Etiqueta('igual', tono: TonoMock.g),
        final d => Etiqueta(_signado(d, producto.esPesable ? ' g' : ''), tono: d < 0 ? TonoMock.b : TonoMock.w),
      },
    ];
  }
}

String _signado(int n, String unidad) => n == 0 ? '0$unidad' : (n > 0 ? '+$n$unidad' : '−${-n}$unidad');

class _Paso extends StatelessWidget {
  const _Paso({required this.icono, required this.etiqueta, required this.onTap});
  final Ic icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: etiqueta,
    child: Tocable(
      onTap: onTap,
      radio: 999,
      etiqueta: etiqueta,
      child: SizedBox(width: 40, height: 42, child: Center(child: Icono(icono, size: 14, grosor: 2.6, color: context.p.tinta))),
    ),
  );
}

/// Un chip con un menú: proveedor o motivo del ajuste.
class _Desplegable<T> extends StatelessWidget {
  const _Desplegable({required this.clave, required this.texto, required this.opciones, required this.onElegir});

  final Key clave;
  final String texto;
  final List<(T, String)> opciones;
  final ValueChanged<T> onElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return PopupMenuButton<T>(
      key: clave,
      tooltip: '',
      onSelected: onElegir,
      color: p.papel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      itemBuilder: (context) => [
        for (final (valor, etiqueta) in opciones) PopupMenuItem(value: valor, child: Text(etiqueta, style: estilo(15, 500, color: p.tinta))),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: p.papel, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.linea)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, style: estilo(15, 500, color: p.tinta)),
            const SizedBox(width: 6),
            Icono(Ic.chevd, size: 16, color: p.mute),
          ],
        ),
      ),
    );
  }
}

class _CampoContado extends StatefulWidget {
  const _CampoContado({super.key, required this.c, required this.producto});

  final StockProveedorControlador c;
  final Producto producto;

  @override
  State<_CampoContado> createState() => _CampoContadoState();
}

class _CampoContadoState extends State<_CampoContado> {
  late final _ctrl = TextEditingController(text: _texto);

  String get _texto => widget.c.contado(widget.producto)?.toString() ?? '';

  @override
  void didUpdateWidget(covariant _CampoContado old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_ctrl.text) != widget.c.contado(widget.producto)) {
      _ctrl.value = TextEditingValue(text: _texto, selection: TextSelection.collapsed(offset: _texto.length));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final e = estilo(16, 600, color: p.tinta, num: true);
    return AreaMinimaToque(
      child: TextField(
        controller: _ctrl,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: e,
        cursorColor: p.azul,
        decoration: decoracionSinBorde('—', e.copyWith(color: p.mute)),
        onChanged: (v) => widget.c.contar(widget.producto, int.tryParse(v.trim())),
      ),
    );
  }
}
