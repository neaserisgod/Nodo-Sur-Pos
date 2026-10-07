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
import 'package:http/http.dart' as http;

import '../../data/database.dart';
import '../../data/normalizacion_texto.dart';
import '../../data/repositorio_promos.dart';
import '../../data/repositorio_sugerencia_promos.dart';
import '../../domain/dinero.dart';
import '../../domain/promo.dart' show atajosPorcentajePromo, porcentajePromoPorDefectoBp, textoPorcentajeBp;
import '../../servicios/asistente_promos.dart';
import '../../servicios/gemini.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/presionable.dart';
import '../tema/tema.dart' show radioControlEscritorio;
import '../tema/tokens.dart';
import 'selector_porcentaje.dart' show pedirOtroPorcentaje;

const _atajosPorcentaje = atajosPorcentajePromo;

String _pct(int bp) => textoPorcentajeBp(bp);

Future<void> mostrarDialogoPromos(
  BuildContext context, {
  required AppDatabase db,
  required int usuarioId,
  http.Client? clienteIa,
}) {
  return mostrarModal<void>(
    context,
    builder: (_) =>
        _DialogoPromos(db: db, usuarioId: usuarioId, clienteIa: clienteIa),
  );
}

/// Lo que el dueño eligió crear de las sugerencias: la sugerencia, el nombre con que se muestra (el de la IA, o el simple) y el
/// porcentaje de ganancia que dejó elegido.
typedef _SugerenciaElegida = ({SugerenciaDePromo sugerencia, String nombre, int bp});

// ─── Lista de promos ─────────────────────────────────────────────────────

class _DialogoPromos extends StatefulWidget {
  const _DialogoPromos({
    required this.db,
    required this.usuarioId,
    this.clienteIa,
  });

  final AppDatabase db;
  final int usuarioId;
  final http.Client? clienteIa;

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

  Future<void> _abrirCreador([
    PromoConComponentes? existente,
    _SugerenciaElegida? sugerida,
  ]) async {
    final guardo = await mostrarModal<bool>(
      context,
      builder: (_) => _DialogoCrearPromo(
        db: widget.db,
        usuarioId: widget.usuarioId,
        existente: existente,
        sugerida: sugerida,
      ),
    );
    if (guardo == true) await _recargar();
  }

  Future<void> _abrirSugerencias() async {
    final elegida = await mostrarModal<_SugerenciaElegida>(
      context,
      builder: (_) =>
          _DialogoSugerencias(db: widget.db, clienteIa: widget.clienteIa),
    );
    if (elegida != null && mounted) await _abrirCreador(null, elegida);
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
        BotonSecundario(texto: 'Sugerir promos', onPressed: _abrirSugerencias),
        BotonPrimario(texto: 'Nueva promo', onPressed: () => _abrirCreador()),
      ],
    );
  }
}

// ─── Sugerencias ─────────────────────────────────────────────────────────

/// Los pares de artículos que más se llevan juntos (`sugerirPromos`), con el precio ya calculado. Si hay clave de Gemini, la IA
/// les pone nombre y motivo; si no, o si falla, se ven igual con "A + B".
class _DialogoSugerencias extends StatefulWidget {
  const _DialogoSugerencias({required this.db, this.clienteIa});

  final AppDatabase db;
  final http.Client? clienteIa;

  @override
  State<_DialogoSugerencias> createState() => _DialogoSugerenciasState();
}

class _DialogoSugerenciasState extends State<_DialogoSugerencias> {
  List<SugerenciaDePromo>? _sugerencias;
  List<TextoDePromo?> _textos = const [];
  bool _redactando = false;
  String? _avisoIa;

  /// El porcentaje elegido por sugerencia (por posición); sin elegir, el de partida de la sugerencia.
  final Map<int, int> _bpElegido = {};

  int _bpDe(int i) => _bpElegido[i] ?? _sugerencias![i].porcentajeBp;

  Future<void> _otroPorcentaje(int i) async {
    final bp = await pedirOtroPorcentaje(context, actualBp: _bpDe(i));
    if (bp != null) setState(() => _bpElegido[i] = bp);
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final sugerencias = await sugerirPromos(widget.db);
    if (!mounted) return;
    setState(() => _sugerencias = sugerencias);
    if (sugerencias.isNotEmpty) await _redactar(sugerencias);
  }

  Future<void> _redactar(List<SugerenciaDePromo> sugerencias) async {
    if (!ClaveGemini.configurada) {
      setState(
        () => _avisoIa =
            'Cargá la clave de la IA en Configuración › Asistente IA para que les ponga nombre.',
      );
      return;
    }
    setState(() => _redactando = true);
    final cliente = ClienteGemini.guardado(client: widget.clienteIa);
    try {
      final textos = await redactarPromos(cliente, sugerencias);
      if (mounted) setState(() => _textos = textos);
    } on ErrorGemini catch (e) {
      if (mounted) {
        setState(() => _avisoIa = 'La IA no pudo ponerles nombre: ${e.mensaje}');
      }
    } finally {
      cliente.close();
      if (mounted) setState(() => _redactando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sugerencias = _sugerencias;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;

    return Modal(
      titulo: 'Promos sugeridas',
      subtitulo:
          'Artículos que tus clientes ya se llevan juntos (últimos 90 días). Vos decidís cuáles crear.',
      ancho: 720,
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: sugerencias == null
            ? const Center(child: CircularProgressIndicator())
            : sugerencias.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: Espaciado.lg),
                child: Text(
                  'Todavía no hay nada para sugerir: hacen falta artículos que se vendan juntos al menos 2 veces, con stock, '
                  'con costo cargado y con ganancia suficiente para descontar.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colores.textoSecundario,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_redactando)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espaciado.sm),
                      child: Text(
                        'Poniéndoles nombre con la IA…',
                        style: textTheme.bodySmall?.copyWith(
                          color: colores.textoSecundario,
                        ),
                      ),
                    ),
                  if (_avisoIa != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espaciado.sm),
                      child: Text(
                        _avisoIa!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colores.textoSecundario,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sugerencias.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Espaciado.sm),
                      itemBuilder: (_, i) {
                        final s = sugerencias[i];
                        final texto = i < _textos.length ? _textos[i] : null;
                        final nombre = texto?.nombre ?? s.nombreSimple;
                        final bp = _bpDe(i);
                        final calculo = calcularPromo(s.componentes, bp);
                        final cubreElCosto = calculo?.cubreElCosto ?? false;
                        final esAtajo = _atajosPorcentaje.contains(bp);
                        return Container(
                          padding: const EdgeInsets.all(Espaciado.md),
                          decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(radioControlEscritorio)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(nombre, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte)),
                                    if (texto != null) Text(s.nombreSimple, style: textTheme.bodySmall),
                                    // El dato real va siempre: la frase de la IA es un agregado, no lo reemplaza.
                                    Text(
                                      'Se llevaron juntos en ${s.par.ventasJuntos} ventas '
                                      '(uno se vendió en ${s.par.ventasA} y el otro en ${s.par.ventasB}).',
                                      style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
                                    ),
                                    if (texto != null && texto.motivo.isNotEmpty)
                                      Text('IA: ${texto.motivo}', style: textTheme.bodySmall?.copyWith(color: colores.textoTenue)),
                                    const SizedBox(height: Espaciado.sm),
                                    Wrap(
                                      spacing: Espaciado.md,
                                      runSpacing: Espaciado.sm,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        GrupoPildoras<int>(
                                          opciones: [
                                            for (final a in _atajosPorcentaje) (a, _pct(a)),
                                            if (!esAtajo) (bp, _pct(bp)),
                                          ],
                                          elegida: bp,
                                          onElegir: (v) => setState(() => _bpElegido[i] = v),
                                        ),
                                        TextButton(onPressed: () => _otroPorcentaje(i), child: const Text('Otro %')),
                                      ],
                                    ),
                                    const SizedBox(height: Espaciado.xs),
                                    if (calculo == null)
                                      Text('Falta el costo o el precio de algún artículo.', style: textTheme.bodySmall)
                                    else ...[
                                      Text(
                                        'Sueltos ${formatearARS(calculo.listaCentavos)} · promo ${formatearARS(calculo.precioCentavos)} '
                                        '(el cliente ahorra ${formatearARS(calculo.listaCentavos - calculo.precioCentavos)}) · '
                                        'te quedan ${formatearARS(calculo.precioCentavos - calculo.costoCentavos)} por promo',
                                        style: textTheme.bodySmall,
                                      ),
                                      if (calculo.topeadoPorLista)
                                        Text(
                                          'Con ese porcentaje no baja del precio de lista: no hay descuento para el cliente.',
                                          style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
                                        ),
                                      if (!cubreElCosto)
                                        Text('Con ese porcentaje la promo no cubre su costo.', style: textTheme.bodySmall?.copyWith(color: colores.error)),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: Espaciado.sm),
                              TextButton(
                                onPressed: cubreElCosto
                                    ? () => Navigator.of(context).pop<_SugerenciaElegida>((sugerencia: s, nombre: nombre, bp: bp))
                                    : null,
                                child: const Text('Crear'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      botones: [
        BotonSecundario(
          texto: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
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
    this.sugerida,
  });

  final AppDatabase db;
  final int usuarioId;
  final PromoConComponentes? existente;

  /// Una sugerencia que se quiere crear: llega con los artículos, el nombre y el porcentaje ya puestos, todo editable.
  final _SugerenciaElegida? sugerida;

  @override
  State<_DialogoCrearPromo> createState() => _DialogoCrearPromoState();
}

class _DialogoCrearPromoState extends State<_DialogoCrearPromo> {
  late final _nombreCtrl = TextEditingController(
    text: widget.existente?.promo.nombre ?? widget.sugerida?.nombre ?? '',
  );
  final _busquedaCtrl = TextEditingController();
  late final List<_Elegido> _elegidos = [
    for (final c
        in widget.existente?.componentes ??
            widget.sugerida?.sugerencia.componentes ??
            const <ComponenteDePromo>[])
      _Elegido(c.producto, c.cantidad),
  ];
  List<Producto> _elegibles = const [];
  late int _bp = widget.sugerida?.bp ?? porcentajePromoPorDefectoBp;
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

  /// Solo lo que puede entrar en una promo (`productosParaPromo`, la misma regla que el celular).
  Future<void> _cargarElegibles() async {
    final elegibles = await productosParaPromo(widget.db);
    if (mounted) setState(() => _elegibles = elegibles);
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
        gananciaBp: _bp,
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
                'Ganancia sobre el precio',
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
              Insignia(texto: '${_pct(bp)} de ganancia, a la centena'),
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
