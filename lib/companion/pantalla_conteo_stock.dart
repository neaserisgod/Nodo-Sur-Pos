// Conteo de stock, tal cual el mock (docs/03 C3): se abre ya parado sobre un
// proveedor (o sobre "Productos sin stock"), con el avance arriba, una fila por
// producto con lo guardado y un campo para lo que hay, y el botón flotante de
// guardar. Un campo vacío NO toca el stock; lo cargado se guarda con su rastro
// ("Conteo físico") y recién ahí se limpia.

import 'package:flutter/material.dart';

import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';

class PantallaConteoStock extends StatefulWidget {
  /// [proveedorId] null y [soloSinStock] false = todos los productos juntos.
  const PantallaConteoStock({super.key, this.proveedorId, this.soloSinStock = false});

  final int? proveedorId;
  final bool soloSinStock;

  @override
  State<PantallaConteoStock> createState() => _PantallaConteoStockState();
}

class _PantallaConteoStockState extends State<PantallaConteoStock> {
  ServicioCompanion? _servicio;
  int? _usuarioId;
  List<ProveedorCompanion> _proveedores = [];
  List<ProductoCompanion> _productos = [];
  Set<int> _sinStockIds = {};
  final Map<int, TextEditingController> _controladores = {};
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  int get _contados => _controladores.values.where((c) => c.text.trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final conexion = await leerConexion();
      final usuario = await leerUsuario();
      if (usuario == null) throw const ErrorCompanion(0, 'Falta elegir usuario.');
      final servicio = conexion == null ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion())) : await resolverServicioCompanion(conexion);
      if (!mounted) return;
      _servicio = servicio;
      _usuarioId = usuario.id;
      await _cargarCatalogo();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarCatalogo() async {
    final s = _servicio!;
    final r = await Future.wait([s.proveedores(), s.productos(), s.productosSinStock()]);
    final productos = r[1] as List<ProductoCompanion>;
    for (final p in productos) {
      _controladores.putIfAbsent(p.id, () => TextEditingController()..addListener(() => mounted ? setState(() {}) : null));
    }
    if (!mounted) return;
    setState(() {
      _proveedores = r[0] as List<ProveedorCompanion>;
      _productos = productos;
      _sinStockIds = {for (final p in r[2] as List<ProductoCompanion>) p.id};
    });
  }

  List<ProductoCompanion> get _visibles => [
    for (final p in _productos)
      if ((widget.proveedorId == null || p.proveedorId == widget.proveedorId) && (!widget.soloSinStock || _sinStockIds.contains(p.id))) p,
  ];

  ProveedorCompanion? get _proveedor => _proveedores.where((p) => p.id == widget.proveedorId).firstOrNull;

  /// Lo guardado en la unidad del producto (unidades o gramos).
  int _guardado(ProductoCompanion p) => p.esPesable ? (p.stockGramos ?? 0) : p.stock;

  Future<void> _guardar() async {
    final cuantos = _contados;
    if (cuantos == 0) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final errores = <String>[];
    final ok = <int>{};
    for (final p in _visibles) {
      final texto = _controladores[p.id]?.text.trim() ?? '';
      if (texto.isEmpty) continue;
      final valor = int.tryParse(texto);
      if (valor == null || valor < 0) {
        errores.add('${p.nombre}: número inválido');
        continue;
      }
      try {
        await _servicio!.ajustarStock(p.id, stock: p.esPesable ? p.stock : valor, stockGramos: p.esPesable ? valor : null, motivo: 'Conteo físico', usuarioId: _usuarioId!);
        ok.add(p.id);
      } catch (e) {
        errores.add('${p.nombre}: ${mensajeDeError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    mostrarAvisoNs(
      context,
      errores.isEmpty ? 'Guardado: ${ok.length} ${ok.length == 1 ? 'producto actualizado' : 'productos actualizados'}' : '${ok.length} guardado(s), con errores: ${errores.join('; ')}',
      largo: true,
    );
    if (ok.isNotEmpty) {
      for (final id in ok) {
        _controladores[id]?.clear();
      }
      try {
        await _cargarCatalogo();
      } catch (e) {
        if (mounted) setState(() => _error = mensajeDeError(e));
      }
    }
  }

  Future<void> _volver() async {
    if (_contados == 0 || await confirmarSalirSinGuardar(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final visibles = _visibles;
    final titulo = widget.soloSinStock ? 'Productos sin stock' : (_proveedor?.nombre ?? 'Todos los productos');
    final subtitulo = widget.soloSinStock || widget.proveedorId == null
        ? 'Todos los proveedores juntos · ${visibles.length} ${visibles.length == 1 ? 'producto' : 'productos'}'
        : '${visibles.length} ${visibles.length == 1 ? 'producto' : 'productos'} · lo que dejes vacío no se toca';
    final contadosVisibles = visibles.where((p) => (_controladores[p.id]?.text.trim() ?? '').isNotEmpty).length;
    final cuantos = _contados;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _volver();
      },
      child: Scaffold(
        backgroundColor: ns.paper,
        body: SafeArea(
          child: PantallaEntradaNs(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          BotonCircularNs(icono: IconoNs.volver, onTap: _volver, etiqueta: 'Volver', tamanioIcono: 18, grosor: 2.4),
                          const Spacer(),
                          if (!widget.soloSinStock && _proveedor != null) Text(_proveedor!.codigo.toUpperCase(), style: estiloNs(14, peso: FontWeight.w700, track: 0.04, color: ns.mute)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(titulo, style: tituloNs(38, altura: 1.02, color: ns.ink)),
                      const SizedBox(height: 4),
                      Text(subtitulo, style: estiloNs(15, color: ns.mute)),
                      if (visibles.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: Container(
                                  height: 8,
                                  color: ns.s2,
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedFractionallySizedBox(
                                    duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 400),
                                    curve: curvaNs,
                                    widthFactor: (contadosVisibles / visibles.length).clamp(0.0, 1.0),
                                    child: Container(color: ns.prim),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('$contadosVisibles de ${visibles.length} contados', style: estiloNs(13, peso: FontWeight.w700, color: ns.ink, tabular: true)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      Expanded(
                        child: _cargando
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                            : _servicio == null
                            ? InfoNs(_error ?? 'No se pudo conectar.', tono: TonoNs.bad)
                            : visibles.isEmpty
                            ? const Center(child: EstadoVacioNs(texto: 'Nada sin stock: todo contado'))
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 112),
                                itemCount: visibles.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, i) => _FilaConteo(key: ValueKey('conteo:${visibles[i].nombre}'), producto: visibles[i], guardado: _guardado(visibles[i]), controller: _controladores[visibles[i].id]!),
                              ),
                      ),
                    ],
                  ),
                ),
                if (_error != null && _servicio != null) Positioned(left: margenNs, right: margenNs, bottom: 92, child: InfoNs(_error!, tono: TonoNs.bad)),
                if (visibles.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: PresionNs(
                      onTap: cuantos == 0 || _guardando ? null : _guardar,
                      etiqueta: 'Guardar conteo',
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: cuantos == 0 ? ns.s2 : ns.prim,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: cuantos == 0 ? null : const [BoxShadow(color: Color(0x47121317), blurRadius: 40, offset: Offset(0, 18))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconoNsWidget(IconoNs.guardar, tamanio: 22, color: cuantos == 0 ? ns.mute : TokensNs.blanco),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _guardando ? 'Guardando…' : (cuantos == 0 ? 'Guardar conteo' : 'Guardar conteo ($cuantos de ${visibles.length})'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: estiloNs(17, peso: FontWeight.w600, color: cuantos == 0 ? ns.mute : TokensNs.blanco),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaConteo extends StatelessWidget {
  const _FilaConteo({super.key, required this.producto, required this.guardado, required this.controller});
  final ProductoCompanion producto;
  final int guardado;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final p = producto;
    final unidad = p.esPesable ? 'g' : 'u.';
    final texto = controller.text.trim();
    final valor = int.tryParse(texto);
    final vacio = texto.isEmpty;
    final invalido = !vacio && (valor == null || valor < 0);
    final diferencia = valor == null ? 0 : valor - guardado;
    String? nota;
    Color? colorNota;
    if (invalido) {
      nota = 'Número inválido';
      colorNota = ns.b;
    } else if (!vacio) {
      if (diferencia == 0) {
        nota = 'Coincide con lo guardado';
        colorNota = ns.mute;
      } else {
        nota = '${diferencia > 0 ? '+' : '−'}${diferencia.abs()} $unidad de diferencia';
        colorNota = diferencia > 0 ? ns.g : ns.b;
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, style: estiloNs(16, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                Text('Guardado: $guardado${p.esPesable ? ' g' : ' u.'}', style: estiloNs(14, color: ns.mute, tabular: true)),
                if (nota != null) Text(nota, style: estiloNs(13, peso: FontWeight.w700, color: colorNota, tabular: true)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 96,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: vacio ? ns.paper : (invalido ? ns.bbg : ns.prim),
              borderRadius: BorderRadius.circular(999),
              border: vacio ? Border.all(color: ns.line, width: 1.5) : null,
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              cursorColor: vacio ? ns.ink : TokensNs.blanco,
              style: estiloNs(18, peso: FontWeight.w600, color: invalido ? ns.b : (vacio ? ns.ink : TokensNs.blanco), tabular: true),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: p.esPesable ? 'Gramos' : 'Unidades',
                hintStyle: estiloNs(14, peso: FontWeight.w500, color: ns.mute),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Está igual que lo guardado',
            child: PresionNs(
              onTap: () => controller.text = '$guardado',
              etiqueta: 'Está igual que lo guardado',
              child: Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.gbg, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(IconoNs.tilde, tamanio: 20, color: ns.g, grosor: 2.6)),
            ),
          ),
        ],
      ),
    );
  }
}
