// Promos en el celular (El dueño, 2026-10-07: "seguí con promos"). Lo mismo que Proveedores › Promos de la PC — lista, crear, editar,
// activar y "Sugerir promos" —, con las mismas cuentas y reglas: `calcularPromo`/`guardarPromo` (`data/repositorio_promos.dart`),
// `sugerirPromos` (`data/repositorio_sugerencia_promos.dart`) y los nombres con la IA (`servicios/asistente_promos.dart`).
//
// Trabaja sobre la base del celular, como Cargar factura: la promo y sus artículos viajan a la PC por la sync (v62).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/normalizacion_texto.dart';
import '../data/repositorio_promos.dart';
import '../data/repositorio_sugerencia_promos.dart';
import '../domain/promo.dart' show atajosPorcentajePromo, porcentajePromoPorDefectoBp, textoPorcentajeBp;
import '../servicios/asistente_promos.dart';
import '../servicios/gemini.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';

class PantallaPromos extends StatefulWidget {
  /// [db], [usuarioId] y [clienteIa] son para tests.
  const PantallaPromos({super.key, this.db, this.usuarioId, this.clienteIa});

  final AppDatabase? db;
  final int? usuarioId;
  final http.Client? clienteIa;

  @override
  State<PantallaPromos> createState() => _PantallaPromosState();
}

class _PantallaPromosState extends State<PantallaPromos> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<PromoConComponentes>? _promos;
  int? _usuarioId;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    _recargar();
  }

  Future<void> _recargar() async {
    final promos = await listarPromos(_db);
    if (mounted) setState(() => _promos = promos);
  }

  Future<void> _abrirCreador({PromoConComponentes? existente, _SugerenciaElegida? sugerida}) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) {
      mostrarAvisoNs(context, 'Falta elegir usuario');
      return;
    }
    final guardo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _PantallaCrearPromo(db: _db, usuarioId: usuarioId, existente: existente, sugerida: sugerida)),
    );
    if (guardo == true) {
      await _recargar();
      if (mounted) mostrarAvisoNs(context, existente == null ? 'Promo creada' : 'Promo guardada');
    }
  }

  Future<void> _abrirSugerencias() async {
    final elegida = await Navigator.of(context).push<_SugerenciaElegida>(
      MaterialPageRoute(builder: (_) => _PantallaSugerencias(db: _db, clienteIa: widget.clienteIa)),
    );
    if (elegida != null && mounted) await _abrirCreador(sugerida: elegida);
  }

  Future<void> _alternar(PromoConComponentes p) async {
    await cambiarActivaPromo(_db, promoId: p.promo.id, activa: !p.promo.activo);
    await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final promos = _promos;
    return PaginaNs(
      titulo: 'Promos',
      cuerpo: promos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                Text('Se venden como un producto más y descuentan el stock de cada artículo.', style: estiloNs(15, altura: 1.4, color: ns.mute)),
                const SizedBox(height: 12),
                BotonNs.secundario(context, 'Sugerir promos', _abrirSugerencias, icono: IconoNs.porcentaje),
                const SizedBox(height: 12),
                if (promos.isEmpty) const InfoNs('Todavía no armaste ninguna. Con "Nueva promo" elegís dos o más artículos y el porcentaje.'),
                for (final p in promos) _TarjetaPromo(p: p, onEditar: () => _abrirCreador(existente: p), onAlternar: () => _alternar(p)),
              ],
            ),
      botones: [BotonNs.primario(context, 'Nueva promo', () => _abrirCreador(), icono: IconoNs.masMas)],
    );
  }
}

class _TarjetaPromo extends StatelessWidget {
  const _TarjetaPromo({required this.p, required this.onEditar, required this.onAlternar});
  final PromoConComponentes p;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final apagada = !p.promo.activo;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(p.promo.nombre, style: estiloNs(18, peso: FontWeight.w500, color: apagada ? ns.mute : ns.ink))),
              Text(plataNs(p.promo.precioCentavos ?? 0), style: estiloNs(18, peso: FontWeight.w600, color: apagada ? ns.mute : ns.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Text(p.componentes.map((c) => c.cantidad > 1 ? '${c.cantidad} × ${c.producto.nombre}' : c.producto.nombre).join(' + '),
              style: estiloNs(14, altura: 1.3, color: ns.mute)),
          Text('Costo ${plataNs(p.costoCentavos)} · sueltos ${plataNs(p.listaCentavos)} · alcanzan ${p.stock}', style: estiloNs(13, color: ns.mute)),
          if (apagada) ...[const SizedBox(height: 8), const InfoNs('Desactivada: no aparece en la venta.', tamanio: 13, vertical: 10)],
          if (p.pasaDeLista) ...[
            const SizedBox(height: 8),
            const InfoNs('Pasa el precio de lista: bajó algún artículo. Editala para recalcular.', tono: TonoNs.warn, tamanio: 13, vertical: 10),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: BotonNs(texto: 'Editar', onTap: onEditar, alto: 44, tamanio: 14, fondo: ns.paper, color: ns.ink)),
              const SizedBox(width: 8),
              Expanded(child: BotonNs(texto: apagada ? 'Activar' : 'Desactivar', onTap: onAlternar, alto: 44, tamanio: 14, fondo: ns.paper, color: ns.ink)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lo que el dueño eligió crear de las sugerencias: la sugerencia, el nombre (el de la IA o el simple) y el porcentaje.
typedef _SugerenciaElegida = ({SugerenciaDePromo sugerencia, String nombre, int bp});

/// Elegir el porcentaje: los atajos de siempre y "Otro %".
class _SelectorPorcentaje extends StatelessWidget {
  const _SelectorPorcentaje({required this.bp, required this.onCambio});
  final int bp;
  final ValueChanged<int> onCambio;

  Future<void> _otro(BuildContext context) async {
    final ctrl = TextEditingController(text: '${bp ~/ 100}');
    final elegido = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Otro porcentaje',
        bloques: [
          CampoNs(
            etiqueta: 'Ganancia (%)',
            controller: ctrl,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            autofoco: true,
          ),
        ],
        botones: [
          BotonNs.primario(ctx, 'Listo', () {
            final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
            Navigator.of(ctx).pop(v == null || v <= 0 ? null : (v * 100).round());
          }),
        ],
      ),
    );
    ctrl.dispose();
    if (elegido != null) onCambio(elegido);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in atajosPorcentajePromo) ChipNs(texto: textoPorcentajeBp(a), activo: a == bp, onTap: () => onCambio(a)),
        ChipNs(texto: atajosPorcentajePromo.contains(bp) ? 'Otro %' : '${textoPorcentajeBp(bp)} ✎', activo: !atajosPorcentajePromo.contains(bp), onTap: () => _otro(context)),
      ],
    );
  }
}

/// Lo que va a costar la promo con lo elegido: sueltos, promo, ahorro del cliente y lo que te queda. Mismos textos que la PC.
class _Calculo extends StatelessWidget {
  const _Calculo(this.calculo);
  final PrecioDePromoCalculado? calculo;

  @override
  Widget build(BuildContext context) {
    final c = calculo;
    if (c == null) return const InfoNs('Elegí al menos dos artículos con costo y precio.', tamanio: 13, vertical: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilaClaveValorNs(clave: 'Precio de la promo', valor: plataNs(c.precioCentavos), tamanioValor: 24),
        FilaClaveValorNs(clave: 'Sueltos', valor: plataNs(c.listaCentavos), tamanioValor: 16),
        FilaClaveValorNs(clave: 'El cliente ahorra', valor: plataNs(c.listaCentavos - c.precioCentavos), tamanioValor: 16),
        FilaClaveValorNs(clave: 'Te quedan por promo', valor: plataNs(c.precioCentavos - c.costoCentavos), tamanioValor: 16, sinLinea: true),
        if (c.topeadoPorLista) const InfoNs('Con ese porcentaje no baja del precio de lista: no hay descuento para el cliente.', tono: TonoNs.warn, tamanio: 13, vertical: 10),
        if (!c.cubreElCosto) const InfoNs('Con ese porcentaje la promo no cubre su costo.', tono: TonoNs.bad, tamanio: 13, vertical: 10),
      ],
    );
  }
}

class _Elegido {
  _Elegido(this.producto, this.cantidad);
  final Producto producto;
  int cantidad;
}

class _PantallaCrearPromo extends StatefulWidget {
  const _PantallaCrearPromo({required this.db, required this.usuarioId, this.existente, this.sugerida});
  final AppDatabase db;
  final int usuarioId;
  final PromoConComponentes? existente;
  final _SugerenciaElegida? sugerida;

  @override
  State<_PantallaCrearPromo> createState() => _PantallaCrearPromoState();
}

class _PantallaCrearPromoState extends State<_PantallaCrearPromo> {
  late final _nombre = TextEditingController(text: widget.existente?.promo.nombre ?? widget.sugerida?.nombre ?? '');
  final _buscar = TextEditingController();
  late final List<_Elegido> _elegidos = [
    for (final c in widget.existente?.componentes ?? widget.sugerida?.sugerencia.componentes ?? const <ComponenteDePromo>[]) _Elegido(c.producto, c.cantidad),
  ];
  List<Producto> _elegibles = const [];
  late int _bp = widget.sugerida?.bp ?? porcentajePromoPorDefectoBp;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    productosParaPromo(widget.db).then((e) {
      if (mounted) setState(() => _elegibles = e);
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _buscar.dispose();
    super.dispose();
  }

  PrecioDePromoCalculado? get _calculo => calcularPromo([for (final e in _elegidos) ComponenteDePromo(producto: e.producto, cantidad: e.cantidad)], _bp);

  List<Producto> get _resultados {
    final texto = normalizarTexto(_buscar.text);
    if (texto.isEmpty) return const [];
    final ya = {for (final e in _elegidos) e.producto.id};
    return [for (final p in _elegibles) if (!ya.contains(p.id) && normalizarTexto(p.nombre).contains(texto)) p].take(6).toList();
  }

  bool get _sePuedeGuardar {
    final c = _calculo;
    return _nombre.text.trim().isNotEmpty && _elegidos.length >= 2 && c != null && c.cubreElCosto;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await guardarPromo(
        widget.db,
        promoId: widget.existente?.promo.id,
        nombre: _nombre.text,
        articulos: [for (final e in _elegidos) (productoId: e.producto.id, cantidad: e.cantidad)],
        gananciaBp: _bp,
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PaginaNs(
      titulo: widget.existente == null ? 'Nueva promo' : 'Editar promo',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          CampoNs(etiqueta: 'Nombre de la promo', controller: _nombre, placeholder: 'Ej: Merienda', onChanged: (_) => setState(() => _error = null)),
          const SizedBox(height: 14),
          const SeccionNs('Artículos (al menos dos)'),
          const SizedBox(height: 8),
          for (final e in _elegidos)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink)),
                        Text('Costo ${plataNs(e.producto.costoCentavos ?? 0)} · lista ${plataNs(e.producto.precioCentavos ?? 0)}', style: estiloNs(13, color: ns.mute)),
                      ],
                    ),
                  ),
                  BotonCircularNs(
                    icono: e.cantidad > 1 ? IconoNs.menos : IconoNs.papelera,
                    onTap: () => setState(() => e.cantidad > 1 ? e.cantidad-- : _elegidos.remove(e)),
                    etiqueta: e.cantidad > 1 ? 'Una menos' : 'Quitar ${e.producto.nombre}',
                    tamanioIcono: 16,
                  ),
                  SizedBox(width: 32, child: Text('${e.cantidad}', textAlign: TextAlign.center, style: estiloNs(17, peso: FontWeight.w600, color: ns.ink))),
                  BotonCircularNs(icono: IconoNs.masMas, onTap: () => setState(() => e.cantidad++), etiqueta: 'Una más', tamanioIcono: 16),
                ],
              ),
            ),
          CampoNs(etiqueta: 'Agregar artículo', controller: _buscar, placeholder: 'Buscá por nombre', onChanged: (_) => setState(() {})),
          for (final p in _resultados)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: BotonNs(
                texto: '${p.nombre} · ${plataNs(p.precioCentavos ?? 0)}',
                onTap: () => setState(() {
                  _elegidos.add(_Elegido(p, 1));
                  _buscar.clear();
                }),
                alto: 48,
                tamanio: 14,
                fondo: ns.s,
                color: ns.ink,
                alineacion: Alignment.centerLeft,
                paddingH: 18,
              ),
            ),
          if (_buscar.text.trim().isNotEmpty && _resultados.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Sin coincidencias (por unidad, sin cigarrillos, con costo y precio)', style: estiloNs(13, color: ns.mute))),
          const SizedBox(height: 16),
          const SeccionNs('Ganancia (sobre el precio, a la centena)'),
          const SizedBox(height: 8),
          _SelectorPorcentaje(bp: _bp, onCambio: (v) => setState(() => _bp = v)),
          const SizedBox(height: 12),
          _Calculo(_calculo),
          const SizedBox(height: 12),
        ],
      ),
      botones: [
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar promo', _sePuedeGuardar && !_guardando ? _guardar : null, habilitado: _sePuedeGuardar && !_guardando),
      ],
    );
  }
}

class _PantallaSugerencias extends StatefulWidget {
  const _PantallaSugerencias({required this.db, this.clienteIa});
  final AppDatabase db;
  final http.Client? clienteIa;

  @override
  State<_PantallaSugerencias> createState() => _PantallaSugerenciasState();
}

class _PantallaSugerenciasState extends State<_PantallaSugerencias> {
  List<SugerenciaDePromo>? _sugerencias;
  List<TextoDePromo?> _textos = const [];
  bool _redactando = false;
  String? _avisoIa;
  final Map<int, int> _bpElegido = {};

  int _bpDe(int i) => _bpElegido[i] ?? _sugerencias![i].porcentajeBp;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final sugerencias = await sugerirPromos(widget.db);
    if (!mounted) return;
    setState(() => _sugerencias = sugerencias);
    if (sugerencias.isEmpty) return;
    if (!ClaveGemini.configurada) {
      setState(() => _avisoIa = 'Cargá la clave de la IA en Más › Configuración › Asistente IA para que les ponga nombre.');
      return;
    }
    setState(() => _redactando = true);
    final cliente = ClienteGemini.guardado(client: widget.clienteIa);
    try {
      final textos = await redactarPromos(cliente, sugerencias);
      if (mounted) setState(() => _textos = textos);
    } on ErrorGemini catch (e) {
      if (mounted) setState(() => _avisoIa = 'La IA no pudo ponerles nombre: ${e.mensaje}');
    } finally {
      cliente.close();
      if (mounted) setState(() => _redactando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final sugerencias = _sugerencias;
    return PaginaNs(
      titulo: 'Promos sugeridas',
      cuerpo: sugerencias == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                Text('Artículos que tus clientes ya se llevan juntos (últimos 90 días). Vos decidís cuáles crear.', style: estiloNs(15, altura: 1.4, color: ns.mute)),
                const SizedBox(height: 12),
                if (sugerencias.isEmpty)
                  const InfoNs('Todavía no hay nada para sugerir: hacen falta artículos que se vendan juntos al menos 2 veces, con stock, con costo cargado y con ganancia suficiente para descontar.'),
                if (_redactando) Text('Poniéndoles nombre con la IA…', style: estiloNs(14, color: ns.mute)),
                if (_avisoIa != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoNs(_avisoIa!, tamanio: 13, vertical: 10)),
                for (var i = 0; i < sugerencias.length; i++) _tarjeta(context, i, sugerencias[i]),
              ],
            ),
    );
  }

  Widget _tarjeta(BuildContext context, int i, SugerenciaDePromo s) {
    final ns = context.ns;
    final texto = i < _textos.length ? _textos[i] : null;
    final nombre = texto?.nombre ?? s.nombreSimple;
    final bp = _bpDe(i);
    final calculo = calcularPromo(s.componentes, bp);
    final cubre = calculo?.cubreElCosto ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(nombre, style: estiloNs(18, peso: FontWeight.w500, color: ns.ink)),
          if (texto != null) Text(s.nombreSimple, style: estiloNs(14, color: ns.mute)),
          Text('Se llevaron juntos en ${s.par.ventasJuntos} ventas (uno se vendió en ${s.par.ventasA} y el otro en ${s.par.ventasB}).',
              style: estiloNs(13, altura: 1.3, color: ns.mute)),
          if (texto != null && texto.motivo.isNotEmpty) Text('IA: ${texto.motivo}', style: estiloNs(13, altura: 1.3, color: ns.mute)),
          const SizedBox(height: 10),
          _SelectorPorcentaje(bp: bp, onCambio: (v) => setState(() => _bpElegido[i] = v)),
          const SizedBox(height: 8),
          _Calculo(calculo),
          const SizedBox(height: 8),
          BotonNs.primario(context, 'Crear esta promo', cubre ? () => Navigator.of(context).pop<_SugerenciaElegida>((sugerencia: s, nombre: nombre, bp: bp)) : null,
              habilitado: cubre, alto: 50, tamanio: 15),
        ],
      ),
    );
  }
}
