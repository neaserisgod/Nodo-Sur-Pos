// Creador de promos (El dueño, 2026-09-29): "se carga precio y costo de 2 o más
// artículos, se le suma el porcentaje, y no se tiene que pasar del precio de
// lista normal". Elegís los artículos (con su cantidad) y el porcentaje; el
// precio sale de la suma de los costos + el porcentaje, redondeado a la
// próxima centena, con tope en lo que costarían los artículos sueltos.
//
// La promo se vende como un producto más y al cobrarla descuenta el stock de
// cada artículo (`registrarPromoEnVenta`). Sin cigarrillos, pesables ni
// artículos sin costo.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/normalizacion_texto.dart';
import '../../data/repositorio_productos.dart' show listarProductos;
import '../../data/repositorio_promos.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/presionable.dart';
import '../tema/tema.dart' show radioControlEscritorio;
import '../tema/tokens.dart';
import 'selector_porcentaje.dart' show pedirOtroPorcentaje;

const _atajosPorcentaje = [2000, 3000, 4000, 5000, 7000, 10000];

String _pct(int bp) =>
    '${bp % 100 == 0 ? bp ~/ 100 : (bp / 100).toStringAsFixed(1)}%';

Future<void> mostrarDialogoPromos(
  BuildContext context, {
  required AppDatabase db,
  required int usuarioId,
}) {
  return mostrarModal<void>(
    context,
    builder: (_) => _DialogoPromos(db: db, usuarioId: usuarioId),
  );
}

// ─── Lista de promos ─────────────────────────────────────────────────────

class _DialogoPromos extends StatefulWidget {
  const _DialogoPromos({required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<_DialogoPromos> createState() => _DialogoPromosState();
}

class _DialogoPromosState extends State<_DialogoPromos> {
  List<PromoConComponentes>? _promos;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    final promos = await listarPromos(widget.db);
    if (mounted) setState(() => _promos = promos);
  }

  Future<void> _abrirCreador([PromoConComponentes? existente]) async {
    final guardo = await mostrarModal<bool>(
      context,
      builder: (_) => _DialogoCrearPromo(
        db: widget.db,
        usuarioId: widget.usuarioId,
        existente: existente,
      ),
    );
    if (guardo == true) await _recargar();
  }

  Future<void> _alternarActiva(PromoConComponentes p) async {
    await cambiarActivaPromo(
      widget.db,
      promoId: p.promo.id,
      activa: !p.promo.activo,
    );
    await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final promos = _promos;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;

    return Modal(
      titulo: 'Promos',
      subtitulo:
          'Se venden como un producto más y descuentan el stock de cada artículo',
      ancho: 720,
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: promos == null
            ? const Center(child: CircularProgressIndicator())
            : promos.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: Espaciado.lg),
                child: Text(
                  'Todavía no armaste ninguna. Con "Nueva promo" elegís dos o más artículos y el porcentaje.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colores.textoSecundario,
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: promos.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: Espaciado.sm),
                itemBuilder: (_, i) {
                  final p = promos[i];
                  final apagada = !p.promo.activo;
                  return Container(
                    padding: const EdgeInsets.all(Espaciado.md),
                    decoration: BoxDecoration(
                      color: colores.fondo,
                      borderRadius: BorderRadius.circular(
                        radioControlEscritorio,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: Espaciado.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    p.promo.nombre,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: Pesos.fuerte,
                                      color: apagada
                                          ? colores.textoTenue
                                          : colores.textoPrimario,
                                    ),
                                  ),
                                  if (apagada)
                                    const Insignia(texto: 'Desactivada'),
                                  if (p.pasaDeLista)
                                    const Insignia(
                                      texto: 'Pasa el precio de lista',
                                      tono: Tono.alerta,
                                    ),
                                ],
                              ),
                              Text(
                                p.componentes
                                    .map(
                                      (c) => c.cantidad > 1
                                          ? '${c.cantidad} × ${c.producto.nombre}'
                                          : c.producto.nombre,
                                    )
                                    .join(' + '),
                                style: textTheme.bodySmall,
                              ),
                              Text(
                                'Costo ${formatearARS(p.costoCentavos)} · sueltos ${formatearARS(p.listaCentavos)} · alcanzan ${p.stock}',
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatearARS(p.promo.precioCentavos ?? 0),
                          style: textTheme.titleMedium
                              ?.copyWith(
                                color: apagada ? colores.textoTenue : null,
                              )
                              .tabular,
                        ),
                        const SizedBox(width: Espaciado.sm),
                        TextButton(
                          onPressed: () => _abrirCreador(p),
                          child: const Text('Editar'),
                        ),
                        TextButton(
                          onPressed: () => _alternarActiva(p),
                          child: Text(apagada ? 'Activar' : 'Desactivar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      botones: [
        BotonSecundario(
          texto: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Nueva promo', onPressed: () => _abrirCreador()),
      ],
    );
  }
}

// ─── Creador ─────────────────────────────────────────────────────────────

class _Elegido {
  _Elegido(this.producto, this.cantidad);

  final Producto producto;
  int cantidad;
}

class _DialogoCrearPromo extends StatefulWidget {
  const _DialogoCrearPromo({
    required this.db,
    required this.usuarioId,
    required this.existente,
  });

  final AppDatabase db;
  final int usuarioId;
  final PromoConComponentes? existente;

  @override
  State<_DialogoCrearPromo> createState() => _DialogoCrearPromoState();
}

class _DialogoCrearPromoState extends State<_DialogoCrearPromo> {
  late final _nombreCtrl = TextEditingController(
    text: widget.existente?.promo.nombre ?? '',
  );
  final _busquedaCtrl = TextEditingController();
  late final List<_Elegido> _elegidos = [
    for (final c
        in widget.existente?.componentes ?? const <ComponenteDePromo>[])
      _Elegido(c.producto, c.cantidad),
  ];
  List<Producto> _elegibles = const [];
  int _bp = 3000;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarElegibles();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  /// Solo lo que puede entrar en una promo: por unidad, sin cigarrillos, con
  /// costo y precio cargados (`listarProductos` ya deja afuera "Varios" y las
  /// promos).
  Future<void> _cargarElegibles() async {
    final todos = await listarProductos(widget.db);
    if (!mounted) return;
    setState(() {
      _elegibles = [
        for (final p in todos)
          if (!p.esPesable &&
              p.tipoCigarrillo == 'ninguno' &&
              (p.costoCentavos ?? 0) > 0 &&
              p.precioCentavos != null)
            p,
      ];
    });
  }

  List<Producto> get _resultados {
    final texto = normalizarTexto(_busquedaCtrl.text);
    if (texto.isEmpty) return const [];
    final yaElegidos = _elegidos.map((e) => e.producto.id).toSet();
    return [
      for (final p in _elegibles)
        if (!yaElegidos.contains(p.id) &&
            normalizarTexto(p.nombre).contains(texto))
          p,
    ].take(6).toList();
  }

  PrecioDePromoCalculado? get _calculo => calcularPromo([
    for (final e in _elegidos)
      ComponenteDePromo(producto: e.producto, cantidad: e.cantidad),
  ], _bp);

  bool get _sePuedeGuardar {
    final c = _calculo;
    return _nombreCtrl.text.trim().isNotEmpty &&
        _elegidos.length >= 2 &&
        c != null &&
        c.cubreElCosto;
  }

  void _agregar(Producto p) {
    setState(() {
      _elegidos.add(_Elegido(p, 1));
      _busquedaCtrl.clear();
      _error = null;
    });
  }

  Future<void> _otroPorcentaje() async {
    final bp = await pedirOtroPorcentaje(context, actualBp: _bp);
    if (bp != null) setState(() => _bp = bp);
  }

  Future<void> _guardar() async {
    try {
      await guardarPromo(
        widget.db,
        promoId: widget.existente?.promo.id,
        nombre: _nombreCtrl.text,
        articulos: [
          for (final e in _elegidos)
            (productoId: e.producto.id, cantidad: e.cantidad),
        ],
        markupBp: _bp,
        usuarioId: widget.usuarioId,
      );
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final calculo = _calculo;
    final resultados = _resultados;
    final esAtajo = _atajosPorcentaje.contains(_bp);

    return Modal(
      titulo: widget.existente == null ? 'Nueva promo' : 'Editar promo',
      ancho: 720,
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CampoTexto(
                key: const Key('campo_nombre_promo'),
                controller: _nombreCtrl,
                etiqueta: 'Nombre de la promo',
                autofocus: widget.existente == null,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: Espaciado.lg),
              Text(
                'Artículos (al menos dos)',
                style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
              ),
              const SizedBox(height: Espaciado.sm),
              for (final e in _elegidos)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espaciado.xs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Espaciado.md,
                      vertical: Espaciado.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colores.fondo,
                      borderRadius: BorderRadius.circular(
                        radioControlEscritorio,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.producto.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'costo ${formatearARS(e.producto.costoCentavos!)} · lista ${formatearARS(e.producto.precioCentavos!)}',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(width: Espaciado.md),
                        IconButton(
                          tooltip: 'Menos',
                          visualDensity: VisualDensity.compact,
                          onPressed: e.cantidad > 1
                              ? () => setState(() => e.cantidad--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 24,
                          child: Center(
                            child: Text(
                              '${e.cantidad}',
                              style: textTheme.bodyMedium?.tabular,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Más',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => e.cantidad++),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Sacar',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _elegidos.remove(e)),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              CampoTexto(
                key: const Key('campo_buscar_articulo_promo'),
                controller: _busquedaCtrl,
                etiqueta: 'Agregar un artículo (escribí para buscar)',
                onChanged: (_) => setState(() {}),
              ),
              if (resultados.isNotEmpty) ...[
                const SizedBox(height: Espaciado.xs),
                for (final p in resultados)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Presionable(
                      radio: radioControlEscritorio,
                      color: colores.fondo,
                      onTap: () => _agregar(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Espaciado.md,
                          vertical: Espaciado.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              formatearARS(p.precioCentavos!),
                              style: textTheme.bodySmall?.tabular,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ] else if (_busquedaCtrl.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.xs),
                  child: Text(
                    'Sin coincidencias. Solo entran artículos por unidad, con costo y precio, y sin cigarrillos.',
                    style: textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: Espaciado.lg),
              Text(
                'Ganancia sobre el costo',
                style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
              ),
              const SizedBox(height: Espaciado.sm),
              Wrap(
                spacing: Espaciado.md,
                runSpacing: Espaciado.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GrupoPildoras<int>(
                    opciones: [
                      for (final a in _atajosPorcentaje) (a, _pct(a)),
                      if (!esAtajo) (_bp, _pct(_bp)),
                    ],
                    elegida: _bp,
                    onElegir: (bp) => setState(() => _bp = bp),
                  ),
                  BotonSecundario(texto: 'Otro %', onPressed: _otroPorcentaje),
                ],
              ),
              const SizedBox(height: Espaciado.lg),
              BloqueSuave(
                child: _Resumen(
                  calculo: calculo,
                  cantidadElegidos: _elegidos.length,
                  bp: _bp,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Espaciado.sm),
                Text(_error!, style: TextStyle(color: colores.error)),
              ],
            ],
          ),
        ),
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BotonPrimario(
          texto: 'Guardar promo',
          onPressed: _sePuedeGuardar ? _guardar : null,
        ),
      ],
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.calculo,
    required this.cantidadElegidos,
    required this.bp,
  });

  final PrecioDePromoCalculado? calculo;
  final int cantidadElegidos;
  final int bp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final c = calculo;

    if (cantidadElegidos < 2 || c == null) {
      return Text(
        cantidadElegidos < 2
            ? 'Elegí al menos dos artículos para ver el precio.'
            : 'Falta el costo o el precio de algún artículo.',
        style: textTheme.bodyMedium,
      );
    }

    Widget fila(String etiqueta, String valor, {bool fuerte = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(etiqueta, style: textTheme.bodyMedium)),
              Text(
                valor,
                style: (fuerte ? textTheme.titleLarge : textTheme.bodyMedium)
                    ?.copyWith(fontWeight: fuerte ? Pesos.fuerte : null)
                    .tabular,
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fila('Costo de los artículos', formatearARS(c.costoCentavos)),
        fila('Sueltos, a precio de lista', formatearARS(c.listaCentavos)),
        const Divider(),
        fila(
          'Precio de la promo',
          formatearARS(c.precioCentavos),
          fuerte: true,
        ),
        const SizedBox(height: Espaciado.xs),
        Wrap(
          spacing: Espaciado.sm,
          runSpacing: Espaciado.xs,
          children: [
            if (c.cubreElCosto)
              Insignia(
                texto:
                    'Ganás ${formatearARS(c.precioCentavos - c.costoCentavos)}',
                tono: Tono.ganancia,
              ),
            if (c.topeadoPorLista)
              const Insignia(
                texto: 'Tope: no pasa el precio de lista',
                tono: Tono.alerta,
              )
            else
              Insignia(texto: 'Costo + ${_pct(bp)}, a la centena'),
            if (c.listaCentavos > c.precioCentavos)
              Insignia(
                texto:
                    'Ahorra ${formatearARS(c.listaCentavos - c.precioCentavos)} al cliente',
              ),
          ],
        ),
        if (!c.cubreElCosto) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'El precio de lista de estos artículos no cubre su costo: la promo perdería plata.',
            style: TextStyle(color: colores.error),
          ),
        ],
      ],
    );
  }
}
