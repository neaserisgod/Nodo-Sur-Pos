// Alta de un encargue: nombre del cliente y los productos a apartar. Solo productos con stock (se aparta lo que está), y
// por cada uno unidades o, si es pesable, gramos. Cargar el catálogo entero acá no pesa: se abre pocas veces por día.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../data/repositorio_encargues.dart';
import '../../data/repositorio_productos.dart' show listarProductos;
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';

/// `true` si se creó el encargue.
Future<bool?> mostrarDialogoNuevoEncargue(BuildContext context, {required AppDatabase db, required int usuarioId}) async {
  final catalogo = (await listarProductos(db)).where(tieneStock).toList();
  if (!context.mounted) return null;
  return mostrarModal<bool>(
    context,
    builder: (_) => _DialogoNuevoEncargue(db: db, usuarioId: usuarioId, catalogo: catalogo),
  );
}

class _DialogoNuevoEncargue extends StatefulWidget {
  const _DialogoNuevoEncargue({required this.db, required this.usuarioId, required this.catalogo});

  final AppDatabase db;
  final int usuarioId;
  final List<Producto> catalogo;

  @override
  State<_DialogoNuevoEncargue> createState() => _DialogoNuevoEncargueState();
}

class _DialogoNuevoEncargueState extends State<_DialogoNuevoEncargue> {
  final _nombre = TextEditingController();
  final _buscador = TextEditingController();

  /// Lo elegido hasta ahora: producto y cantidad (unidades, o gramos si es pesable).
  final List<({Producto producto, int cantidad})> _elegidos = [];
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _buscador.dispose();
    super.dispose();
  }

  List<Producto> get _coincidencias {
    final yaElegidos = {for (final e in _elegidos) e.producto.id};
    return buscarProductos(catalogo: widget.catalogo, textoBuscado: _buscador.text, limite: 6)
        .where((p) => !yaElegidos.contains(p.id))
        .toList();
  }

  Future<void> _agregar(Producto p) async {
    final cantidad = await _pedirCantidad(p);
    if (cantidad == null) return;
    setState(() {
      _elegidos.add((producto: p, cantidad: cantidad));
      _buscador.clear();
      _error = null;
    });
  }

  Future<int?> _pedirCantidad(Producto p) {
    final ctrl = TextEditingController(text: p.esPesable ? '' : '1');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(p.esPesable ? 'Gramos de ${p.nombre}' : 'Cantidad de ${p.nombre}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (t) => Navigator.of(context).pop(int.tryParse(t)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(int.tryParse(ctrl.text)), child: const Text('Agregar')),
        ],
      ),
    ).then((v) => v == null || v <= 0 ? null : v);
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await crearEncargueApartando(
        widget.db,
        nombreCliente: _nombre.text,
        lineas: [
          for (final e in _elegidos)
            LineaEncargueNueva(
              productoId: e.producto.id,
              cantidad: e.producto.esPesable ? null : e.cantidad,
              gramos: e.producto.esPesable ? e.cantidad : null,
            ),
        ],
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on EncargueSinStock catch (e) {
      setState(() => _error = 'No alcanza el stock de ${e.nombreProducto}.');
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final coincidencias = _coincidencias;
    return Modal(
      titulo: 'Nuevo encargue',
      subtitulo: 'Lo que se aparta sale del stock ahora',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('encargue_nombre'),
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Cliente'),
          ),
          const SizedBox(height: Espaciado.md),
          TextField(
            key: const Key('encargue_buscador'),
            controller: _buscador,
            decoration: const InputDecoration(labelText: 'Buscar producto para apartar'),
            onChanged: (_) => setState(() {}),
          ),
          for (final p in coincidencias)
            ListTile(
              key: Key('encargue_opcion_${p.id}'),
              dense: true,
              title: Text(p.nombre),
              subtitle: Text(p.esPesable ? '${p.stockGramos ?? 0} g en stock' : '${p.stock} en stock'),
              onTap: () => _agregar(p),
            ),
          const SizedBox(height: Espaciado.md),
          for (var i = 0; i < _elegidos.length; i++)
            Row(
              key: Key('encargue_elegido_$i'),
              children: [
                Expanded(
                  child: Text(
                    _elegidos[i].producto.esPesable
                        ? '${_elegidos[i].cantidad} g ${_elegidos[i].producto.nombre}'
                        : '${_elegidos[i].cantidad} × ${_elegidos[i].producto.nombre}',
                  ),
                ),
                IconButton(
                  tooltip: 'Sacar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _elegidos.removeAt(i)),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Espaciado.sm),
              child: Text(_error!, key: const Key('encargue_error'), style: textTheme.bodyMedium?.copyWith(color: context.colores.error)),
            ),
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
        BotonPrimario(texto: 'Apartar', onPressed: _guardando || _elegidos.isEmpty ? null : _guardar),
      ],
    );
  }
}
