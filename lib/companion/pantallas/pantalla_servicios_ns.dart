// Servicios del celular (`docs/PLAN-SERVICIOS.md`, etapa 2; mock `docs/mock-servicios/NodoSurServicios.html`, "Servicios"):
// en un negocio de servicios (barbería, uñas) la pestaña Productos pasa a ser esta. Dos segmentos, Servicios e Insumos;
// el creador de servicio con el calculador (lo que cuesta, para cuántos alcanza, el precio para ganar lo buscado); alta de
// insumo, cargar compra por envases y contar.
//
// Trabaja sobre la base del celular, como Promos: todo viaja a los otros equipos por la sync. Solo en "Solo celular": con
// una PC, los servicios todavía no tienen pantallas ni rutas del lado de la PC (etapa "Después" del plan), así que se avisa
// en vez de mostrar datos que la PC no ve igual. Cobrar un servicio llega en la etapa 3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart' show configuracionNegocioActual, configurarValorHora;
import '../../data/repositorio_servicios.dart';
import '../../domain/dinero.dart' show formatearARS, parsearARS;
import '../../domain/ganancia.dart' show gananciaBpDesdeCostoYPrecio;
import '../../domain/modulos.dart';
import '../../domain/servicios.dart';
import '../../servicios/modulos_activos.dart';
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../modo_uso.dart';

/// Pesos escritos ("8.000", "8000,50") a centavos; null si está vacío o no es un monto.
int? _centavos(String texto) {
  if (texto.trim().isEmpty) return null;
  try {
    final c = parsearARS(texto);
    return c < 0 ? null : c;
  } on FormatException {
    return null;
  }
}

String _cantidad(int milesimas, UnidadInsumo unidad) => '${textoDeMilesimas(milesimas)} ${unidad.abreviatura}';

UnidadInsumo _unidadDe(Producto insumo) => UnidadInsumo.desdeClave(insumo.unidadInsumo) ?? UnidadInsumo.u;

/// Lo que suma o resta cada toque del − / + de la receta: una unidad entera, o una décima en ml y g (5 g si el envase es
/// grande, como un pote de 500 g de polvo).
int _paso(Producto insumo) => switch (_unidadDe(insumo)) {
      UnidadInsumo.u => milesimasPorUnidad,
      UnidadInsumo.g => (insumo.contenidoEnvaseMilesimas ?? 0) > 100 * milesimasPorUnidad ? 5 * milesimasPorUnidad : 100,
      UnidadInsumo.ml => 100,
    };

const _formatoPlata = [_SoloPlata()];

class _SoloPlata extends TextInputFormatter {
  const _SoloPlata();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      RegExp(r'^[0-9.,]*$').hasMatch(newValue.text) ? newValue : oldValue;
}

final _formatoCantidad = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

class PantallaServiciosNs extends StatefulWidget {
  /// [db], [usuarioId] y [soloCelular] son para tests (sin `AppNs` arriba).
  const PantallaServiciosNs({super.key, this.db, this.usuarioId, this.soloCelular});

  final AppDatabase? db;
  final int? usuarioId;
  final bool? soloCelular;

  @override
  State<PantallaServiciosNs> createState() => _PantallaServiciosNsState();
}

class _PantallaServiciosNsState extends State<PantallaServiciosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  int? _usuarioId;
  int _segmento = 0;
  List<ServicioConCosto>? _servicios;
  List<InsumoConCosto> _insumos = const [];
  Map<int, String> _categorias = const {};
  int? _valorHora;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    // Lo que llega por la sync (un insumo cargado en otro celular) se ve sin salir de la pantalla.
    _sub = avisosCambiosCompanion.listen((_) => _cargar());
    _cargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    final servicios = await listarServicios(_db);
    final insumos = await listarInsumos(_db);
    final categorias = {for (final c in await _db.select(_db.categorias).get()) c.id: c.nombre};
    final config = await configuracionNegocioActual(_db);
    if (!mounted) return;
    setState(() {
      _servicios = servicios;
      _insumos = insumos;
      _categorias = categorias;
      _valorHora = config.valorHoraCentavos;
    });
  }

  bool get _soloCelular {
    if (widget.soloCelular != null) return widget.soloCelular!;
    final app = context.dependOnInheritedWidgetOfExactType<AppNs>()?.controlador;
    return app?.modoUso == ModoUso.soloCelular;
  }

  Future<T?> _abrir<T>(WidgetBuilder builder) => Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));

  Future<void> _editarServicio([ServicioConCosto? existente]) async {
    final usuario = _usuarioId;
    if (usuario == null) return mostrarAvisoNs(context, 'Falta elegir usuario');
    final guardo = await _abrir<bool>((_) => PantallaEditorServicioNs(db: _db, usuarioId: usuario, existente: existente));
    if (guardo == true) {
      await _cargar();
      if (mounted) mostrarAvisoNs(context, existente == null ? 'Servicio creado' : 'Servicio guardado');
    }
  }

  Future<void> _editarInsumo([Producto? existente]) async {
    final usuario = _usuarioId;
    if (usuario == null) return mostrarAvisoNs(context, 'Falta elegir usuario');
    final guardo = await _abrir<bool>((_) => PantallaInsumoNs(db: _db, usuarioId: usuario, existente: existente));
    if (guardo == true) await _cargar();
  }

  Future<void> _compra([InsumoConCosto? insumo]) async {
    final usuario = _usuarioId;
    if (usuario == null) return mostrarAvisoNs(context, 'Falta elegir usuario');
    if (_insumos.isEmpty) return mostrarAvisoNs(context, 'Primero cargá un insumo');
    final elegido = insumo ?? _insumos.firstWhere((i) => i.stockBajo, orElse: () => _insumos.first);
    final hecho = await mostrarHojaNs<bool>(context, builder: (_) => _HojaCompra(db: _db, usuarioId: usuario, insumos: _insumos, inicial: elegido));
    if (hecho == true) {
      await _cargar();
      if (mounted) mostrarAvisoNs(context, 'Compra sumada al stock');
    }
  }

  Future<void> _contar(InsumoConCosto insumo) async {
    final usuario = _usuarioId;
    if (usuario == null) return mostrarAvisoNs(context, 'Falta elegir usuario');
    final hecho = await mostrarHojaNs<bool>(context, builder: (_) => _HojaContar(db: _db, usuarioId: usuario, insumo: insumo));
    if (hecho == true) await _cargar();
  }

  Future<void> _elegirParaContar() async {
    if (_insumos.isEmpty) return mostrarAvisoNs(context, 'Primero cargá un insumo');
    final elegido = await mostrarHojaNs<InsumoConCosto>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Contar',
        texto: 'Elegí qué insumo contaste.',
        bloques: [
          ListaAgrupadaNs(filas: [
            for (final i in _insumos)
              _Fila(titulo: i.insumo.nombre, subtitulo: 'Quedan ${_cantidad(i.stockMilesimas, i.unidad)}', onTap: () => Navigator.of(ctx).pop(i)),
          ]),
        ],
      ),
    );
    if (elegido != null && mounted) await _contar(elegido);
  }

  Future<void> _accionesInsumo(InsumoConCosto i) async {
    final accion = await mostrarHojaNs<String>(
      context,
      builder: (ctx) => HojaNs(
        titulo: i.insumo.nombre,
        texto: 'Quedan ${_cantidad(i.stockMilesimas, i.unidad)}'
            '${i.costoPorUnidadCentavos == null ? '' : ' · ${plataNs(i.costoPorUnidadCentavos!)} por ${i.unidad.abreviatura}'}',
        botones: [
          BotonNs.primario(ctx, 'Cargar compra', () => Navigator.of(ctx).pop('compra'), icono: IconoNs.masMas),
          BotonNs.secundario(ctx, 'Contar', () => Navigator.of(ctx).pop('contar'), icono: IconoNs.portapapeles),
          BotonNs.secundario(ctx, 'Editar', () => Navigator.of(ctx).pop('editar'), icono: IconoNs.editar),
          BotonNs.peligroSuave(ctx, 'Dejar de usarlo', () => Navigator.of(ctx).pop('baja')),
        ],
      ),
    );
    if (!mounted) return;
    switch (accion) {
      case 'compra':
        await _compra(i);
      case 'contar':
        await _contar(i);
      case 'editar':
        await _editarInsumo(i.insumo);
      case 'baja':
        await dejarDeOfrecer(_db, i.insumo.id);
        await _cargar();
    }
  }

  Future<void> _cambiarValorHora() async {
    final ctrl = TextEditingController(text: _valorHora == null ? '' : formatearARS(_valorHora!, conSigno: false));
    final valor = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Valor de la hora',
        texto: 'Lo que vale una hora de trabajo. Los servicios que suman mano de obra lo agregan a su costo según lo que duran.',
        bloques: [CampoNs(etiqueta: 'Por hora', controller: ctrl, teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _formatoPlata, autofoco: true)],
        botones: [BotonNs.primario(ctx, 'Guardar', () => Navigator.of(ctx).pop(_centavos(ctrl.text) ?? -1))],
      ),
    );
    if (valor == null) return;
    if (valor < 0) {
      if (mounted) mostrarAvisoNs(context, 'Monto inválido');
      return;
    }
    await configurarValorHora(_db, valor);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) {
        final conInsumos = modulos.estaActivo(Modulo.insumos);
        final segmento = conInsumos ? _segmento : 0;
        return PantallaEntradaNs(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
                  child: Row(
                    children: [
                      Expanded(child: Text('Servicios', style: tituloNs(42, track: -0.055, color: ns.ink))),
                      if (_soloCelular)
                        BotonNs(
                          texto: segmento == 0 ? '+ Nuevo' : '+ Insumo',
                          onTap: segmento == 0 ? () => _editarServicio() : () => _editarInsumo(),
                          alto: 44,
                          tamanio: 15,
                          fondo: ns.prim,
                          color: TokensNs.blanco,
                          rellenar: false,
                          paddingH: 20,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: !_soloCelular
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: margenNs),
                          child: InfoNs(
                            'Los servicios y sus insumos se manejan desde el celular en modo "Solo celular". Con la PC todavía no '
                            'están: llegan en una próxima versión.',
                          ),
                        )
                      : _servicios == null
                          ? const Padding(padding: EdgeInsets.symmetric(horizontal: margenNs), child: EsqueletoListaNs())
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado - 8),
                              children: [
                                if (conInsumos) ...[
                                  SegmentoNs(opciones: const ['Servicios', 'Insumos'], indice: segmento, onCambio: (i) => setState(() => _segmento = i)),
                                  const SizedBox(height: 14),
                                ],
                                if (segmento == 0) ..._listaServicios(context, modulos, conInsumos) else ..._listaInsumos(context),
                              ],
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _listaServicios(BuildContext context, ModulosNegocio modulos, bool conInsumos) {
    final ns = context.ns;
    final servicios = _servicios!;
    final porCategoria = <String, List<ServicioConCosto>>{};
    for (final s in servicios) {
      porCategoria.putIfAbsent(_categorias[s.servicio.categoriaId] ?? 'Sin categoría', () => []).add(s);
    }
    final nombres = porCategoria.keys.toList()
      ..sort((a, b) => a == 'Sin categoría' ? 1 : b == 'Sin categoría' ? -1 : a.compareTo(b));
    return [
      if (modulos.estaActivo(Modulo.manoDeObra) && conInsumos) ...[
        ListaAgrupadaNs(filas: [
          _Fila(
            titulo: 'Valor de la hora',
            subtitulo: 'Para la mano de obra de cada servicio',
            derecha: Text(_valorHora == null ? 'Cargar' : plataNs(_valorHora!), style: estiloNs(17, peso: FontWeight.w600, color: _valorHora == null ? ns.i : ns.ink)),
            onTap: _cambiarValorHora,
          ),
        ]),
        const SizedBox(height: 8),
      ],
      if (servicios.isEmpty)
        const InfoNs('Todavía no cargaste ningún servicio. Con "+ Nuevo" ponés lo que dura, qué insumos usa y el precio.'),
      for (final c in nombres) ...[
        SeccionNs(c),
        const SizedBox(height: 8),
        ListaAgrupadaNs(filas: [for (final s in porCategoria[c]!) _filaServicio(context, s, conInsumos)]),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _filaServicio(BuildContext context, ServicioConCosto s, bool conInsumos) {
    final ns = context.ns;
    final minutos = duracionTextoNs(s.servicio.duracionMinutos ?? 0);
    if (!conInsumos) {
      return _Fila(
        titulo: s.servicio.nombre,
        subtitulo: minutos,
        derecha: Text(plataNs(s.precioCentavos), style: estiloNs(17, peso: FontWeight.w600, color: ns.ink)),
        onTap: () => _editarServicio(s),
      );
    }
    final costo = s.costo.totalCentavos;
    final ganancia = s.precioCentavos > 0 ? gananciaBpDesdeCostoYPrecio(costo, s.precioCentavos) : 0;
    final alcanza = s.alcanzaPara;
    final textoAlcanza = alcanza == null ? '' : alcanza < 1 ? ' · no alcanza' : ' · alcanza para $alcanza';
    return _Fila(
      titulo: s.servicio.nombre,
      subtitulo: '$minutos · cuesta ${plataNs(costo)}$textoAlcanza',
      colorSubtitulo: alcanza != null && alcanza < 1 ? ns.b : null,
      derecha: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(plataNs(s.precioCentavos), style: estiloNs(17, peso: FontWeight.w600, color: ns.ink)),
          Text('gana ${ganancia ~/ 100} %', style: estiloNs(13, peso: FontWeight.w600, color: ganancia >= s.gananciaBuscadaBp ? ns.g : ns.w)),
        ],
      ),
      onTap: () => _editarServicio(s),
    );
  }

  List<Widget> _listaInsumos(BuildContext context) {
    final ns = context.ns;
    // Primero lo que se acaba antes: el que está más cerca de su mínimo (sin mínimo, por cantidad).
    double cuanto(InsumoConCosto i) {
      final minimo = i.insumo.stockMinimoMilesimas ?? 0;
      return minimo > 0 ? i.stockMilesimas / minimo : 1e6 + i.stockMilesimas.toDouble();
    }

    final orden = [..._insumos]..sort((a, b) => cuanto(a).compareTo(cuanto(b)));
    return [
      Row(
        children: [
          Expanded(child: BotonNs.primario(context, 'Cargar compra', () => _compra(), icono: IconoNs.masMas, alto: 54, tamanio: 16)),
          const SizedBox(width: 8),
          Expanded(child: BotonNs.secundario(context, 'Contar', _elegirParaContar, icono: IconoNs.portapapeles)),
        ],
      ),
      const SizedBox(height: 14),
      if (orden.isEmpty)
        const InfoNs('Todavía no cargaste insumos. Con "+ Insumo" ponés lo que trae el envase y lo que pagás por él.')
      else ...[
        const SeccionNs('Por acabarse primero'),
        const SizedBox(height: 8),
        ListaAgrupadaNs(filas: [
          for (final i in orden)
            _Fila(
              titulo: i.insumo.nombre,
              subtitulo: [
                _cantidad(i.stockMilesimas, i.unidad),
                if (i.costoPorUnidadCentavos != null) '${plataNs(i.costoPorUnidadCentavos!)}/${i.unidad.abreviatura}',
              ].join(' · '),
              derecha: i.stockBajo ? const EtiquetaStockNs('Poco stock', sinStock: false) : null,
              colorSubtitulo: i.stockMilesimas <= 0 ? ns.b : null,
              onTap: () => _accionesInsumo(i),
            ),
        ]),
      ],
    ];
  }
}

/// Fila de lista agrupada: título, subtítulo y algo a la derecha.
class _Fila extends StatelessWidget {
  const _Fila({required this.titulo, required this.onTap, this.subtitulo, this.derecha, this.colorSubtitulo});

  final String titulo;
  final String? subtitulo;
  final Widget? derecha;
  final Color? colorSubtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: titulo,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w500, color: ns.ink)),
                  if (subtitulo != null) Text(subtitulo!, style: estiloNs(14, altura: 1.3, color: colorSubtitulo ?? ns.mute)),
                ],
              ),
            ),
            if (derecha != null) ...[const SizedBox(width: 12), derecha!],
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Compra y conteo ─────────────────────────

class _HojaCompra extends StatefulWidget {
  const _HojaCompra({required this.db, required this.usuarioId, required this.insumos, required this.inicial});

  final AppDatabase db;
  final int usuarioId;
  final List<InsumoConCosto> insumos;
  final InsumoConCosto inicial;

  @override
  State<_HojaCompra> createState() => _HojaCompraState();
}

class _HojaCompraState extends State<_HojaCompra> {
  late InsumoConCosto _insumo = widget.inicial;
  final _envases = TextEditingController(text: '1');
  late final _precio = TextEditingController(text: formatearARS(widget.inicial.insumo.costoCentavos ?? 0, conSigno: false));
  String? _error;

  @override
  void dispose() {
    _envases.dispose();
    _precio.dispose();
    super.dispose();
  }

  int get _cantidadEnvases => int.tryParse(_envases.text.trim()) ?? 0;

  String get _calculo {
    final contenido = _insumo.insumo.contenidoEnvaseMilesimas ?? 0;
    final precio = _centavos(_precio.text);
    if (_cantidadEnvases <= 0 || contenido <= 0) return 'Poné cuántos envases entraron.';
    final entra = 'Entran ${_cantidad(_cantidadEnvases * contenido, _insumo.unidad)}';
    if (precio == null) return '$entra.';
    final porUnidad = costoPorUnidadCentavos(InsumoParaCalculo(costoEnvaseCentavos: precio, contenidoEnvaseMilesimas: contenido, stockMilesimas: 0));
    final antes = _insumo.costoPorUnidadCentavos;
    final cambio = antes != null && antes != porUnidad ? ' (antes ${plataNs(antes)}). Los servicios que lo usan recalculan su costo.' : '.';
    return '$entra · ${plataNs(porUnidad)} por ${_insumo.unidad.abreviatura}$cambio';
  }

  Future<void> _sumar() async {
    final precio = _centavos(_precio.text);
    if (_cantidadEnvases <= 0) return setState(() => _error = 'Poné cuántos envases entraron');
    if (precio == null) return setState(() => _error = 'Poné el precio por envase');
    try {
      await cargarCompraDeInsumo(widget.db, insumoId: _insumo.insumo.id, envases: _cantidadEnvases, costoEnvaseCentavos: precio, usuarioId: widget.usuarioId);
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Cargar compra',
      texto: 'Quedan ${_cantidad(_insumo.stockMilesimas, _insumo.unidad)} de ${_insumo.insumo.nombre.toLowerCase()}. '
          'Un envase trae ${_cantidad(_insumo.insumo.contenidoEnvaseMilesimas ?? 0, _insumo.unidad)}.',
      bloques: [
        if (widget.insumos.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in widget.insumos)
                ChipNs(
                  texto: i.insumo.nombre,
                  activo: i.insumo.id == _insumo.insumo.id,
                  onTap: () => setState(() {
                    _insumo = i;
                    _precio.text = formatearARS(i.insumo.costoCentavos ?? 0, conSigno: false);
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: CampoNs(
                etiqueta: 'Envases',
                controller: _envases,
                teclado: TextInputType.number,
                formatos: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CampoNs(
                etiqueta: 'Precio por envase',
                controller: _precio,
                teclado: const TextInputType.numberWithOptions(decimal: true),
                formatos: _formatoPlata,
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InfoNs(_calculo, icono: IconoNs.calculadora, tamanio: 14, vertical: 12),
        if (_error != null) ...[const SizedBox(height: 8), InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
      ],
      botones: [BotonNs.primario(context, 'Sumar al stock', _sumar, icono: IconoNs.tilde)],
    );
  }
}

class _HojaContar extends StatefulWidget {
  const _HojaContar({required this.db, required this.usuarioId, required this.insumo});

  final AppDatabase db;
  final int usuarioId;
  final InsumoConCosto insumo;

  @override
  State<_HojaContar> createState() => _HojaContarState();
}

class _HojaContarState extends State<_HojaContar> {
  late final _ctrl = TextEditingController(text: textoDeMilesimas(widget.insumo.stockMilesimas));
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final milesimas = milesimasDesdeTexto(_ctrl.text);
    if (milesimas == null) return setState(() => _error = 'Poné cuánto hay, por ejemplo 12,5');
    await contarInsumo(widget.db, insumoId: widget.insumo.insumo.id, stockMilesimas: milesimas, usuarioId: widget.usuarioId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final unidad = widget.insumo.unidad;
    return HojaNs(
      titulo: 'Contar ${widget.insumo.insumo.nombre.toLowerCase()}',
      texto: 'Lo que hay ahora, en ${unidad.nombre.toLowerCase()}, sumando los envases abiertos y cerrados.',
      bloques: [
        CampoNs(
          etiqueta: 'Hay (${unidad.abreviatura})',
          controller: _ctrl,
          teclado: const TextInputType.numberWithOptions(decimal: true),
          formatos: _formatoCantidad,
          autofoco: true,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[const SizedBox(height: 8), InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
      ],
      botones: [BotonNs.primario(context, 'Guardar conteo', _guardar, icono: IconoNs.tilde)],
    );
  }
}

// ───────────────────────── Alta y edición de un insumo ─────────────────────────

class PantallaInsumoNs extends StatefulWidget {
  const PantallaInsumoNs({super.key, required this.db, required this.usuarioId, this.existente});

  final AppDatabase db;
  final int usuarioId;
  final Producto? existente;

  @override
  State<PantallaInsumoNs> createState() => _PantallaInsumoNsState();
}

class _PantallaInsumoNsState extends State<PantallaInsumoNs> {
  late final Producto? _e = widget.existente;
  late final _nombre = TextEditingController(text: _e?.nombre ?? '');
  late UnidadInsumo _unidad = _e == null ? UnidadInsumo.ml : _unidadDe(_e);
  late final _contenido = TextEditingController(text: _e?.contenidoEnvaseMilesimas == null ? '' : textoDeMilesimas(_e!.contenidoEnvaseMilesimas!));
  late final _costo = TextEditingController(text: _e?.costoCentavos == null ? '' : formatearARS(_e!.costoCentavos!, conSigno: false));
  final _stock = TextEditingController();
  late final _minimo = TextEditingController(text: (_e?.stockMinimoMilesimas ?? 0) > 0 ? textoDeMilesimas(_e!.stockMinimoMilesimas!) : '');
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_nombre, _contenido, _costo, _stock, _minimo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final contenido = milesimasDesdeTexto(_contenido.text);
    final costo = _centavos(_costo.text);
    final stock = _stock.text.trim().isEmpty ? 0 : milesimasDesdeTexto(_stock.text);
    final minimo = _minimo.text.trim().isEmpty ? null : milesimasDesdeTexto(_minimo.text);
    String? error;
    if (_nombre.text.trim().isEmpty) {
      error = 'Falta el nombre';
    } else if (contenido == null || contenido <= 0) {
      error = 'Poné lo que trae un envase';
    } else if (costo == null) {
      error = 'Poné lo que pagás por un envase';
    } else if (stock == null || (_minimo.text.trim().isNotEmpty && minimo == null)) {
      error = 'Revisá las cantidades';
    }
    if (error != null) return setState(() => _error = error);
    setState(() => _guardando = true);
    try {
      if (_e == null) {
        await crearInsumo(
          widget.db,
          nombre: _nombre.text,
          unidad: _unidad,
          contenidoEnvaseMilesimas: contenido!,
          costoEnvaseCentavos: costo!,
          stockMilesimas: stock!,
          stockMinimoMilesimas: minimo,
          usuarioId: widget.usuarioId,
        );
      } else {
        await editarInsumo(
          widget.db,
          insumoId: _e.id,
          nombre: _nombre.text,
          unidad: _unidad,
          contenidoEnvaseMilesimas: contenido!,
          costoEnvaseCentavos: costo!,
          stockMinimoMilesimas: minimo,
          proveedorId: _e.proveedorId,
          categoriaId: _e.categoriaId,
          usuarioId: widget.usuarioId,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _unidad.abreviatura;
    return PaginaNs(
      titulo: _e == null ? 'Nuevo insumo' : 'Editar insumo',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej.: Top coat', onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 14),
          const SeccionNs('Se usa en'),
          const SizedBox(height: 8),
          SegmentoNs(
            opciones: [for (final x in UnidadInsumo.values) x.nombre],
            indice: _unidad.index,
            onCambio: (i) => setState(() => _unidad = UnidadInsumo.values[i]),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CampoNs(
                  etiqueta: 'Trae un envase ($u)',
                  controller: _contenido,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatos: _formatoCantidad,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CampoNs(
                  etiqueta: 'Precio por envase',
                  controller: _costo,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatos: _formatoPlata,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_e == null) ...[
                Expanded(
                  child: CampoNs(etiqueta: 'Hay ahora ($u)', controller: _stock, teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _formatoCantidad),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: CampoNs(etiqueta: 'Avisar con menos de ($u)', controller: _minimo, teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _formatoCantidad),
              ),
            ],
          ),
          if (_e != null) ...[
            const SizedBox(height: 10),
            const InfoNs('El stock se cambia con "Cargar compra" o "Contar", así queda el movimiento.', tamanio: 13, vertical: 10),
          ],
        ],
      ),
      botones: [
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar insumo', _guardando ? null : _guardar, habilitado: !_guardando),
      ],
    );
  }
}

// ───────────────────────── Creador de servicio con calculador ─────────────────────────

class _LineaEditable {
  _LineaEditable(this.insumo, this.milesimas);
  final Producto insumo;
  int milesimas;
}

class PantallaEditorServicioNs extends StatefulWidget {
  const PantallaEditorServicioNs({super.key, required this.db, required this.usuarioId, this.existente});

  final AppDatabase db;
  final int usuarioId;
  final ServicioConCosto? existente;

  @override
  State<PantallaEditorServicioNs> createState() => _PantallaEditorServicioNsState();
}

class _PantallaEditorServicioNsState extends State<PantallaEditorServicioNs> {
  late final Producto? _s = widget.existente?.servicio;
  late final _nombre = TextEditingController(text: _s?.nombre ?? '');
  late final _duracion = TextEditingController(text: '${_s?.duracionMinutos ?? 30}');
  late final _precio = TextEditingController(text: (_s?.precioCentavos ?? 0) > 0 ? formatearARS(_s!.precioCentavos!, conSigno: false) : '');
  late final List<_LineaEditable> _receta = [for (final u in widget.existente?.receta ?? const <UsoDeInsumoResuelto>[]) _LineaEditable(u.insumo, u.cantidadMilesimas)];
  late bool _manoDeObra = _s?.sumaManoDeObra ?? false;
  late int _gananciaBp = _s?.gananciaBuscadaBp ?? gananciaBuscadaPorDefectoBp;
  late int? _categoriaId = _s?.categoriaId;
  List<Categoria> _categorias = const [];
  List<InsumoConCosto> _insumos = const [];
  int? _valorHora;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final categorias = await widget.db.select(widget.db.categorias).get();
    final insumos = await listarInsumos(widget.db);
    final config = await configuracionNegocioActual(widget.db);
    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      _insumos = insumos;
      _valorHora = config.valorHoraCentavos;
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _duracion.dispose();
    _precio.dispose();
    super.dispose();
  }

  int get _minutos => int.tryParse(_duracion.text.trim()) ?? 0;
  int get _precioCentavos => _centavos(_precio.text) ?? 0;

  CostoDeServicio _costo(bool manoDeObraActiva) => costoDeServicio(
        receta: [for (final l in _receta) UsoDeInsumo(insumo: insumoParaCalculo(l.insumo), cantidadMilesimas: l.milesimas)],
        duracionMinutos: _minutos,
        valorHoraCentavos: manoDeObraActiva && _manoDeObra ? _valorHora : null,
      );

  Future<void> _agregarInsumo() async {
    final usados = {for (final l in _receta) l.insumo.id};
    final libres = [for (final i in _insumos) if (!usados.contains(i.insumo.id)) i];
    if (libres.isEmpty) {
      return mostrarAvisoNs(context, _insumos.isEmpty ? 'Primero cargá un insumo en Servicios › Insumos' : 'Ya están todos los insumos');
    }
    final elegido = await mostrarHojaNs<InsumoConCosto>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Agregar un insumo',
        texto: 'Elegí qué usa este servicio. La cantidad se ajusta después.',
        bloques: [
          ListaAgrupadaNs(filas: [
            for (final i in libres)
              _Fila(
                titulo: i.insumo.nombre,
                subtitulo: i.costoPorUnidadCentavos == null ? null : '${plataNs(i.costoPorUnidadCentavos!)} por ${i.unidad.abreviatura}',
                onTap: () => Navigator.of(ctx).pop(i),
              ),
          ]),
        ],
      ),
    );
    if (elegido != null) setState(() => _receta.add(_LineaEditable(elegido.insumo, _paso(elegido.insumo))));
  }

  Future<void> _escribirCantidad(_LineaEditable l) async {
    final ctrl = TextEditingController(text: textoDeMilesimas(l.milesimas));
    final valor = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: l.insumo.nombre,
        texto: 'Cuánto usa cada vez, en ${_unidadDe(l.insumo).nombre.toLowerCase()}.',
        bloques: [CampoNs(etiqueta: 'Usa (${_unidadDe(l.insumo).abreviatura})', controller: ctrl, teclado: const TextInputType.numberWithOptions(decimal: true), formatos: _formatoCantidad, autofoco: true)],
        botones: [BotonNs.primario(ctx, 'Listo', () => Navigator.of(ctx).pop(milesimasDesdeTexto(ctrl.text)))],
      ),
    );
    if (valor != null && valor > 0) setState(() => l.milesimas = valor);
  }

  Future<void> _guardar(bool manoDeObraActiva) async {
    String? error;
    if (_nombre.text.trim().isEmpty) {
      error = 'Falta el nombre';
    } else if (_minutos <= 0) {
      error = 'Poné cuánto dura, en minutos';
    } else if (_centavos(_precio.text) == null) {
      error = 'Poné el precio al cliente';
    }
    if (error != null) return setState(() => _error = error);
    setState(() => _guardando = true);
    try {
      await guardarServicio(
        widget.db,
        servicioId: _s?.id,
        nombre: _nombre.text,
        precioCentavos: _precioCentavos,
        duracionMinutos: _minutos,
        receta: [for (final l in _receta) (insumoId: l.insumo.id, milesimas: l.milesimas)],
        sumaManoDeObra: _manoDeObra,
        gananciaBuscadaBp: _gananciaBp == gananciaBuscadaPorDefectoBp && _s?.gananciaBuscadaBp == null ? null : _gananciaBp,
        categoriaId: _categoriaId,
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _dejarDeOfrecer() async {
    final s = _s;
    if (s == null) return;
    await dejarDeOfrecer(widget.db, s.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) {
        final conInsumos = modulos.estaActivo(Modulo.insumos);
        final manoDeObraActiva = conInsumos && modulos.estaActivo(Modulo.manoDeObra);
        final costo = _costo(manoDeObraActiva);
        final usos = [for (final l in _receta) UsoDeInsumo(insumo: insumoParaCalculo(l.insumo), cantidadMilesimas: l.milesimas)];
        final alcanza = alcanzaPara(usos);
        final primero = seAcabaPrimero(usos);
        final sugerido = precioSugeridoCentavos(costoCentavos: costo.totalCentavos, gananciaBuscadaBp: _gananciaBp);
        final ganancia = _precioCentavos > 0 ? gananciaBpDesdeCostoYPrecio(costo.totalCentavos, _precioCentavos) : 0;
        final colorGanancia = ganancia >= _gananciaBp ? ns.g : ganancia >= 4000 ? ns.w : ns.b;
        return PaginaNs(
          titulo: _s == null ? 'Nuevo servicio' : 'Editar servicio',
          cuerpo: ListView(
            padding: EdgeInsets.zero,
            children: [
              CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej.: Semipermanente manos', onChanged: (_) => setState(() => _error = null)),
              const SizedBox(height: 10),
              CampoNs(
                etiqueta: 'Duración (min)',
                controller: _duracion,
                teclado: TextInputType.number,
                formatos: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_categorias.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SeccionNs('Categoría'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _categorias)
                      ChipNs(texto: c.nombre, activo: c.id == _categoriaId, onTap: () => setState(() => _categoriaId = c.id == _categoriaId ? null : c.id)),
                  ],
                ),
              ],
              if (conInsumos) ...[
                const SizedBox(height: 14),
                SeccionNs('Qué usa cada vez', derecha: Text('${_receta.length} ${_receta.length == 1 ? 'insumo' : 'insumos'}', style: estiloNs(14, color: ns.mute))),
                const SizedBox(height: 8),
                ListaAgrupadaNs(filas: [
                  for (final l in _receta) _filaReceta(context, l),
                  _Fila(titulo: '+ Agregar un insumo', onTap: _agregarInsumo),
                ]),
              ],
              if (manoDeObraActiva) ...[
                const SizedBox(height: 12),
                InterruptorNs(
                  etiqueta: 'Sumar mano de obra',
                  descripcion: _valorHora == null
                      ? 'Cargá el valor de la hora en Servicios'
                      : '${plataNs(_valorHora!)} la hora · $_minutos min = '
                          '${plataNs(costoManoDeObraCentavos(duracionMinutos: _minutos, valorHoraCentavos: _valorHora!))}',
                  encendido: _manoDeObra,
                  onCambio: (v) => setState(() => _manoDeObra = v),
                ),
              ],
              if (conInsumos) ...[
                const SizedBox(height: 16),
                HeroNs(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Le cuesta a tu negocio', style: estiloNs(15, color: const Color(0xBFFFFFFF))),
                      Text(plataNs(costo.totalCentavos), style: tituloNs(40, color: TokensNs.blanco)),
                      if (costo.manoDeObraCentavos > 0)
                        Text('Insumos ${plataNs(costo.insumosCentavos)} + mano de obra ${plataNs(costo.manoDeObraCentavos)}',
                            style: estiloNs(14, color: const Color(0xBFFFFFFF))),
                      if (alcanza != null)
                        Text(
                          alcanza < 1
                              ? 'Con el stock de hoy no alcanza: falta ${_receta[primero!].insumo.nombre.toLowerCase()}.'
                              : 'Con el stock de hoy alcanza para $alcanza ${alcanza == 1 ? 'servicio' : 'servicios'}'
                                  '${primero == null ? '' : ' · se acaba primero: ${_receta[primero].insumo.nombre.toLowerCase()}'}',
                          style: estiloNs(14, altura: 1.35, color: alcanza < 1 ? const Color(0xFFFFB4AD) : const Color(0xBFFFFFFF)),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CampoNs(
                etiqueta: 'Precio al cliente',
                controller: _precio,
                grande: true,
                teclado: const TextInputType.numberWithOptions(decimal: true),
                formatos: _formatoPlata,
                onChanged: (_) => setState(() => _error = null),
              ),
              if (conInsumos) ...[
                FilaClaveValorNs(
                  clave: 'Ganancia por servicio',
                  valor: '${plataNs(_precioCentavos - costo.totalCentavos)} · ${ganancia ~/ 100} %',
                  colorValor: colorGanancia,
                  tamanioValor: 16,
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilaClaveValorNs(
                        clave: 'Para ganar el ${_gananciaBp ~/ 100} %',
                        valor: plataNs(sugerido),
                        tamanioValor: 16,
                        sinLinea: true,
                      ),
                    ),
                    BotonNs(
                      texto: 'Usar',
                      onTap: () => setState(() => _precio.text = formatearARS(sugerido, conSigno: false)),
                      alto: 44,
                      tamanio: 15,
                      fondo: Colors.transparent,
                      color: ns.i,
                      rellenar: false,
                      paddingH: 12,
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final bp in const [4000, 5000, 6000, 7000])
                      ChipNs(texto: '${bp ~/ 100} %', activo: bp == _gananciaBp, onTap: () => setState(() => _gananciaBp = bp)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
          botones: [
            if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
            BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar servicio', _guardando ? null : () => _guardar(manoDeObraActiva),
                habilitado: !_guardando, icono: IconoNs.tilde),
            if (_s != null) BotonNs.peligroSuave(context, 'Dejar de ofrecerlo', _dejarDeOfrecer),
          ],
        );
      },
    );
  }

  Widget _filaReceta(BuildContext context, _LineaEditable l) {
    final ns = context.ns;
    final unidad = _unidadDe(l.insumo);
    final uso = UsoDeInsumo(insumo: insumoParaCalculo(l.insumo), cantidadMilesimas: l.milesimas);
    final noAlcanza = (l.insumo.stockMilesimas ?? 0) < l.milesimas;
    final paso = _paso(l.insumo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.insumo.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(16, peso: FontWeight.w500, color: ns.ink)),
                Text('${plataNs(costoDeUsoCentavos(uso))}${noAlcanza ? ' · no alcanza' : ''}', style: estiloNs(13, color: noAlcanza ? ns.b : ns.mute)),
              ],
            ),
          ),
          StepperNs(
            cantidad: _cantidad(l.milesimas, unidad),
            anchoCantidad: 74,
            tamanioCantidad: 15,
            onTapCantidad: () => _escribirCantidad(l),
            onMenos: () => setState(() => l.milesimas > paso ? l.milesimas -= paso : _receta.remove(l)),
            onMas: () => setState(() => l.milesimas += paso),
          ),
        ],
      ),
    );
  }
}
