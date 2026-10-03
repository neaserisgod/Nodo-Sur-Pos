// Encargues en el celular (El dueño, 2026-10-02): lo que un cliente pidió y ya está en el local, apartado hasta que lo
// retire. Mismas reglas que la PC (`repositorio_encargues.dart`) a través del servicio, así que anda igual con la PC
// por wifi que sin ella. Apartar saca el stock ya; "Entregar" vuelve al menú con lo apartado para abrir el carrito;
// "Cancelar" lo devuelve al stock.

import 'package:flutter/material.dart';

import '../ui/comun/estado_vacio.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart' show ApartadoCompanion, EncargueCompanion, ProductoCompanion;
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'servicio_companion.dart';
import 'tema/app_bar_companion.dart';
import 'tema/superficie.dart';
import 'tema/hoja_vidrio.dart';

/// Lo que devuelve la pantalla al elegir "Entregar": el menú arma el carrito con esto.
class EntregaEncargue {
  const EntregaEncargue(this.id);
  final int id;
}

class PantallaEncarguesCompanion extends StatefulWidget {
  const PantallaEncarguesCompanion({super.key, required this.servicio, required this.usuarioId, this.hayVentaArmada = false});

  final ServicioCompanion servicio;
  final int usuarioId;

  /// El celular tiene un solo carrito: con una venta armada no se puede abrir otra para entregar.
  final bool hayVentaArmada;

  @override
  State<PantallaEncarguesCompanion> createState() => _PantallaEncarguesCompanionState();
}

class _PantallaEncarguesCompanionState extends State<PantallaEncarguesCompanion> {
  List<EncargueCompanion> _encargues = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.servicio.encargues();
      if (mounted) setState(() => _encargues = lista);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final creado = await pushSinTeclado<bool>(
      context,
      (_) => _PantallaNuevoEncargue(servicio: widget.servicio, usuarioId: widget.usuarioId),
    );
    if (creado == true) await _cargar();
  }

  Future<void> _cancelar(EncargueCompanion e) async {
    final confirmar = await confirmarAccionDestructiva(
      context,
      titulo: '¿Cancelar el encargue de ${e.nombreCliente}?',
      contenido: 'Lo apartado vuelve al stock.',
      textoConfirmar: 'Cancelar encargue',
    );
    if (!confirmar) return;
    try {
      await widget.servicio.cancelarEncargue(e.id, usuarioId: widget.usuarioId);
      await _cargar();
    } catch (err) {
      if (mounted) setState(() => _error = mensajeDeError(err));
    }
  }

  void _entregar(EncargueCompanion e) {
    if (widget.hayVentaArmada) {
      setState(() => _error = 'Hay una venta armada: cobrala o vaciala antes de entregar un encargue.');
      return;
    }
    Navigator.of(context).pop(EntregaEncargue(e.id));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    return Scaffold(
      appBar: const AppBarCompanion(titulo: 'Encargues'),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
                children: [
                  FilledButton(
                    key: const Key('encargue_nuevo'),
                    style: FilledButton.styleFrom(minimumSize: const Size(128, 56)),
                    onPressed: _nuevo,
                    child: const Text('Nuevo encargue'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Espaciado.md),
                      child: Text(_error!, key: const Key('encargues_error'), style: textTheme.bodyMedium?.copyWith(color: colores.error)),
                    ),
                  const SizedBox(height: Espaciado.lg),
                  if (_encargues.isEmpty)
                    const SizedBox(height: 320, child: EstadoVacio(mensaje: 'No hay encargues pendientes.'))
                  else
                    for (final e in _encargues)
                      Padding(
                        key: Key('encargue_${e.id}'),
                        padding: const EdgeInsets.only(bottom: Espaciado.md),
                        child: Superficie(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(e.nombreCliente, style: textTheme.titleMedium)),
                                  Text('desde el ${e.desde.day}/${e.desde.month}', style: textTheme.bodySmall),
                                ],
                              ),
                              const SizedBox(height: Espaciado.sm),
                              for (final l in e.lineas) Text(l, style: textTheme.bodyMedium),
                              const SizedBox(height: Espaciado.md),
                              // Mitad y mitad: con botones de ancho propio, el tema (que estira los botones) desbordaba el renglón.
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                                      onPressed: () => _cancelar(e),
                                      child: Text('Cancelar', style: TextStyle(color: colores.error)),
                                    ),
                                  ),
                                  const SizedBox(width: Espaciado.md),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                                      onPressed: () => _entregar(e),
                                      child: const Text('Entregar'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

/// Alta: nombre del cliente y los productos a apartar (solo con stock; unidades, o gramos si es pesable).
class _PantallaNuevoEncargue extends StatefulWidget {
  const _PantallaNuevoEncargue({required this.servicio, required this.usuarioId});

  final ServicioCompanion servicio;
  final int usuarioId;

  @override
  State<_PantallaNuevoEncargue> createState() => _PantallaNuevoEncargueState();
}

class _PantallaNuevoEncargueState extends State<_PantallaNuevoEncargue> {
  final _nombre = TextEditingController();
  final _buscador = TextEditingController();
  List<ProductoCompanion> _resultados = const [];
  final List<({ProductoCompanion producto, int cantidad})> _elegidos = [];
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() => _resultados = const []);
      return;
    }
    try {
      final r = await widget.servicio.buscarVenta(texto);
      final yaElegidos = {for (final e in _elegidos) e.producto.id};
      if (mounted) setState(() => _resultados = r.resultados.where((p) => !yaElegidos.contains(p.id)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _elegir(ProductoCompanion p) async {
    final ctrl = TextEditingController(text: p.esPesable ? '' : '1');
    final cantidad = await mostrarHojaVidrio<int>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.esPesable ? 'Gramos de ${p.nombre}' : 'Cantidad de ${p.nombre}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Espaciado.md),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (t) => Navigator.of(context).pop(int.tryParse(t)),
          ),
          const SizedBox(height: Espaciado.lg),
          FilledButton(onPressed: () => Navigator.of(context).pop(int.tryParse(ctrl.text)), child: const Text('Agregar')),
        ],
      ),
    );
    if (cantidad == null || cantidad <= 0) return;
    setState(() {
      _elegidos.add((producto: p, cantidad: cantidad));
      _buscador.clear();
      _resultados = const [];
      _error = null;
    });
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.crearEncargue(
        nombreCliente: _nombre.text,
        lineas: [
          for (final e in _elegidos)
            ApartadoCompanion(
              productoId: e.producto.id,
              cantidad: e.producto.esPesable ? null : e.cantidad,
              gramos: e.producto.esPesable ? e.cantidad : null,
            ),
        ],
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const AppBarCompanion(titulo: 'Nuevo encargue'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
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
              onChanged: _buscar,
            ),
            for (final p in _resultados)
              ListTile(
                key: Key('encargue_opcion_${p.id}'),
                title: Text(p.nombre),
                subtitle: Text(p.esPesable ? '${p.stockGramos ?? 0} g en stock' : '${p.stock} en stock'),
                onTap: () => _elegir(p),
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
                      style: textTheme.bodyLarge,
                    ),
                  ),
                  IconButton(tooltip: 'Sacar', icon: const Icon(Icons.close), onPressed: () => setState(() => _elegidos.removeAt(i))),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Espaciado.sm),
                child: Text(_error!, key: const Key('encargue_error'), style: textTheme.bodyMedium?.copyWith(color: context.colores.error)),
              ),
            const SizedBox(height: Espaciado.lg),
            FilledButton(
              key: const Key('encargue_apartar'),
              style: FilledButton.styleFrom(minimumSize: const Size(128, 56)),
              onPressed: _guardando || _elegidos.isEmpty ? null : _guardar,
              child: const Text('Apartar'),
            ),
          ],
        ),
      ),
    );
  }
}
