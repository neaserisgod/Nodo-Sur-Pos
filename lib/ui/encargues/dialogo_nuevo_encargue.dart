// Alta de un encargue: nombre del cliente y los productos a apartar. Solo productos con stock (se aparta lo que está), y
// por cada uno unidades o, si es pesable, gramos. Cargar el catálogo entero acá no pesa: se abre pocas veces por día.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../data/repositorio_encargues.dart';
import '../../data/repositorio_productos.dart' show listarProductos;
import '../../data/repositorio_ventas.dart' show SesionCerradaException;
import '../../domain/dinero.dart' show parsearARS;
import '../comun/botones.dart';
import '../comun/campo_texto.dart' show CampoPlata;
import '../comun/modal.dart';
import '../comun/tarjetas.dart' show ChipAtajo;
import '../tema/tokens.dart';

/// `true` si se creó el encargue.
///
/// [sesionCajaId]: la caja abierta; sin ella no se puede tomar una seña (la plata tiene que entrar a una caja).
Future<bool?> mostrarDialogoNuevoEncargue(BuildContext context, {required AppDatabase db, required int usuarioId, int? sesionCajaId}) async {
  final catalogo = (await listarProductos(db)).where(tieneStock).toList();
  if (!context.mounted) return null;
  return mostrarModal<bool>(
    context,
    builder: (_) => _DialogoNuevoEncargue(db: db, usuarioId: usuarioId, sesionCajaId: sesionCajaId, catalogo: catalogo),
  );
}

class _DialogoNuevoEncargue extends StatefulWidget {
  const _DialogoNuevoEncargue({required this.db, required this.usuarioId, required this.catalogo, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;
  final List<Producto> catalogo;

  @override
  State<_DialogoNuevoEncargue> createState() => _DialogoNuevoEncargueState();
}

class _DialogoNuevoEncargueState extends State<_DialogoNuevoEncargue> {
  final _nombre = TextEditingController();
  final _buscador = TextEditingController();
  final _sena = TextEditingController();

  /// Por qué caja entra la seña: true = cajón (efectivo), false = Mercado Pago.
  bool _senaEnEfectivo = true;

  /// Lo elegido hasta ahora: producto y cantidad (unidades, o gramos si es pesable).
  final List<({Producto producto, int cantidad})> _elegidos = [];
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _buscador.dispose();
    _sena.dispose();
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
      builder: (context) => Modal(
        titulo: p.esPesable ? 'Gramos de ${p.nombre}' : 'Cantidad de ${p.nombre}',
        contenido: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (t) => Navigator.of(context).pop(int.tryParse(t)),
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Agregar', onPressed: () => Navigator.of(context).pop(int.tryParse(ctrl.text))),
        ],
      ),
    ).then((v) => v == null || v <= 0 ? null : v);
  }

  int get _senaCentavos => _sena.text.trim().isEmpty ? 0 : parsearARS(_sena.text);

  Future<void> _guardar() async {
    final int sena;
    try {
      sena = _senaCentavos;
    } on FormatException {
      setState(() => _error = 'La seña no es un monto válido.');
      return;
    }
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
        senaCentavos: sena,
        senaEsEfectivo: _senaEnEfectivo,
        sesionCajaId: widget.sesionCajaId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on EncargueSinStock catch (e) {
      setState(() => _error = 'No alcanza el stock de ${e.nombreProducto}.');
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    } on SesionCerradaException {
      setState(() => _error = 'La caja ya se cerró: abrila de nuevo para tomar la seña.');
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
          const SizedBox(height: Espaciado.md),
          if (widget.sesionCajaId == null)
            Text(
              'Para tomar una seña hay que abrir la caja: la plata entra a la caja.',
              key: const Key('encargue_sena_sin_caja'),
              style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
            )
          else ...[
            CampoPlata(key: const Key('encargue_sena'), controller: _sena, etiqueta: 'Seña (opcional)', onChanged: (_) => setState(() {})),
            const SizedBox(height: Espaciado.sm),
            Wrap(
              spacing: Espaciado.sm,
              children: [
                ChipAtajo(key: const Key('encargue_sena_efectivo'), texto: 'Efectivo', elegido: _senaEnEfectivo, onTap: () => setState(() => _senaEnEfectivo = true)),
                ChipAtajo(key: const Key('encargue_sena_mp'), texto: 'Mercado Pago', elegido: !_senaEnEfectivo, onTap: () => setState(() => _senaEnEfectivo = false)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: Espaciado.xs),
              child: Text(
                'Entra a la caja ahora, no es una venta. Al entregar se descuenta; si se cancela, se devuelve.',
                style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
              ),
            ),
          ],
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
