// Servicios en el celular (`docs/PLAN-SERVICIOS.md`, etapa 2; mock `docs/mock-servicios`, "Servicios"): en un negocio de
// servicios, la pestaña Productos pasa a ser esta. Dos solapas: Servicios (cada uno con lo que cuesta, cuánto gana y para
// cuántos alcanza) e Insumos (por acabarse primero, cargar compra y contar). El creador de servicio calcula el costo en
// vivo y sugiere el precio.
//
// Trabaja sobre la base del celular, como Promos: la etapa 2 es solo para "Solo celular" (con la PC, las pantallas de
// servicios de la PC llegan después). Las cuentas son las de `domain/servicios.dart`, por `data/repositorio_servicios.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show cambiarActivo, listarCategorias;
import '../../data/repositorio_servicios.dart';
import '../../domain/dinero.dart' show parsearARS;
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

class PantallaServiciosNs extends StatefulWidget {
  /// [db] y [usuarioId] son para tests.
  const PantallaServiciosNs({super.key, this.db, this.usuarioId});

  final AppDatabase? db;
  final int? usuarioId;

  @override
  State<PantallaServiciosNs> createState() => _PantallaServiciosNsState();
}

class _PantallaServiciosNsState extends State<PantallaServiciosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  int _solapa = 0;
  List<ServicioListado>? _servicios;
  List<InsumoListado> _insumos = const [];
  Map<int, String> _categorias = const {};
  int? _usuarioId;
  StreamSubscription<void>? _sub;

  bool get _conInsumos => moduloActivo(Modulo.insumos);

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    _sub = avisosCambiosCompanion.listen((_) => _recargar());
    modulosActuales.addListener(_recargar);
    _recargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    modulosActuales.removeListener(_recargar);
    super.dispose();
  }

  Future<void> _recargar() async {
    final r = await Future.wait([
      listarServicios(_db, conManoDeObra: moduloActivo(Modulo.manoDeObra)),
      listarInsumos(_db),
      listarCategorias(_db),
    ]);
    if (!mounted) return;
    setState(() {
      _servicios = r[0] as List<ServicioListado>;
      _insumos = r[1] as List<InsumoListado>;
      _categorias = {for (final c in r[2] as List<Categoria>) c.id: c.nombre};
      if (!_conInsumos) _solapa = 0;
    });
  }

  Future<void> _conUsuario(Future<void> Function(int usuarioId) hacer) async {
    final u = _usuarioId;
    if (u == null) {
      mostrarAvisoNs(context, 'Falta elegir usuario');
      return;
    }
    await hacer(u);
  }

  Future<void> _abrirEditor({ServicioListado? existente}) => _conUsuario((u) async {
    final guardo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PantallaEditorServicioNs(db: _db, usuarioId: u, existente: existente)),
    );
    await _recargar();
    if (guardo != null && mounted) mostrarAvisoNs(context, guardo);
  });

  Future<void> _hojaInsumo({InsumoListado? existente}) => _conUsuario((u) async {
    final listo = await mostrarHojaNs<String>(context, builder: (_) => _HojaInsumo(db: _db, usuarioId: u, existente: existente));
    await _recargar();
    if (listo != null && mounted) mostrarAvisoNs(context, listo);
  });

  Future<void> _hojaCompra({InsumoListado? insumo}) => _conUsuario((u) async {
    if (_insumos.isEmpty) {
      mostrarAvisoNs(context, 'Primero cargá un insumo');
      return;
    }
    final listo = await mostrarHojaNs<String>(context, builder: (_) => _HojaCompra(db: _db, usuarioId: u, insumos: _insumos, elegido: insumo ?? _porAcabarse.first));
    await _recargar();
    if (listo != null && mounted) mostrarAvisoNs(context, listo);
  });

  Future<void> _hojaContar(InsumoListado insumo) => _conUsuario((u) async {
    final listo = await mostrarHojaNs<String>(context, builder: (_) => _HojaContar(db: _db, usuarioId: u, insumo: insumo));
    await _recargar();
    if (listo != null && mounted) mostrarAvisoNs(context, listo);
  });

  /// Lo que se acaba primero arriba: el que menos stock tiene contra su mínimo (sin mínimo, por stock).
  List<InsumoListado> get _porAcabarse {
    double clave(InsumoListado i) {
      final minimo = i.producto.stockMinimoMilesimas ?? 0;
      return minimo > 0 ? i.stockMilesimas / minimo : 1e9 + i.stockMilesimas;
    }

    return [..._insumos]..sort((a, b) => clave(a).compareTo(clave(b)));
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final app = AppNs.maybeOf(context);
    final conPc = app?.modoUso == ModoUso.pcYCelular;
    return PantallaEntradaNs(
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<ModulosNegocio>(
          valueListenable: modulosActuales,
          builder: (context, _, _) => ListView(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado - 8),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Servicios', style: tituloNs(42, track: -0.055, color: ns.ink))),
                  if (!conPc)
                    BotonNs(
                      texto: _solapa == 0 ? '+ Nuevo' : '+ Insumo',
                      onTap: _solapa == 0 ? () => _abrirEditor() : () => _hojaInsumo(),
                      alto: 44,
                      tamanio: 15,
                      fondo: ns.prim,
                      color: TokensNs.blanco,
                      rellenar: false,
                      paddingH: 20,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (conPc)
                const InfoNs('Con la PC, los servicios todavía se cargan solo en "Solo celular". Las pantallas de la PC llegan más adelante.', icono: IconoNs.computadora)
              else ...[
                if (_conInsumos) ...[
                  SegmentoNs(opciones: const ['Servicios', 'Insumos'], indice: _solapa, onCambio: (i) => setState(() => _solapa = i)),
                  const SizedBox(height: 14),
                ],
                if (_servicios == null)
                  const EsqueletoListaNs()
                else if (_solapa == 0)
                  ..._listaServicios(context)
                else
                  ..._listaInsumos(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _listaServicios(BuildContext context) {
    final ns = context.ns;
    final servicios = _servicios!;
    if (servicios.isEmpty) {
      return [const InfoNs('Todavía no cargaste ningún servicio. Con "+ Nuevo" ponés el nombre, cuánto dura y qué insumos usa, y la app calcula lo que te cuesta.')];
    }
    final porCategoria = <String, List<ServicioListado>>{};
    for (final s in servicios) {
      porCategoria.putIfAbsent(_categorias[s.producto.categoriaId] ?? 'Sin categoría', () => []).add(s);
    }
    return [
      for (final MapEntry(key: categoria, value: lista) in porCategoria.entries) ...[
        SeccionNs(categoria),
        const SizedBox(height: 8),
        ListaAgrupadaNs(
          filas: [
            for (final s in lista)
              TarjetaFilaNs(
                key: ValueKey('servicio-${s.producto.id}'),
                titulo: s.producto.nombre,
                subtitulo: _subtituloServicio(s),
                chevron: false,
                radio: 0,
                onTap: () => _abrirEditor(existente: s),
                derecha: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(plataNs(s.producto.precioCentavos ?? 0), style: estiloNs(17, peso: FontWeight.w600, color: ns.ink)),
                    if (_conInsumos && (s.producto.precioCentavos ?? 0) > 0) _TextoGanancia(precio: s.producto.precioCentavos!, costo: s.costo.totalCentavos, buscadaBp: s.gananciaBuscadaBp),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  String _subtituloServicio(ServicioListado s) {
    final partes = [duracionTextoNs(s.producto.duracionMinutos ?? 0)];
    if (_conInsumos) {
      partes.add('cuesta ${plataNs(s.costo.totalCentavos)}');
      final alcanza = s.alcanzaPara;
      if (alcanza != null) partes.add(alcanza < 1 ? 'no alcanza' : 'alcanza para $alcanza');
      if (s.faltantes > 0) partes.add('faltan datos de ${s.faltantes} insumo${s.faltantes == 1 ? '' : 's'}');
    }
    return partes.join(' · ');
  }

  List<Widget> _listaInsumos(BuildContext context) {
    final ns = context.ns;
    return [
      Row(
        children: [
          Expanded(child: BotonNs.primario(context, 'Cargar compra', () => _hojaCompra(), icono: IconoNs.masMas, alto: 52, tamanio: 15)),
        ],
      ),
      const SizedBox(height: 16),
      if (_insumos.isEmpty)
        const InfoNs('Todavía no hay insumos. Un insumo es lo que comprás y gastás de a poco: un frasco de top coat, una caja de guantes. Cargalo con "+ Insumo".')
      else ...[
        const SeccionNs('Por acabarse primero'),
        const SizedBox(height: 8),
        ListaAgrupadaNs(
          filas: [
            for (final i in _porAcabarse)
              TarjetaFilaNs(
                key: ValueKey('insumo-${i.producto.id}'),
                titulo: i.producto.nombre,
                subtitulo: [
                  '${textoDeMilesimas(i.stockMilesimas)} ${i.unidad.abreviatura}',
                  if (i.costoPorUnidadCentavos != null) '${plataNs(i.costoPorUnidadCentavos!)}/${i.unidad.abreviatura}',
                ].join(' · '),
                chevron: false,
                radio: 0,
                onTap: () => _accionesInsumo(i),
                derecha: i.pocoStock ? Text('Poco stock', style: estiloNs(13, peso: FontWeight.w600, color: ns.w)) : null,
              ),
          ],
        ),
      ],
    ];
  }

  Future<void> _accionesInsumo(InsumoListado i) async {
    final elegido = await mostrarHojaNs<String>(
      context,
      builder: (ctx) => HojaNs(
        titulo: i.producto.nombre,
        texto: 'Quedan ${textoDeMilesimas(i.stockMilesimas)} ${i.unidad.abreviatura}.',
        botones: [
          BotonNs.primario(ctx, 'Cargar compra', () => Navigator.of(ctx).pop('compra'), icono: IconoNs.masMas),
          BotonNs.secundario(ctx, 'Contar lo que hay', () => Navigator.of(ctx).pop('contar'), icono: IconoNs.portapapeles),
          BotonNs.secundario(ctx, 'Editar', () => Navigator.of(ctx).pop('editar'), icono: IconoNs.editar),
        ],
      ),
    );
    if (!mounted) return;
    switch (elegido) {
      case 'compra':
        await _hojaCompra(insumo: i);
      case 'contar':
        await _hojaContar(i);
      case 'editar':
        await _hojaInsumo(existente: i);
    }
  }
}

/// "gana 62 %", en verde si llega a la buscada y en amarillo si no.
class _TextoGanancia extends StatelessWidget {
  const _TextoGanancia({required this.precio, required this.costo, required this.buscadaBp});
  final int precio;
  final int costo;
  final int buscadaBp;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final bp = gananciaBpDesdeCostoYPrecio(costo, precio);
    return Text('gana ${(bp / 100).round()} %', style: estiloNs(13, peso: FontWeight.w600, color: bp >= buscadaBp ? ns.g : ns.w));
  }
}

int? _plata(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  try {
    return parsearARS(t);
  } on FormatException {
    return null;
  }
}

String _plataEnCampo(int? centavos) => centavos == null ? '' : '${centavos ~/ 100}';

// ───────────────────────── Insumo: alta y edición ─────────────────────────

class _HojaInsumo extends StatefulWidget {
  const _HojaInsumo({required this.db, required this.usuarioId, this.existente});
  final AppDatabase db;
  final int usuarioId;
  final InsumoListado? existente;

  @override
  State<_HojaInsumo> createState() => _HojaInsumoState();
}

class _HojaInsumoState extends State<_HojaInsumo> {
  late final _nombre = TextEditingController(text: widget.existente?.producto.nombre ?? '');
  late final _contenido = TextEditingController(
    text: widget.existente?.producto.contenidoEnvaseMilesimas == null ? '' : textoDeMilesimas(widget.existente!.producto.contenidoEnvaseMilesimas!),
  );
  late final _costo = TextEditingController(text: _plataEnCampo(widget.existente?.producto.costoCentavos));
  late final _minimo = TextEditingController(
    text: (widget.existente?.producto.stockMinimoMilesimas ?? 0) > 0 ? textoDeMilesimas(widget.existente!.producto.stockMinimoMilesimas!) : '',
  );
  late UnidadInsumo _unidad = widget.existente?.unidad ?? UnidadInsumo.ml;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _contenido.dispose();
    _costo.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final contenido = milesimasDesdeTexto(_contenido.text);
    final costo = _plata(_costo.text);
    final minimo = _minimo.text.trim().isEmpty ? null : milesimasDesdeTexto(_minimo.text);
    if (_nombre.text.trim().isEmpty || contenido == null || contenido <= 0 || costo == null) {
      setState(() => _error = 'Completá nombre, lo que trae un envase y lo que sale');
      return;
    }
    try {
      final e = widget.existente;
      if (e == null) {
        await crearInsumo(widget.db, nombre: _nombre.text, unidad: _unidad, contenidoEnvaseMilesimas: contenido, costoEnvaseCentavos: costo, stockMinimoMilesimas: minimo, usuarioId: widget.usuarioId);
      } else {
        await editarInsumo(
          widget.db,
          id: e.producto.id,
          nombre: _nombre.text,
          unidad: _unidad,
          contenidoEnvaseMilesimas: contenido,
          costoEnvaseCentavos: costo,
          proveedorId: e.producto.proveedorId,
          categoriaId: e.producto.categoriaId,
          stockMinimoMilesimas: minimo,
          usuarioId: widget.usuarioId,
        );
      }
      if (mounted) Navigator.of(context).pop(e == null ? 'Insumo cargado. Sumá lo que tenés con "Cargar compra".' : 'Insumo guardado');
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final decimales = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return HojaNs(
      titulo: widget.existente == null ? 'Nuevo insumo' : 'Editar insumo',
      texto: 'Lo que comprás y gastás de a poco. Se compra por envase y cada servicio usa una parte.',
      bloques: [
        CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej.: Top coat', autofoco: widget.existente == null),
        Wrap(
          spacing: 8,
          children: [
            for (final u in UnidadInsumo.values) ChipNs(texto: u.nombre, activo: u == _unidad, onTap: () => setState(() => _unidad = u)),
          ],
        ),
        Row(
          children: [
            Expanded(child: CampoNs(etiqueta: 'Trae un envase (${_unidad.abreviatura})', controller: _contenido, placeholder: '15', teclado: const TextInputType.numberWithOptions(decimal: true), formatos: decimales)),
            const SizedBox(width: 10),
            Expanded(child: CampoNs(etiqueta: 'Sale el envase', controller: _costo, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs)),
          ],
        ),
        CampoNs(etiqueta: 'Avisar con menos de (${_unidad.abreviatura}, opcional)', controller: _minimo, teclado: const TextInputType.numberWithOptions(decimal: true), formatos: decimales),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, 'Guardar insumo', _guardar, icono: IconoNs.tilde)],
    );
  }
}

// ───────────────────────── Insumo: compra y conteo ─────────────────────────

class _HojaCompra extends StatefulWidget {
  const _HojaCompra({required this.db, required this.usuarioId, required this.insumos, required this.elegido});
  final AppDatabase db;
  final int usuarioId;
  final List<InsumoListado> insumos;
  final InsumoListado elegido;

  @override
  State<_HojaCompra> createState() => _HojaCompraState();
}

class _HojaCompraState extends State<_HojaCompra> {
  late InsumoListado _insumo = widget.elegido;
  final _envases = TextEditingController(text: '1');
  late final _precio = TextEditingController(text: _plataEnCampo(widget.elegido.producto.costoCentavos));
  String? _error;

  @override
  void dispose() {
    _envases.dispose();
    _precio.dispose();
    super.dispose();
  }

  String get _calculo {
    final envases = int.tryParse(_envases.text) ?? 0;
    final contenido = _insumo.producto.contenidoEnvaseMilesimas ?? 0;
    final precio = _plata(_precio.text);
    if (envases <= 0 || contenido <= 0) return 'Poné cuántos envases compraste.';
    final u = _insumo.unidad.abreviatura;
    final entra = 'Entran ${textoDeMilesimas(envases * contenido)} $u';
    if (precio == null) return '$entra.';
    final porUnidad = costoPorUnidadCentavos(InsumoParaCalculo(costoEnvaseCentavos: precio, contenidoEnvaseMilesimas: contenido, stockMilesimas: 0));
    final antes = _insumo.costoPorUnidadCentavos;
    return '$entra · ${plataNs(porUnidad)} por $u'
        '${antes != null && antes != porUnidad ? ' (antes ${plataNs(antes)}). Los servicios que lo usan recalculan su costo.' : '.'}';
  }

  Future<void> _guardar() async {
    final envases = int.tryParse(_envases.text) ?? 0;
    try {
      await cargarCompraDeInsumo(widget.db, insumoId: _insumo.producto.id, envases: envases, costoEnvaseCentavos: _plata(_precio.text), usuarioId: widget.usuarioId);
      if (mounted) Navigator.of(context).pop('Compra sumada al stock');
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return HojaNs(
      titulo: 'Cargar compra',
      texto: 'Quedan ${textoDeMilesimas(_insumo.stockMilesimas)} ${_insumo.unidad.abreviatura} de ${_insumo.producto.nombre}.',
      bloques: [
        if (widget.insumos.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in widget.insumos)
                ChipNs(
                  texto: i.producto.nombre,
                  activo: i.producto.id == _insumo.producto.id,
                  onTap: () => setState(() {
                    _insumo = i;
                    _precio.text = _plataEnCampo(i.producto.costoCentavos);
                  }),
                ),
            ],
          ),
        Row(
          children: [
            Expanded(child: CampoNs(etiqueta: 'Envases', controller: _envases, teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(child: CampoNs(etiqueta: 'Precio por envase', controller: _precio, teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {}))),
          ],
        ),
        InfoNs(_calculo, icono: IconoNs.calculadora, tamanio: 14),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        Text('Trae ${textoDeMilesimas(_insumo.producto.contenidoEnvaseMilesimas ?? 0)} ${_insumo.unidad.abreviatura} por envase (se cambia en Editar).', style: estiloNs(13, color: ns.mute)),
      ],
      botones: [BotonNs.primario(context, 'Sumar al stock', _guardar, icono: IconoNs.tilde)],
    );
  }
}

class _HojaContar extends StatefulWidget {
  const _HojaContar({required this.db, required this.usuarioId, required this.insumo});
  final AppDatabase db;
  final int usuarioId;
  final InsumoListado insumo;

  @override
  State<_HojaContar> createState() => _HojaContarState();
}

class _HojaContarState extends State<_HojaContar> {
  late final _cantidad = TextEditingController(text: textoDeMilesimas(widget.insumo.stockMilesimas));
  String? _error;

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final milesimas = milesimasDesdeTexto(_cantidad.text);
    if (milesimas == null) {
      setState(() => _error = 'Escribí cuánto hay');
      return;
    }
    await contarInsumo(widget.db, insumoId: widget.insumo.producto.id, stockMilesimas: milesimas, usuarioId: widget.usuarioId);
    if (mounted) Navigator.of(context).pop('Stock corregido');
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.insumo.unidad.abreviatura;
    return HojaNs(
      titulo: 'Contar ${widget.insumo.producto.nombre}',
      texto: 'Lo que hay de verdad, sumando los envases abiertos. Queda anotado como conteo.',
      bloques: [
        CampoNs(
          etiqueta: 'Hay ($u)',
          controller: _cantidad,
          grande: true,
          autofoco: true,
          teclado: const TextInputType.numberWithOptions(decimal: true),
          formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        ),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, 'Guardar conteo', _guardar, icono: IconoNs.tilde)],
    );
  }
}

// ───────────────────────── Creador de servicio ─────────────────────────

class _LineaEditable {
  _LineaEditable(this.insumo, this.milesimas);
  final InsumoListado insumo;
  int milesimas;
}

class PantallaEditorServicioNs extends StatefulWidget {
  const PantallaEditorServicioNs({super.key, required this.db, required this.usuarioId, this.existente});
  final AppDatabase db;
  final int usuarioId;
  final ServicioListado? existente;

  @override
  State<PantallaEditorServicioNs> createState() => _PantallaEditorServicioNsState();
}

class _PantallaEditorServicioNsState extends State<PantallaEditorServicioNs> {
  late final _nombre = TextEditingController(text: widget.existente?.producto.nombre ?? '');
  late final _duracion = TextEditingController(text: '${widget.existente?.producto.duracionMinutos ?? 30}');
  late final _precio = TextEditingController(text: _plataEnCampo(widget.existente?.producto.precioCentavos));
  late final List<_LineaEditable> _receta = [for (final u in widget.existente?.receta ?? const <UsoListado>[]) _LineaEditable(u.insumo, u.milesimas)];
  late bool _manoDeObra = widget.existente?.producto.sumaManoDeObra ?? false;
  late int? _categoriaId = widget.existente?.producto.categoriaId;
  List<InsumoListado> _insumos = const [];
  List<Categoria> _categorias = const [];
  int? _valorHora;
  String? _error;

  bool get _conInsumos => moduloActivo(Modulo.insumos);
  bool get _conManoDeObra => _conInsumos && moduloActivo(Modulo.manoDeObra);
  int get _gananciaBuscadaBp => widget.existente?.gananciaBuscadaBp ?? gananciaBuscadaPorDefectoBp;

  @override
  void initState() {
    super.initState();
    Future.wait([
      listarInsumos(widget.db),
      listarCategorias(widget.db),
      widget.db.select(widget.db.configuracionNegocioTabla).getSingleOrNull(),
    ]).then((r) {
      if (!mounted) return;
      setState(() {
        _insumos = r[0] as List<InsumoListado>;
        _categorias = r[1] as List<Categoria>;
        _valorHora = (r[2] as ConfiguracionNegocio?)?.valorHoraCentavos;
      });
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _duracion.dispose();
    _precio.dispose();
    super.dispose();
  }

  int get _minutos => int.tryParse(_duracion.text) ?? 0;

  List<UsoDeInsumo> get _usos => [
    for (final l in _receta)
      if ((l.insumo.producto.contenidoEnvaseMilesimas ?? 0) > 0) UsoDeInsumo(insumo: l.insumo.paraCalculo, cantidadMilesimas: l.milesimas),
  ];

  CostoDeServicio get _costo => costoDeServicio(
    receta: _usos,
    duracionMinutos: _minutos,
    valorHoraCentavos: _conManoDeObra && _manoDeObra ? _valorHora : null,
  );

  /// Cuánto sube o baja cada toque de +/−: de a una unidad lo que se cuenta por unidad; de a 0,1 lo demás.
  int _paso(InsumoListado i) => i.unidad == UnidadInsumo.u ? milesimasPorUnidad : 100;

  Future<void> _agregarInsumo() async {
    final usados = {for (final l in _receta) l.insumo.producto.id};
    final libres = [for (final i in _insumos) if (!usados.contains(i.producto.id)) i];
    if (libres.isEmpty) {
      mostrarAvisoNs(context, _insumos.isEmpty ? 'Primero cargá insumos en la solapa Insumos' : 'Ya están todos');
      return;
    }
    final elegido = await mostrarHojaNs<InsumoListado>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Agregar un insumo',
        texto: 'Elegí qué usa este servicio. La cantidad se ajusta después.',
        bloques: [
          ListaAgrupadaNs(
            filas: [
              for (final i in libres)
                TarjetaFilaNs(
                  titulo: i.producto.nombre,
                  subtitulo: i.costoPorUnidadCentavos == null ? null : '${plataNs(i.costoPorUnidadCentavos!)} por ${i.unidad.abreviatura}',
                  radio: 0,
                  chevron: false,
                  derecha: IconoNsWidget(IconoNs.masMas, tamanio: 20, color: ctx.ns.ink),
                  onTap: () => Navigator.of(ctx).pop(i),
                ),
            ],
          ),
        ],
      ),
    );
    if (elegido != null) setState(() => _receta.add(_LineaEditable(elegido, _paso(elegido))));
  }

  Future<void> _editarCantidad(_LineaEditable l) async {
    final ctrl = TextEditingController(text: textoDeMilesimas(l.milesimas));
    final valor = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: l.insumo.producto.nombre,
        texto: 'Cuánto usa cada vez, en ${l.insumo.unidad.nombre.toLowerCase()}.',
        bloques: [
          CampoNs(
            etiqueta: 'Usa (${l.insumo.unidad.abreviatura})',
            controller: ctrl,
            grande: true,
            autofoco: true,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          ),
        ],
        botones: [BotonNs.primario(ctx, 'Listo', () => Navigator.of(ctx).pop(milesimasDesdeTexto(ctrl.text)))],
      ),
    );
    ctrl.dispose();
    if (valor != null && valor > 0) setState(() => l.milesimas = valor);
  }

  Future<void> _guardar() async {
    final precio = _plata(_precio.text);
    if (_nombre.text.trim().isEmpty || precio == null || _minutos <= 0) {
      setState(() => _error = 'Completá nombre, duración y precio');
      return;
    }
    final receta = [for (final l in _receta) (insumoId: l.insumo.producto.id, milesimas: l.milesimas)];
    try {
      final e = widget.existente;
      if (e == null) {
        await crearServicio(widget.db, nombre: _nombre.text, precioCentavos: precio, duracionMinutos: _minutos, receta: receta,
            sumaManoDeObra: _manoDeObra, categoriaId: _categoriaId, usuarioId: widget.usuarioId);
      } else {
        await editarServicio(widget.db, id: e.producto.id, nombre: _nombre.text, precioCentavos: precio, duracionMinutos: _minutos, receta: receta,
            sumaManoDeObra: _manoDeObra, gananciaBuscadaBp: e.producto.gananciaBuscadaBp, categoriaId: _categoriaId, usuarioId: widget.usuarioId);
      }
      if (mounted) Navigator.of(context).pop(e == null ? 'Servicio creado' : 'Servicio guardado');
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  Future<void> _dejarDeOfrecer() async {
    await cambiarActivo(widget.db, id: widget.existente!.producto.id, activo: false);
    if (mounted) Navigator.of(context).pop('Ya no se ofrece');
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final costo = _costo;
    final precio = _plata(_precio.text);
    final sugerido = precioSugeridoCentavos(costoCentavos: costo.totalCentavos, gananciaBuscadaBp: _gananciaBuscadaBp);
    final alcanza = alcanzaPara(_usos);
    final primero = seAcabaPrimero(_usos);
    return PaginaNs(
      titulo: widget.existente == null ? 'Nuevo servicio' : 'Editar servicio',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej.: Corte clásico', onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 10),
          CampoNs(etiqueta: 'Duración (min)', controller: _duracion, teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {})),
          if (_categorias.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SeccionNs('Categoría'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _categorias) ChipNs(texto: c.nombre, activo: c.id == _categoriaId, onTap: () => setState(() => _categoriaId = c.id == _categoriaId ? null : c.id)),
              ],
            ),
          ],
          if (_conInsumos) ...[
            const SizedBox(height: 16),
            SeccionNs('Qué usa cada vez', derecha: Text('${_receta.length} insumo${_receta.length == 1 ? '' : 's'}', style: estiloNs(13, color: ns.mute))),
            const SizedBox(height: 8),
            for (final l in _receta) _filaReceta(context, l),
            BotonNs(texto: '+ Agregar un insumo', onTap: _agregarInsumo, alto: 52, tamanio: 15, fondo: ns.s, color: ns.i),
          ],
          if (_conManoDeObra) ...[
            const SizedBox(height: 12),
            InterruptorNs(
              etiqueta: 'Sumar mano de obra',
              descripcion: _valorHora == null
                  ? 'Cargá el valor de la hora en Más › Configuración'
                  : '${plataNs(_valorHora!)} la hora · $_minutos min = ${plataNs(costoManoDeObraCentavos(duracionMinutos: _minutos, valorHoraCentavos: _valorHora!))}',
              encendido: _manoDeObra,
              onCambio: (v) => setState(() => _manoDeObra = v),
            ),
          ],
          if (_conInsumos) ...[
            const SizedBox(height: 18),
            HeroNs(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Le cuesta a tu negocio', style: estiloNs(14, color: TokensNs.blanco)),
                  Text(plataNs(costo.totalCentavos), style: tituloNs(40, color: TokensNs.blanco)),
                  if (costo.manoDeObraCentavos > 0)
                    Text('Insumos ${plataNs(costo.insumosCentavos)} + mano de obra ${plataNs(costo.manoDeObraCentavos)}', style: estiloNs(14, color: TokensNs.blanco)),
                  if (alcanza != null)
                    Text(
                      alcanza < 1 && primero != null
                          ? 'Con el stock de hoy no alcanza: falta ${_receta[primero].insumo.producto.nombre.toLowerCase()}.'
                          : 'Con el stock de hoy alcanza para $alcanza ${alcanza == 1 ? 'servicio' : 'servicios'}'
                                '${primero != null ? ' · se acaba primero: ${_receta[primero].insumo.producto.nombre.toLowerCase()}' : ''}',
                      style: estiloNs(14, altura: 1.35, color: TokensNs.blanco),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          CampoNs(etiqueta: 'Precio al cliente', controller: _precio, grande: true, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() => _error = null)),
          if (_conInsumos) ...[
            if (precio != null && precio > 0)
              FilaClaveValorNs(
                clave: 'Ganancia por servicio',
                valor: '${plataNs(precio - costo.totalCentavos)} · ${(gananciaBpDesdeCostoYPrecio(costo.totalCentavos, precio) / 100).round()} %',
                colorValor: gananciaBpDesdeCostoYPrecio(costo.totalCentavos, precio) >= _gananciaBuscadaBp ? ns.g : ns.w,
                tamanioValor: 16,
              ),
            Row(
              children: [
                Expanded(
                  child: FilaClaveValorNs(clave: 'Para ganar el ${_gananciaBuscadaBp ~/ 100} %', valor: plataNs(sugerido), tamanioValor: 16, sinLinea: true),
                ),
                const SizedBox(width: 8),
                BotonNs(
                  texto: 'Usar',
                  onTap: () => setState(() => _precio.text = _plataEnCampo(sugerido)),
                  alto: 40,
                  tamanio: 14,
                  fondo: ns.s,
                  color: ns.i,
                  rellenar: false,
                  paddingH: 16,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
      botones: [
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        BotonNs.primario(context, 'Guardar servicio', _guardar, icono: IconoNs.tilde),
        if (widget.existente != null) BotonNs.secundario(context, 'Dejar de ofrecerlo', _dejarDeOfrecer),
      ],
    );
  }

  Widget _filaReceta(BuildContext context, _LineaEditable l) {
    final ns = context.ns;
    final i = l.insumo;
    final uso = (i.producto.contenidoEnvaseMilesimas ?? 0) > 0 ? costoDeUsoCentavos(UsoDeInsumo(insumo: i.paraCalculo, cantidadMilesimas: l.milesimas)) : null;
    final noAlcanza = i.stockMilesimas < l.milesimas;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink)),
                Text(
                  [
                    if (uso != null) plataNs(uso),
                    if (i.costoPorUnidadCentavos != null) '(${plataNs(i.costoPorUnidadCentavos!)}/${i.unidad.abreviatura})',
                    if (noAlcanza) 'no alcanza',
                  ].join(' '),
                  style: estiloNs(13, color: noAlcanza ? ns.b : ns.mute),
                ),
              ],
            ),
          ),
          StepperNs(
            cantidad: '${textoDeMilesimas(l.milesimas)} ${i.unidad.abreviatura}',
            anchoCantidad: 72,
            tamanioCantidad: 14,
            fondo: ns.paper,
            onTapCantidad: () => _editarCantidad(l),
            onMenos: l.milesimas > _paso(i) ? () => setState(() => l.milesimas -= _paso(i)) : null,
            onMas: () => setState(() => l.milesimas += _paso(i)),
          ),
          BotonCircularNs(icono: IconoNs.papelera, onTap: () => setState(() => _receta.remove(l)), etiqueta: 'Quitar ${i.producto.nombre}', tamanioIcono: 16),
        ],
      ),
    );
  }
}
