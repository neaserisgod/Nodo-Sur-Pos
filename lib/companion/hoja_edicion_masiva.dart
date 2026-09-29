// Editor masivo de productos (Bruno, 2026-09-19: "editor masivo, ya sea de
// precios costo stock etc etc" — y después, sobre la primera versión: "las
// opciones que da no se correlacionan con el editor como tal"). La primera
// versión ofrecía un selector genérico de siete campos (precio, costo,
// stock, categoría, proveedor, activar, desactivar) sin importar desde
// dónde se abriera — nada ataba esas opciones a una razón real para usarlas.
//
// Rehecho alrededor de los tres casos reales que confirmó Bruno:
// - "Llegó un pedido de un proveedor" / "Un proveedor subió precios" →
//   `HojaEdicionMasiva.porProveedor`, con solo stock/precio/costo, abierta
//   desde el filtro "Por proveedor" de `pantalla_precios.dart` (ya viendo
//   los productos de ESE proveedor, no una selección arbitraria).
// - "Completar productos filtrados como sin X" → `.asignarProveedor` /
//   `.asignarCategoria`, sin selector de acción (una sola cosa para hacer),
//   abiertas desde los filtros "Sin proveedor"/"Sin categoría".
//
// "Activar"/"Desactivar" se sacaron: no correspondían a ninguno de los tres
// casos — copiados mecánicamente del editor masivo del escritorio
// (`dialogo_edicion_masiva.dart`) sin que nadie los pidiera para acá.
//
// Todo sigue pasando por `ServicioCompanion.ajustar*EnLote`/`asignar*EnLote`,
// que reusan el mismo repositorio en lote que el escritorio (Regla 3).

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../domain/edicion_masiva_precios.dart';
import '../domain/edicion_masiva_stock.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'tema/chip_seleccionable.dart';

enum _AccionMasiva { stock, precio, costo, categoria, proveedor }

class HojaEdicionMasiva extends StatefulWidget {
  /// "Llegó un pedido" / "un proveedor subió precios" — ya parados sobre los
  /// productos de ESE proveedor (`pantalla_precios.dart`, filtro "Por
  /// proveedor"), así que acá no hace falta elegir proveedor de nuevo.
  const HojaEdicionMasiva.porProveedor({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.productoIds,
    required String nombreProveedor,
  }) : _acciones = const {_AccionMasiva.stock, _AccionMasiva.precio, _AccionMasiva.costo},
       _titulo = 'Productos de $nombreProveedor',
       proveedores = const [],
       categorias = const [];

  /// Completar productos que salieron en el filtro "Sin proveedor" — una
  /// sola cosa para hacer, así que no hay selector de acción: se va directo
  /// al desplegable.
  const HojaEdicionMasiva.asignarProveedor({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.productoIds,
    required this.proveedores,
  }) : _acciones = const {_AccionMasiva.proveedor},
       _titulo = 'Asignar proveedor',
       categorias = const [];

  /// Mismo criterio que [asignarProveedor], para el filtro "Sin categoría".
  const HojaEdicionMasiva.asignarCategoria({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.productoIds,
    required this.categorias,
  }) : _acciones = const {_AccionMasiva.categoria},
       _titulo = 'Asignar categoría',
       proveedores = const [];

  final ServicioCompanion cliente;
  final int usuarioId;
  final List<int> productoIds;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;
  final Set<_AccionMasiva> _acciones;
  final String _titulo;

  @override
  State<HojaEdicionMasiva> createState() => _HojaEdicionMasivaState();
}

class _HojaEdicionMasivaState extends State<HojaEdicionMasiva> {
  late _AccionMasiva _accion = widget._acciones.first;
  TipoAjustePrecio _tipoMonto = TipoAjustePrecio.sumarPorcentaje;
  TipoAjusteStock _tipoStock = TipoAjusteStock.sumar;
  final _valorCtrl = TextEditingController();
  int? _categoriaElegida;
  int? _proveedorElegido;
  String? _error;
  bool _aplicando = false;

  /// `true` entre "Revisar" y "Sí, aplicar" — mismo paso intermedio que
  /// `dialogo_edicion_masiva.dart` del escritorio (Bruno, revisión de
  /// "errores humanos evitables"): antes "Aplicar" escribía DIRECTO sobre
  /// todos los productos marcados, sin ningún resumen ni techo de sanidad
  /// en el porcentaje — un dedo de más ("500" en vez de "50") multiplicaba
  /// precios x5 sin aviso.
  bool _revisando = false;

  /// Valor ya validado (centavos, unidades de stock, o basis points para un
  /// porcentaje) — calculado una sola vez en [_revisar], reusado en
  /// [_aplicar] para no volver a parsear el texto.
  int? _valorListo;

  bool get _esMonto => _accion == _AccionMasiva.precio || _accion == _AccionMasiva.costo;
  bool get _esPorcentaje =>
      _tipoMonto == TipoAjustePrecio.sumarPorcentaje || _tipoMonto == TipoAjustePrecio.restarPorcentaje;

  String get _etiquetaValorMonto => switch (_tipoMonto) {
    TipoAjustePrecio.nuevoFijo => 'Valor nuevo',
    TipoAjustePrecio.sumarMonto => 'Monto a sumar',
    TipoAjustePrecio.restarMonto => 'Monto a restar',
    TipoAjustePrecio.sumarPorcentaje => 'Porcentaje a sumar',
    TipoAjustePrecio.restarPorcentaje => 'Porcentaje a restar',
  };

  String get _etiquetaValorStock => switch (_tipoStock) {
    TipoAjusteStock.nuevoFijo => 'Stock nuevo',
    TipoAjusteStock.sumar => 'Unidades a sumar',
    TipoAjusteStock.restar => 'Unidades a restar',
  };

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  /// Valida el input y pasa al paso de revisión — nunca escribe nada
  /// todavía (ver [_revisando]).
  void _revisar() {
    setState(() => _error = null);
    switch (_accion) {
      case _AccionMasiva.precio:
      case _AccionMasiva.costo:
        if (_esPorcentaje) {
          final texto = _valorCtrl.text.trim().replaceAll(',', '.').replaceAll('%', '');
          final porcentaje = double.tryParse(texto);
          if (porcentaje == null || porcentaje < 0) {
            setState(() => _error = 'Porcentaje inválido');
            return;
          }
          _valorListo = (porcentaje * 100).round();
        } else {
          try {
            final monto = parsearARS(_valorCtrl.text);
            if (monto < 0) {
              setState(() => _error = 'El monto no puede ser negativo');
              return;
            }
            _valorListo = monto;
          } on FormatException {
            setState(() => _error = 'Monto inválido');
            return;
          }
        }
      case _AccionMasiva.stock:
        final valor = int.tryParse(_valorCtrl.text.trim());
        if (valor == null || valor < 0) {
          setState(() => _error = 'Valor inválido');
          return;
        }
        _valorListo = valor;
      case _AccionMasiva.categoria:
      case _AccionMasiva.proveedor:
        break; // nada que parsear
    }
    setState(() => _revisando = true);
  }

  Future<void> _aplicar() async {
    setState(() => _aplicando = true);
    try {
      switch (_accion) {
        case _AccionMasiva.precio:
        case _AccionMasiva.costo:
          await widget.cliente.ajustarMontoEnLote(
            productoIds: widget.productoIds,
            campo: _accion == _AccionMasiva.precio ? CampoMonto.precio : CampoMonto.costo,
            tipo: _tipoMonto,
            valor: _valorListo!,
            usuarioId: widget.usuarioId,
          );
        case _AccionMasiva.stock:
          await widget.cliente.ajustarStockEnLote(
            productoIds: widget.productoIds,
            tipo: _tipoStock,
            valor: _valorListo!,
            usuarioId: widget.usuarioId,
          );
        case _AccionMasiva.categoria:
          await widget.cliente.asignarCategoriaEnLote(
            productoIds: widget.productoIds,
            categoriaId: _categoriaElegida,
            usuarioId: widget.usuarioId,
          );
        case _AccionMasiva.proveedor:
          await widget.cliente.asignarProveedorEnLote(
            productoIds: widget.productoIds,
            proveedorId: _proveedorElegido,
            usuarioId: widget.usuarioId,
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _aplicando = false;
          _error = mensajeDeError(e);
        });
      }
    }
  }

  String _formatearPorcentaje(int basisPoints) {
    final valor = basisPoints / 100;
    return valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toStringAsFixed(2);
  }

  /// Frase de una línea con el cambio exacto — mismo criterio que el
  /// escritorio (`dialogo_edicion_masiva.dart::_resumenAccion`): el último
  /// paso antes de aplicar tiene que mostrar el número real, no obligar a
  /// acordarse de lo que se tipeó.
  String get _resumenAccion {
    switch (_accion) {
      case _AccionMasiva.precio:
      case _AccionMasiva.costo:
        final campo = _accion == _AccionMasiva.precio ? 'precio de venta' : 'costo';
        final valor = _valorListo!;
        return switch (_tipoMonto) {
          TipoAjustePrecio.nuevoFijo => 'Poner el $campo en ${formatearARS(valor)} fijo',
          TipoAjustePrecio.sumarMonto => 'Sumar ${formatearARS(valor)} al $campo',
          TipoAjustePrecio.restarMonto => 'Restar ${formatearARS(valor)} al $campo',
          TipoAjustePrecio.sumarPorcentaje => 'Sumar ${_formatearPorcentaje(valor)}% al $campo',
          TipoAjustePrecio.restarPorcentaje => 'Restar ${_formatearPorcentaje(valor)}% al $campo',
        };
      case _AccionMasiva.stock:
        final valor = _valorListo!;
        return switch (_tipoStock) {
          TipoAjusteStock.nuevoFijo => 'Poner el stock en $valor',
          TipoAjusteStock.sumar => 'Sumar $valor al stock',
          TipoAjusteStock.restar => 'Restar $valor al stock',
        };
      case _AccionMasiva.categoria:
        final nombre = _categoriaElegida == null
            ? 'sin categoría'
            : widget.categorias.firstWhere((c) => c.id == _categoriaElegida).nombre;
        return 'Poner la categoría en "$nombre"';
      case _AccionMasiva.proveedor:
        final nombre = _proveedorElegido == null
            ? 'sin proveedor'
            : widget.proveedores.firstWhere((p) => p.id == _proveedorElegido).nombre;
        return 'Poner el proveedor en "$nombre"';
    }
  }

  /// No bloquea — mismo criterio que el escritorio: un ajuste de 100%+
  /// puede ser real, pero es justo el rango donde un dígito de más pasa
  /// desapercibido.
  String? get _advertencia {
    if (!_esMonto || !_esPorcentaje || _valorListo == null || _valorListo! < 10000) {
      return null;
    }
    final porcentaje = _formatearPorcentaje(_valorListo!);
    return _tipoMonto == TipoAjustePrecio.restarPorcentaje
        ? 'Restar $porcentaje% deja el precio en \$0 en todos los productos marcados.'
        : 'Es un aumento de $porcentaje% — más del doble del valor actual. Revisá que no '
              'te haya sobrado un dígito o faltado el punto decimal (ej. "500" en vez de "50").';
  }

  @override
  Widget build(BuildContext context) {
    final cantidad = widget.productoIds.length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _revisando ? _contenidoRevision(context, cantidad) : _contenidoFormulario(context, cantidad),
        ),
      ),
    );
  }

  List<Widget> _contenidoFormulario(BuildContext context, int cantidad) {
    return [
      Text(widget._titulo, style: Theme.of(context).textTheme.titleLarge),
      Text(
        cantidad == 1 ? '1 producto seleccionado' : '$cantidad productos seleccionados',
        style: TextStyle(color: context.colores.textoSecundario),
      ),
      const SizedBox(height: Espaciado.md),
      // Con una sola acción posible (asignar proveedor/categoría desde
      // los filtros "Sin X") no hay nada que elegir — se va directo al
      // formulario de esa acción.
      if (widget._acciones.length > 1) ...[
        _selectorAccion(context),
        const SizedBox(height: Espaciado.md),
      ],
      ..._contenidoAccion(context),
      if (_error != null) ...[
        const SizedBox(height: Espaciado.sm),
        Text(_error!, style: TextStyle(color: context.colores.error)),
      ],
      const SizedBox(height: Espaciado.lg),
      FilledButton(onPressed: _revisar, child: const Text('Revisar')),
    ];
  }

  /// Paso intermedio antes de escribir en la base — ver [_revisando].
  List<Widget> _contenidoRevision(BuildContext context, int cantidad) {
    final colores = context.colores;
    final advertencia = _advertencia;
    return [
      Text(
        'Confirmar cambio a ${cantidad == 1 ? '1 producto' : '$cantidad productos'}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: Espaciado.md),
      Text('Vas a aplicar esto:', style: TextStyle(color: colores.textoSecundario)),
      const SizedBox(height: Espaciado.sm),
      Text(_resumenAccion, style: Theme.of(context).textTheme.titleMedium),
      if (advertencia != null) ...[
        const SizedBox(height: Espaciado.md),
        Container(
          padding: const EdgeInsets.all(Espaciado.md),
          decoration: BoxDecoration(
            color: colores.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(advertencia, style: TextStyle(color: colores.error, fontWeight: Pesos.medium)),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: Espaciado.sm),
        Text(_error!, style: TextStyle(color: colores.error)),
      ],
      const SizedBox(height: Espaciado.lg),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _aplicando ? null : () => setState(() => _revisando = false),
              child: const Text('Volver'),
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: FilledButton(
              onPressed: _aplicando ? null : _aplicar,
              child: _aplicando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sí, aplicar'),
            ),
          ),
        ],
      ),
    ];
  }

  static const _etiquetasAccion = {
    _AccionMasiva.stock: 'Recibí un pedido',
    _AccionMasiva.precio: 'Subió el precio',
    _AccionMasiva.costo: 'Subió el costo',
    _AccionMasiva.categoria: 'Categoría',
    _AccionMasiva.proveedor: 'Proveedor',
  };

  Widget _selectorAccion(BuildContext context) {
    return Wrap(
      spacing: Espaciado.sm,
      runSpacing: Espaciado.sm,
      children: [
        for (final accion in widget._acciones)
          ChipSeleccionable(
            texto: _etiquetasAccion[accion]!,
            seleccionado: _accion == accion,
            onTap: () => setState(() {
              _accion = accion;
              _error = null;
              _valorCtrl.clear();
            }),
          ),
      ],
    );
  }

  static const _etiquetasTipoMonto = {
    TipoAjustePrecio.sumarPorcentaje: 'Sumar %',
    TipoAjustePrecio.restarPorcentaje: 'Restar %',
    TipoAjustePrecio.sumarMonto: 'Sumar monto',
    TipoAjustePrecio.restarMonto: 'Restar monto',
    TipoAjustePrecio.nuevoFijo: 'Valor nuevo',
  };

  static const _etiquetasTipoStock = {
    TipoAjusteStock.sumar: 'Sumar',
    TipoAjusteStock.restar: 'Restar',
    TipoAjusteStock.nuevoFijo: 'Valor nuevo',
  };

  List<Widget> _contenidoAccion(BuildContext context) {
    final colores = context.colores;
    if (_esMonto) {
      return [
        Text(
          _accion == _AccionMasiva.precio
              ? 'Se aplica al precio de venta de cada producto marcado.'
              : 'Se aplica al costo de cada producto marcado — el precio de venta no se toca.',
          style: TextStyle(color: colores.textoSecundario),
        ),
        const SizedBox(height: Espaciado.md),
        Wrap(
          spacing: Espaciado.sm,
          runSpacing: Espaciado.sm,
          children: [
            for (final entrada in _etiquetasTipoMonto.entries)
              ChipSeleccionable(
                texto: entrada.value,
                seleccionado: _tipoMonto == entrada.key,
                onTap: () => setState(() => _tipoMonto = entrada.key),
              ),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        _esPorcentaje
            ? CampoTexto(
                controller: _valorCtrl,
                etiqueta: '$_etiquetaValorMonto (%)',
                autofocus: true,
              )
            : CampoPlata(controller: _valorCtrl, etiqueta: _etiquetaValorMonto, autofocus: true),
      ];
    }
    if (_accion == _AccionMasiva.stock) {
      return [
        Text(
          'Ajusta el stock de cada producto marcado — unidades, o gramos si es pesable. Deja rastro en movimientos de stock, igual que un ajuste uno por uno.',
          style: TextStyle(color: colores.textoSecundario),
        ),
        const SizedBox(height: Espaciado.md),
        Wrap(
          spacing: Espaciado.sm,
          runSpacing: Espaciado.sm,
          children: [
            for (final entrada in _etiquetasTipoStock.entries)
              ChipSeleccionable(
                texto: entrada.value,
                seleccionado: _tipoStock == entrada.key,
                onTap: () => setState(() => _tipoStock = entrada.key),
              ),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        CampoTexto(
          controller: _valorCtrl,
          etiqueta: _etiquetaValorStock,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
      ];
    }
    if (_accion == _AccionMasiva.categoria) {
      return [
        Text(
          'La categoría elegida reemplaza la actual en los productos marcados.',
          style: TextStyle(color: colores.textoSecundario),
        ),
        const SizedBox(height: Espaciado.md),
        DropdownButtonFormField<int?>(
          initialValue: _categoriaElegida,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin categoría')),
            for (final c in widget.categorias)
              DropdownMenuItem(value: c.id, child: Text(c.nombre, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _categoriaElegida = v),
        ),
      ];
    }
    // _AccionMasiva.proveedor
    return [
      Text(
        'El proveedor elegido reemplaza el actual en los productos marcados.',
        style: TextStyle(color: colores.textoSecundario),
      ),
      const SizedBox(height: Espaciado.md),
      DropdownButtonFormField<int?>(
        initialValue: _proveedorElegido,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Proveedor'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
          for (final p in widget.proveedores)
            DropdownMenuItem(
              value: p.id,
              child: Text('${p.codigo} — ${p.nombre}', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _proveedorElegido = v),
      ),
    ];
  }
}
