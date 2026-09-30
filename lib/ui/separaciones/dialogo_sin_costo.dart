// Qué producto se vendió sin costo cargado (El dueño, 2026-09-26: "que si hago
// click me diga el producto sin costo"). Se abre tocando el aviso "…sin
// costo cargado" de Separaciones, o la línea "incluye $X sin costo" de una
// tarjeta de "Lo vendido" (ahí, solo de ese proveedor).
//
// "Lenguaje de diseño" (mock `DialogosSeparaciones` → Productos sin
// costo): el costo se carga acá mismo, sin ir a Proveedores. Pasa por
// `cargarCostoProducto` → `actualizarProducto`, así que esas ventas lo toman
// solas (`completarCostoDeVentasSinCosto`) y queda en el historial de
// precios igual que editando el producto. El "costo sugerido" y "completar
// con estimado" del mock no están: un costo inventado se vería como real en
// la reposición y la ganancia, y avisar antes que inventar es la regla.
// "Varios" no tiene costo nunca (REGLAS-NEGOCIO.md): se lista, sin campo.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show cargarCostoProducto;
import '../../data/repositorio_reposicion.dart' show VendidoSinCosto, vendidoSinCostoDesde;
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoSinCosto(
  BuildContext context, {
  required AppDatabase db,
  required DateTime desde,
  required String periodo,
  required int usuarioId,
  String? soloProveedor,
  VoidCallback? alGuardar,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoSinCosto(
      db: db,
      desde: desde,
      periodo: periodo,
      usuarioId: usuarioId,
      soloProveedor: soloProveedor,
      alGuardar: alGuardar,
    ),
  );
}

class _DialogoSinCosto extends StatefulWidget {
  const _DialogoSinCosto({
    required this.db,
    required this.desde,
    required this.periodo,
    required this.usuarioId,
    this.soloProveedor,
    this.alGuardar,
  });

  final AppDatabase db;
  final DateTime desde;

  /// "hoy", "esta semana"… — para el título.
  final String periodo;
  final int usuarioId;

  /// Si viene, solo los de ese proveedor (la línea de una tarjeta).
  final String? soloProveedor;

  /// Para que Separaciones recalcule después de cargar costos.
  final VoidCallback? alGuardar;

  @override
  State<_DialogoSinCosto> createState() => _DialogoSinCostoState();
}

class _DialogoSinCostoState extends State<_DialogoSinCosto> {
  List<VendidoSinCosto>? _lista;

  /// Ids de productos "Varios": se muestran, pero sin campo de costo.
  Set<int> _varios = {};
  final Map<int, TextEditingController> _campos = {};
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final todos = await vendidoSinCostoDesde(widget.db, widget.desde);
    final lista = [
      for (final v in todos)
        if (widget.soloProveedor == null || v.proveedor == widget.soloProveedor) v,
    ];
    final varios = await (widget.db.select(widget.db.productos)..where((p) => p.esVarios.equals(true))).get();
    if (!mounted) return;
    setState(() {
      _lista = lista;
      _varios = {for (final p in varios) p.id};
      for (final v in lista) {
        if (v.productoId != null && !_varios.contains(v.productoId)) {
          _campos.putIfAbsent(v.productoId!, TextEditingController.new);
        }
      }
    });
  }

  Future<void> _guardar() async {
    final aGuardar = <int, int>{};
    for (final MapEntry(key: id, value: ctrl) in _campos.entries) {
      if (ctrl.text.trim().isEmpty) continue;
      try {
        final costo = parsearARS(ctrl.text);
        if (costo <= 0) throw const FormatException();
        aGuardar[id] = costo;
      } on FormatException {
        setState(() => _error = 'Revisá los costos: hay uno que no es un monto');
        return;
      }
    }
    if (aGuardar.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    for (final MapEntry(key: id, value: costo) in aGuardar.entries) {
      await cargarCostoProducto(widget.db, productoId: id, costoCentavos: costo, usuarioId: widget.usuarioId);
    }
    widget.alGuardar?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final lista = _lista;
    return Modal(
      titulo: widget.soloProveedor == null
          ? 'Vendido sin costo ${widget.periodo}'
          : '${widget.soloProveedor}: vendido sin costo ${widget.periodo}',
      subtitulo: 'Sin costo no se sabe cuánto separar',
      ancho: 620,
      contenido: lista == null
          ? const SizedBox(height: Medidas.alturaControl)
          : lista.isEmpty
          ? Text('No hay nada vendido sin costo.', style: TextStyle(color: colores.textoSecundario))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lista.length == 1
                      ? '1 producto vendido no tiene costo cargado: por ahora cuenta todo como ganancia.'
                      : '${lista.length} productos vendidos no tienen costo cargado: por ahora cuentan todo como ganancia.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: Espaciado.md),
                for (final v in lista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.producto, style: textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(
                                '${v.proveedor ?? 'Sin proveedor'} — ${v.gramos > 0 ? '${v.gramos} g' : '${v.cantidad} u.'} · vendido ${formatearARS(v.vendidoCentavos)}',
                                style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Espaciado.md),
                        SizedBox(
                          width: 170,
                          child: _campos[v.productoId] == null
                              ? Text(
                                  _varios.contains(v.productoId) ? 'Varios: sin costo' : 'Sin producto en el catálogo',
                                  textAlign: TextAlign.right,
                                  style: textTheme.bodySmall,
                                )
                              : CampoPlata(
                                  key: Key('costo_${v.productoId}'),
                                  controller: _campos[v.productoId]!,
                                  etiqueta: v.esPesable ? 'Costo por kilo' : 'Costo',
                                ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: Espaciado.sm),
                  Text(_error!, style: TextStyle(color: colores.error)),
                ],
              ],
            ),
      botones: [
        BotonSecundario(texto: 'Después', onPressed: () => Navigator.of(context).pop()),
        if (_campos.isNotEmpty) BotonPrimario(texto: _guardando ? 'Guardando…' : 'Guardar costos', onPressed: _guardando ? null : _guardar),
      ],
    );
  }
}
