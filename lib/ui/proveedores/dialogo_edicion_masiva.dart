// Edición masiva de productos (El dueño, 2026-09-16: "si quiero subir el
// precio de 3 productos... a la vez", y después "maximizá lo que se puede
// hacer con el ajuste masivo" — precio, costo, categoría, proveedor,
// activar/desactivar). Una sola acción a la vez, elegida arriba; el resto
// del diálogo cambia según cuál. Todo pasa por
// `ProveedoresControlador.aplicar*Masivo`, que reusa `actualizarProducto`/
// `cambiarActivo` producto por producto (Regla 3: el historial de precios y
// cualquier otro efecto secundario quedan idénticos a editar uno por uno).

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../domain/edicion_masiva_precios.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../../data/repositorio_reposicion.dart' show ProductoDeProveedor;
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';

Future<void> mostrarDialogoEdicionMasiva(
  BuildContext context, {
  required ProveedoresControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoEdicionMasiva(controlador: controlador),
  );
}

enum _AccionMasiva { precio, costo, categoria, proveedor, activar, desactivar }

class _DialogoEdicionMasiva extends StatefulWidget {
  const _DialogoEdicionMasiva({required this.controlador});

  final ProveedoresControlador controlador;

  @override
  State<_DialogoEdicionMasiva> createState() => _DialogoEdicionMasivaState();
}

class _DialogoEdicionMasivaState extends State<_DialogoEdicionMasiva> {
  _AccionMasiva _accion = _AccionMasiva.precio;
  TipoAjustePrecio _tipoMonto = TipoAjustePrecio.sumarPorcentaje;
  final _valorCtrl = TextEditingController();
  int? _categoriaElegida;
  int? _proveedorElegido;
  bool _proveedorInicializado = false;
  String? _error;
  bool _aplicando = false;

  /// `true` entre "Revisar" y "Sí, aplicar" — un paso intermedio que antes
  /// no existía (bug real: Enter en el campo de valor aplicaba DIRECTO,
  /// sin mostrar a cuántos productos ni con qué número, y el porcentaje no
  /// tenía techo: escribir "500" en vez de "50" — un dedo de más, o el
  /// punto decimal que faltó — multiplicaba precios x5 en TODO lo marcado,
  /// sin aviso y sin un botón de deshacer).
  bool _revisando = false;

  /// Valor ya validado y listo para aplicar (centavos, o basis points para
  /// un porcentaje — `valor / 100` es el porcentaje que se le mostró a la
  /// persona). Se calcula una sola vez en [_revisar] para no volver a
  /// parsear el texto (y arriesgarse a que diga algo distinto) en [_aplicar].
  int? _valorListo;

  bool get _esMonto =>
      _accion == _AccionMasiva.precio || _accion == _AccionMasiva.costo;
  bool get _esPorcentaje =>
      _tipoMonto == TipoAjustePrecio.sumarPorcentaje ||
      _tipoMonto == TipoAjustePrecio.restarPorcentaje;

  String get _etiquetaValorMonto => switch (_tipoMonto) {
    TipoAjustePrecio.nuevoFijo => 'Valor nuevo',
    TipoAjustePrecio.sumarMonto => 'Monto a sumar',
    TipoAjustePrecio.restarMonto => 'Monto a restar',
    TipoAjustePrecio.sumarPorcentaje => 'Porcentaje a sumar',
    TipoAjustePrecio.restarPorcentaje => 'Porcentaje a restar',
  };

  /// Valida el input y pasa al paso de revisión — nunca escribe nada en la
  /// base todavía. Separado de [_aplicar] a propósito (ver [_revisando]).
  void _revisar() {
    setState(() => _error = null);
    if (_esMonto) {
      if (_esPorcentaje) {
        final texto = _valorCtrl.text
            .trim()
            .replaceAll(',', '.')
            .replaceAll('%', '');
        final porcentaje = double.tryParse(texto);
        if (porcentaje == null || porcentaje < 0) {
          setState(() => _error = 'Porcentaje inválido');
          return;
        }
        _valorListo = (porcentaje * 100).round();
      } else {
        final int monto;
        try {
          monto = parsearARS(_valorCtrl.text);
        } on FormatException {
          setState(() => _error = 'Monto inválido');
          return;
        }
        if (monto < 0) {
          setState(() => _error = 'El monto no puede ser negativo');
          return;
        }
        _valorListo = monto;
      }
    }
    setState(() => _revisando = true);
  }

  Future<void> _aplicar() async {
    setState(() => _aplicando = true);
    switch (_accion) {
      case _AccionMasiva.precio:
      case _AccionMasiva.costo:
        await widget.controlador.aplicarAjusteMontoMasivo(
          campo: _accion == _AccionMasiva.precio
              ? CampoMonto.precio
              : CampoMonto.costo,
          tipo: _tipoMonto,
          valor: _valorListo!,
        );
      case _AccionMasiva.categoria:
        await widget.controlador.aplicarCategoriaMasiva(_categoriaElegida);
      case _AccionMasiva.proveedor:
        await widget.controlador.aplicarProveedorMasivo(_proveedorElegido);
      case _AccionMasiva.activar:
        await widget.controlador.aplicarActivoMasivo(true);
      case _AccionMasiva.desactivar:
        await widget.controlador.aplicarActivoMasivo(false);
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _formatearPorcentaje(int basisPoints) {
    final valor = basisPoints / 100;
    return valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
  }

  /// Frase de una línea con el cambio exacto que se va a aplicar — mismo
  /// número que se ve en el botón de confirmar, a propósito (El dueño: "a
  /// prueba de boludos" — el último click tiene que mostrar el número
  /// real, no obligar a acordarse de lo que se tipeó tres pantallas atrás).
  String get _resumenAccion {
    switch (_accion) {
      case _AccionMasiva.precio:
      case _AccionMasiva.costo:
        final campo = _accion == _AccionMasiva.precio
            ? 'precio de venta'
            : 'costo';
        final valor = _valorListo!;
        return switch (_tipoMonto) {
          TipoAjustePrecio.nuevoFijo =>
            'Poner el $campo en ${formatearARS(valor)} fijo',
          TipoAjustePrecio.sumarMonto =>
            'Sumar ${formatearARS(valor)} al $campo',
          TipoAjustePrecio.restarMonto =>
            'Restar ${formatearARS(valor)} al $campo',
          TipoAjustePrecio.sumarPorcentaje =>
            'Sumar ${_formatearPorcentaje(valor)}% al $campo',
          TipoAjustePrecio.restarPorcentaje =>
            'Restar ${_formatearPorcentaje(valor)}% al $campo',
        };
      case _AccionMasiva.categoria:
        final nombre = _categoriaElegida == null
            ? 'sin categoría'
            : widget.controlador.categorias
                  .firstWhere((c) => c.id == _categoriaElegida)
                  .nombre;
        return 'Poner la categoría en "$nombre"';
      case _AccionMasiva.proveedor:
        final nombre = _proveedorElegido == null
            ? 'sin proveedor'
            : widget.controlador.proveedoresDisponibles
                  .firstWhere((p) => p.id == _proveedorElegido)
                  .nombre;
        return 'Poner el proveedor en "$nombre"';
      case _AccionMasiva.activar:
        return 'Activar';
      case _AccionMasiva.desactivar:
        return 'Desactivar';
    }
  }

  /// No bloquea — un ajuste de 100%+ puede ser real (categorías enteras
  /// reciben aumentos grandes de golpe), pero es exactamente el rango
  /// donde un punto decimal que faltó pasa desapercibido (Regla de
  /// convenciones: un cálculo mal escrito no avisa solo). `restarPorcentaje`
  /// ≥100% deja el precio en \$0 en todos los marcados — caso puntual,
  /// mensaje propio.
  String? get _advertencia {
    if (!_esMonto ||
        !_esPorcentaje ||
        _valorListo == null ||
        _valorListo! < 10000) {
      return null;
    }
    final porcentaje = _formatearPorcentaje(_valorListo!);
    return _tipoMonto == TipoAjustePrecio.restarPorcentaje
        ? 'Restar $porcentaje% deja el precio en \$0 en todos los productos marcados.'
        : 'Es un aumento de $porcentaje% — más del doble del valor actual. Revisá que no '
              'te haya sobrado un dígito o faltado el punto decimal (ej. "500" en vez de "50").';
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El proveedor elegido por default es el actual de la vista (si hay
    // uno) — reasignar "al mismo de siempre" sin tener que buscarlo es el
    // caso más común al entrar acá desde el panel de un proveedor.
    if (!_proveedorInicializado) {
      _proveedorInicializado = true;
      if (widget.controlador.esProveedorReal) {
        _proveedorElegido = widget.controlador.seleccionado!.id;
      }
    }

    final cantidad = widget.controlador.seleccionMasiva.length;

    if (_revisando) {
      final advertencia = _advertencia;
      return Modal(
        titulo:
            'Confirmar cambio a $cantidad producto${cantidad == 1 ? '' : 's'}',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vas a aplicar esto a $cantidad producto${cantidad == 1 ? '' : 's'}:',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.sm),
            Text(
              _resumenAccion,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_esMonto) ...[
              const SizedBox(height: Espaciado.md),
              _VistaPrevia(
                productos: [
                  for (final p in widget.controlador.todosLosProductos)
                    if (widget.controlador.seleccionMasiva.contains(p.id)) p,
                ],
                ajustaPrecio: _accion == _AccionMasiva.precio,
                tipo: _tipoMonto,
                valor: _valorListo!,
              ),
            ],
            if (advertencia != null) ...[
              const SizedBox(height: Espaciado.md),
              Container(
                padding: const EdgeInsets.all(Espaciado.md),
                decoration: BoxDecoration(
                  color: context.colores.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(radioControlEscritorio),
                ),
                child: Text(
                  advertencia,
                  style: TextStyle(
                    color: context.colores.error,
                    fontWeight: Pesos.medium,
                  ),
                ),
              ),
            ],
          ],
        ),
        botones: [
          BotonSecundario(
            texto: 'Volver',
            onPressed: _aplicando
                ? null
                : () => setState(() => _revisando = false),
          ),
          BotonPrimario(
            key: const Key('boton_confirmar_edicion_masiva'),
            texto: _aplicando ? 'Aplicando…' : 'Sí, aplicar',
            onPressed: _aplicando ? null : _aplicar,
          ),
        ],
      );
    }

    return Modal(
      titulo: 'Editar $cantidad productos',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectorAccion(
            valor: _accion,
            onCambiar: (a) => setState(() {
              _accion = a;
              _error = null;
            }),
          ),
          const SizedBox(height: Espaciado.md),
          if (_esMonto) ...[
            Text(
              _accion == _AccionMasiva.precio
                  ? 'Se aplica al precio de venta de cada producto marcado.'
                  : 'Se aplica al costo de cada producto marcado — el '
                        'precio de venta no se toca.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.md),
            _SelectorTipoAjuste(
              valor: _tipoMonto,
              onCambiar: (t) => setState(() => _tipoMonto = t),
            ),
            const SizedBox(height: Espaciado.md),
            _esPorcentaje
                ? CampoTexto(
                    key: const Key('campo_valor_edicion_masiva'),
                    controller: _valorCtrl,
                    etiqueta: '$_etiquetaValorMonto (%)',
                    autofocus: true,
                    onSubmitted: (_) => _revisar(),
                  )
                : CampoPlata(
                    key: const Key('campo_valor_edicion_masiva'),
                    controller: _valorCtrl,
                    etiqueta: _etiquetaValorMonto,
                    autofocus: true,
                    onSubmitted: (_) => _revisar(),
                  ),
          ] else if (_accion == _AccionMasiva.categoria) ...[
            Text(
              'La categoría elegida reemplaza la actual en los productos marcados.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.md),
            _SelectorDesplegable<int?>(
              etiqueta: 'Categoría',
              valor: _categoriaElegida,
              opciones: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Sin categoría'),
                ),
                for (final c in widget.controlador.categorias)
                  DropdownMenuItem(value: c.id, child: Text(c.nombre)),
              ],
              onCambiar: (v) => setState(() => _categoriaElegida = v),
            ),
          ] else if (_accion == _AccionMasiva.proveedor) ...[
            Text(
              'El proveedor elegido reemplaza el actual en los productos marcados.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.md),
            _SelectorDesplegable<int?>(
              etiqueta: 'Proveedor',
              valor: _proveedorElegido,
              opciones: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Sin proveedor'),
                ),
                for (final p in widget.controlador.proveedoresDisponibles)
                  DropdownMenuItem(value: p.id, child: Text(p.nombre)),
              ],
              onCambiar: (v) => setState(() => _proveedorElegido = v),
            ),
          ] else
            Text(
              _accion == _AccionMasiva.activar
                  ? 'Los productos marcados vuelven a aparecer en Proveedores y en la venta.'
                  : 'Los productos marcados dejan de aparecer en Proveedores y en la '
                        'venta — nunca se borran (siguen en ventas ya hechas).',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Revisar', onPressed: _revisar),
      ],
    );
  }
}

/// Seis acciones, una elegida a la vez — mismo lenguaje visual que los
/// medios de pago de la pantalla de venta (`_BotonMedio`,
/// `columna_cobro.dart`): fondo sólido del acento cuando está elegida.
class _SelectorAccion extends StatelessWidget {
  const _SelectorAccion({required this.valor, required this.onCambiar});

  final _AccionMasiva valor;
  final ValueChanged<_AccionMasiva> onCambiar;

  static const _etiquetas = {
    _AccionMasiva.precio: 'Precio de venta',
    _AccionMasiva.costo: 'Costo',
    _AccionMasiva.categoria: 'Categoría',
    _AccionMasiva.proveedor: 'Proveedor',
    _AccionMasiva.activar: 'Activar',
    _AccionMasiva.desactivar: 'Desactivar',
  };

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Wrap(
      spacing: Espaciado.sm,
      runSpacing: Espaciado.sm,
      children: [
        for (final entrada in _etiquetas.entries)
          Material(
            color: entrada.key == valor ? colores.acento : colores.fondo,
            borderRadius: BorderRadius.circular(radioControlEscritorio),
            child: InkWell(
              borderRadius: BorderRadius.circular(radioControlEscritorio),
              onTap: () => onCambiar(entrada.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Espaciado.md,
                  vertical: Espaciado.sm,
                ),
                child: Text(
                  entrada.value,
                  style: TextStyle(
                    color: entrada.key == valor
                        ? colores.acentoTexto
                        : colores.textoPrimario,
                    fontWeight: Pesos.medium,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Cinco formas de ajustar un monto, mismo lenguaje que `_SelectorAccion`.
class _SelectorTipoAjuste extends StatelessWidget {
  const _SelectorTipoAjuste({required this.valor, required this.onCambiar});

  final TipoAjustePrecio valor;
  final ValueChanged<TipoAjustePrecio> onCambiar;

  static const _etiquetas = {
    TipoAjustePrecio.sumarPorcentaje: 'Sumar %',
    TipoAjustePrecio.restarPorcentaje: 'Restar %',
    TipoAjustePrecio.sumarMonto: 'Sumar monto',
    TipoAjustePrecio.restarMonto: 'Restar monto',
    TipoAjustePrecio.nuevoFijo: 'Valor nuevo',
  };

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Wrap(
      spacing: Espaciado.sm,
      runSpacing: Espaciado.sm,
      children: [
        for (final entrada in _etiquetas.entries)
          Material(
            color: entrada.key == valor ? colores.acento : colores.fondo,
            borderRadius: BorderRadius.circular(radioControlEscritorio),
            child: InkWell(
              borderRadius: BorderRadius.circular(radioControlEscritorio),
              onTap: () => onCambiar(entrada.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Espaciado.md,
                  vertical: Espaciado.sm,
                ),
                child: Text(
                  entrada.value,
                  style: TextStyle(
                    color: entrada.key == valor
                        ? colores.acentoTexto
                        : colores.textoPrimario,
                    fontWeight: Pesos.medium,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dropdown con la misma etiqueta fija arriba y el mismo fondo que
/// `CampoTexto` (`context.colores.fondo`) — el kit no tiene un selector
/// desplegable propio todavía, esto sigue su mismo lenguaje en vez de un
/// `DropdownButtonFormField` con el estilo por defecto de Material.
class _SelectorDesplegable<T> extends StatelessWidget {
  const _SelectorDesplegable({
    required this.etiqueta,
    required this.valor,
    required this.opciones,
    required this.onCambiar,
  });

  final String etiqueta;
  final T valor;
  final List<DropdownMenuItem<T>> opciones;
  final ValueChanged<T?> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: Espaciado.xs),
        SizedBox(
          height: Medidas.alturaControl,
          child: DropdownButtonFormField<T>(
            initialValue: valor,
            items: opciones,
            onChanged: onCambiar,
            // `isExpanded`: sin esto, un nombre de categoría/proveedor
            // largo puede desbordar el ancho del control en vez de
            // truncarse — bug real de layout de `DropdownButton`, no un
            // caso límite teórico (algunos de los 15 proveedores reales
            // tienen nombres largos, ver `DECISIONES.md`).
            isExpanded: true,
            decoration: InputDecoration(fillColor: context.colores.fondo),
          ),
        ),
      ],
    );
  }
}

/// "Lenguaje de diseño" (mock `DialogosProveedores` → Edición masiva): en
/// el paso de revisar, cómo queda cada producto — antes y ahora — con la
/// misma función que después aplica el cambio (`aplicarAjustePrecio`,
/// convención 3: el número que se ve es el que se guarda).
class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({
    required this.productos,
    required this.ajustaPrecio,
    required this.tipo,
    required this.valor,
  });

  final List<ProductoDeProveedor> productos;
  final bool ajustaPrecio;
  final TipoAjustePrecio tipo;
  final int valor;

  static const _maximo = 5;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final estiloEncabezado = textTheme.labelMedium?.copyWith(
      color: colores.textoSecundario,
    );
    final mostrados = productos.take(_maximo).toList();
    return Container(
      padding: const EdgeInsets.all(Espaciado.md),
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Producto', style: estiloEncabezado)),
              SizedBox(
                width: 110,
                child: Text(
                  'Antes',
                  textAlign: TextAlign.right,
                  style: estiloEncabezado,
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  'Ahora',
                  textAlign: TextAlign.right,
                  style: estiloEncabezado,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.xs),
          for (final p in mostrados)
            Builder(
              builder: (context) {
                final antes =
                    (ajustaPrecio ? p.precioCentavos : p.costoCentavos) ?? 0;
                final ahora = aplicarAjustePrecio(
                  precioActualCentavos: antes,
                  tipo: tipo,
                  valor: valor,
                );
                final kg = p.esPesable ? '/kg' : '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '${formatearARS(antes)}$kg',
                          textAlign: TextAlign.right,
                          style: textTheme.bodyMedium
                              ?.copyWith(color: colores.textoSecundario)
                              .tabular,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          '${formatearARS(ahora)}$kg',
                          textAlign: TextAlign.right,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: Pesos.fuerte)
                              .tabular,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (productos.length > _maximo) ...[
            const SizedBox(height: Espaciado.xs),
            Text(
              'y ${productos.length - _maximo} productos más',
              style: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
