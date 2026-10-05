// Pantalla de conteo físico: recorrer la góndola por proveedor y corregir
// el stock, agotados/negativos primero (Regla 8).
//
// "Lenguaje de diseño" (mock `ConteoStock`): resumen arriba (cuánto se
// contó, cuántos con diferencia, cuánto falta y a qué costo), filtros, y
// una tabla con lo que dice el sistema, lo contado (−/+ o tipeado) y la
// diferencia en el momento. Nada toca la base hasta "Aplicar ajustes".

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart';
import '../../domain/dinero.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/tarjetas.dart';
import '../navegacion/busqueda_contextual.dart';
import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import 'stock_proveedor_controlador.dart';
import '../tema/esqueleto.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(n == 1 ? 'Se ajustó 1 producto' : 'Se ajustaron $n productos')),
    );
  }

  Future<void> _bajarPlanilla() async {
    final ubicacion = await getSaveLocation(
      suggestedName: 'conteo-de-stock.csv',
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (ubicacion == null) return;
    await File(ubicacion.path).writeAsString(Csv.excel().encode(_c.filasPlanilla()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilla guardada')));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StockProveedorControlador>.value(
      value: _c,
      child: Consumer<StockProveedorControlador>(
        builder: (context, c, _) => PantallaGestion(
          db: widget.db,
          claveActiva: 'proveedores',
          usuarioId: widget.usuarioId,
          titulo: 'Conteo de stock',
          busqueda: BusquedaContextual(pista: 'Buscar o escanear producto', alCambiar: c.buscar),
          child: c.cargando ? const EsqueletoLista() : _contenido(context, c),
        ),
      ),
    );
  }

  Widget _contenido(BuildContext context, StockProveedorControlador c) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final conDif = c.conDiferencia;
    final visibles = c.visibles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ActionChip(
              avatar: const IconoPlz(IconosPlazoleta.arrowBackRounded, size: 18),
              label: const Text('Proveedores'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Espaciado.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contá lo que hay en góndola y depósito. Nada cambia hasta que apliques los ajustes.',
                    style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
                  ),
                ],
              ),
            ),
            BotonSecundario(texto: 'Bajar planilla', onPressed: _bajarPlanilla),
            const SizedBox(width: Espaciado.sm),
            BotonPrimario(
              texto: conDif.isEmpty ? 'Aplicar ajustes' : 'Aplicar ajustes (${conDif.length})',
              onPressed: conDif.isEmpty || c.aplicando ? null : _aplicar,
            ),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        SizedBox(
          height: 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 14, child: _TarjetaAvance(contados: c.cantidadContados, total: c.productos.length)),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: TarjetaIndicador(
                  etiqueta: 'Con diferencia',
                  valor: '${conDif.length}',
                  tonoValor: conDif.isEmpty ? null : Tono.alerta,
                  nota: conDif.isEmpty ? 'Todo coincide' : conDif.map((p) => p.nombre).take(3).join(', '),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: TarjetaIndicador(
                  etiqueta: 'Sobran / faltan',
                  valor: _signado(c.unidadesSobrantes - c.unidadesFaltantes, ' u.'),
                  tonoValor: c.unidadesFaltantes > 0 ? Tono.error : null,
                  nota: 'Faltan ${c.unidadesFaltantes} · sobran ${c.unidadesSobrantes}',
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: TarjetaIndicador(
                  etiqueta: 'Costo de lo que falta',
                  valor: formatearARS(c.costoFaltanteCentavos),
                  nota: 'A precio de costo',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.lg),
        Wrap(
          spacing: Espaciado.sm,
          runSpacing: Espaciado.sm,
          children: [
            ChipAtajo(texto: 'Todos ${c.productos.length}', elegido: c.filtro == FiltroConteo.todos, onTap: () => c.elegirFiltro(FiltroConteo.todos)),
            ChipAtajo(
              texto: 'Sin contar ${c.cantidadSinContar}',
              elegido: c.filtro == FiltroConteo.sinContar,
              onTap: () => c.elegirFiltro(FiltroConteo.sinContar),
            ),
            ChipAtajo(
              texto: 'Con diferencia ${conDif.length}',
              elegido: c.filtro == FiltroConteo.conDiferencia,
              onTap: () => c.elegirFiltro(FiltroConteo.conDiferencia),
            ),
            _Desplegable<int?>(
              clave: const Key('filtro_proveedor'),
              texto: 'Proveedor: ${c.proveedores.where((p) => p.id == c.proveedorIdFiltro).firstOrNull?.nombre ?? 'todos'}',
              opciones: [(null, 'Todos'), for (final p in c.proveedores) (p.id, p.nombre)],
              onElegir: c.filtrarPorProveedor,
            ),
            _Desplegable<String>(
              clave: const Key('filtro_motivo'),
              texto: 'Motivo: ${c.motivo}',
              opciones: [for (final m in motivosAjusteDeStock) (m, m)],
              onElegir: c.elegirMotivo,
            ),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: Superficie(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
                  child: DefaultTextStyle.merge(
                    style: textTheme.labelMedium?.copyWith(color: colores.textoSecundario),
                    child: const Row(
                      children: [
                        Expanded(child: Text('Producto')),
                        SizedBox(width: _anchoSistema, child: Text('En el sistema')),
                        SizedBox(width: _anchoContado, child: Text('Contado')),
                        SizedBox(width: _anchoDiferencia, child: Text('Diferencia')),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: visibles.isEmpty
                      ? Center(child: Text('No hay productos con este filtro.', style: textTheme.bodyMedium))
                      : ListView.builder(
                          itemCount: visibles.length,
                          itemBuilder: (context, i) => _FilaConteo(key: ValueKey(visibles[i].id), c: c, producto: visibles[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _signado(int n, String unidad) => n == 0 ? '0$unidad' : (n > 0 ? '+$n$unidad' : '−${-n}$unidad');

const double _anchoSistema = 130;
const double _anchoContado = 230;
const double _anchoDiferencia = 130;

class _TarjetaAvance extends StatelessWidget {
  const _TarjetaAvance({required this.contados, required this.total});

  final int contados;
  final int total;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final sobre = acentos.textoSobreColor;
    return Superficie(
      degrade: acentos.gradienteAcento,
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(child: Text('Contados', style: textTheme.labelLarge?.copyWith(color: sobre.withValues(alpha: 0.75)))),
              Text('$contados de $total', style: textTheme.headlineSmall?.copyWith(color: sobre, fontWeight: Pesos.fuerte).tabular),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: total == 0 ? 0 : contados / total,
              backgroundColor: sobre.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(context.colores.acento.withValues(alpha: 0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Desplegable<T> extends StatelessWidget {
  const _Desplegable({required this.clave, required this.texto, required this.opciones, required this.onElegir});

  final Key clave;
  final String texto;
  final List<(T, String)> opciones;
  final ValueChanged<T> onElegir;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return PopupMenuButton<T>(
      key: clave,
      tooltip: '',
      onSelected: onElegir,
      itemBuilder: (context) => [for (final (valor, etiqueta) in opciones) PopupMenuItem(value: valor, child: Text(etiqueta))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm + 2),
        decoration: BoxDecoration(
          color: colores.fondoBloque,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colores.borde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: Espaciado.xs),
            const IconoPlz(IconosPlazoleta.expandMore, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FilaConteo extends StatelessWidget {
  const _FilaConteo({super.key, required this.c, required this.producto});

  final StockProveedorControlador c;
  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final dif = c.diferencia(producto);
    final unidad = producto.esPesable ? ' g' : '';
    final agotado = productoAgotado(producto);
    final insignia = switch (dif) {
      null => const Insignia(texto: 'Sin contar'),
      0 => const Insignia(texto: 'Justo', tono: Tono.ganancia),
      final d => Insignia(texto: _signado(d, unidad), tono: d < 0 ? Tono.error : Tono.acento),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: Espaciado.sm),
      decoration: BoxDecoration(
        color: (dif ?? 0) != 0 ? acentos.alertaSuave : colores.fondo,
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte, color: agotado ? colores.error : null),
                ),
                Text(c.nombreProveedor(producto), style: textTheme.bodySmall),
              ],
            ),
          ),
          SizedBox(
            width: _anchoSistema,
            child: Text('${c.sistema(producto)}$unidad', style: textTheme.titleMedium?.tabular),
          ),
          SizedBox(
            width: _anchoContado,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 44,
                decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'Restar', icon: const IconoPlz(IconosPlazoleta.remove), onPressed: () => c.sumar(producto, -1)),
                    SizedBox(width: 96, child: _CampoContado(c: c, producto: producto)),
                    IconButton(tooltip: 'Sumar', icon: const IconoPlz(IconosPlazoleta.add), onPressed: () => c.sumar(producto, 1)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: _anchoDiferencia, child: Align(alignment: Alignment.centerLeft, child: insignia)),
        ],
      ),
    );
  }
}

/// El número del medio del stepper, tipeable. Sigue al controlador cuando
/// cambia por "−"/"+", sin pisar lo que se esté escribiendo.
class _CampoContado extends StatefulWidget {
  const _CampoContado({required this.c, required this.producto});

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
    return TextField(
      controller: _ctrl,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
      decoration: const InputDecoration(
        hintText: '—',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isCollapsed: true,
      ),
      onChanged: (v) => widget.c.contar(widget.producto, int.tryParse(v.trim())),
    );
  }
}
