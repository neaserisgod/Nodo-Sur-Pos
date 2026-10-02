// Alta y edición completa de producto desde la companion — antes vivía
// privada adentro de `pantalla_precios.dart` ("alta rápida", solo nombre/
// código/precio/costo/proveedor); ahora es pública porque también la abre
// el escáner central (`boton_escaner_companion.dart`), y ganó categoría y
// stock (El dueño, 2026-09-17: "que sea uno como se debe, con todos los campos
// necesarios para dejarlo andando" — sin categoría el producto queda
// invisible en reportes por categoría, y sin stock ni siquiera aparece en
// la búsqueda de venta, Regla 8).
//
// Modal, no pantalla completa (El dueño, 2026-09-19: "los modales de edición y
// agregado" — mismo lenguaje que el resto de la companion, `mostrarHojaVidrio`)
// y edición SÍ puede tocar stock directo (El dueño: "y el stock? o que
// carajos?" — antes era exclusivo de "Conteo de stock" para no duplicar ese
// camino; ahora se reusa la MISMA fórmula, `ajustarStock` — Regla 3 —, así
// que no hay dos caminos, solo dos lugares desde donde se puede llegar al
// mismo).

import 'package:flutter/material.dart';

import '../ui/comun/tarjetas.dart';

import '../domain/dinero.dart';
import '../domain/ganancia.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'escanear_codigo.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'servicio_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

/// Abre el formulario como hoja de vidrio y devuelve `true` si se guardó
/// algo — mismo contrato que tenía `pushSinTeclado<bool>` antes de que esto
/// dejara de ser una pantalla propia.
Future<bool> mostrarFormularioProducto(
  BuildContext context, {
  required ServicioCompanion cliente,
  required int usuarioId,
  required List<ProveedorCompanion> proveedores,
  required List<CategoriaCompanion> categorias,
  ProductoCompanion? producto,
  String? codigoInicial,
}) async {
  final resultado = await mostrarHojaVidrio<bool>(
    context,
    builder: (_) => PantallaFormularioProducto(
      cliente: cliente,
      usuarioId: usuarioId,
      proveedores: proveedores,
      categorias: categorias,
      producto: producto,
      codigoInicial: codigoInicial,
    ),
  );
  return resultado ?? false;
}

class PantallaFormularioProducto extends StatefulWidget {
  const PantallaFormularioProducto({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.proveedores,
    required this.categorias,
    this.producto,
    this.codigoInicial,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final List<ProveedorCompanion> proveedores;
  final List<CategoriaCompanion> categorias;

  /// No nulo = edición; null = alta.
  final ProductoCompanion? producto;

  /// Solo para alta: el código escaneado que no matcheó ningún producto.
  final String? codigoInicial;

  @override
  State<PantallaFormularioProducto> createState() =>
      _PantallaFormularioProductoState();
}

class _PantallaFormularioProductoState
    extends State<PantallaFormularioProducto> {
  late final _nombreCtrl = TextEditingController(
    text: widget.producto?.nombre ?? '',
  );
  late final _codigoCtrl = TextEditingController(
    text: widget.producto?.codigoBarras ?? widget.codigoInicial ?? '',
  );
  late final _precioCtrl = TextEditingController(
    text: widget.producto == null
        ? ''
        : formatearARS(
            widget.producto!.esPesable
                ? widget.producto!.precioPorKiloCentavos ?? 0
                : widget.producto!.precioCentavos ?? 0,
            conSigno: false,
          ),
  );
  late final _costoCtrl = TextEditingController(
    text: widget.producto == null
        ? ''
        : formatearARS(
            widget.producto!.esPesable
                ? widget.producto!.costoPorKiloCentavos ?? 0
                : widget.producto!.costoCentavos ?? 0,
            conSigno: false,
          ),
  );

  /// En alta arranca vacío (0 si no se toca). En edición arranca con el
  /// stock real — El dueño, 2026-09-19: "y el stock?", tocarlo desde acá ya no
  /// es un camino aparte, es el mismo `ajustarStock` que usa Conteo de
  /// stock (Regla 3), disparado solo si el valor cambió (ver `_guardar`).
  late final _stockCtrl = TextEditingController(
    text: widget.producto == null
        ? ''
        : '${widget.producto!.esPesable ? widget.producto!.stockGramos ?? 0 : widget.producto!.stock}',
  );

  late bool _esPesable = widget.producto?.esPesable ?? false;
  late bool _activo = widget.producto?.activo ?? true;
  int? _proveedorId;
  int? _categoriaId;

  bool _guardando = false;
  String? _error;

  /// Sin esto, el botón atrás del sistema salía directo perdiendo lo
  /// tipeado sin avisar nada.
  bool _dirty = false;
  void _marcarDirty([String? _]) => _dirty = true;

  /// A diferencia de `_marcarDirty`, esto SÍ reconstruye — precio y costo
  /// alimentan la ganancia en vivo de abajo (`_margenTexto`), así que
  /// necesitan un rebuild por cada tecla. Nombre/código no lo necesitan
  /// (el propio `TextField` ya se repinta solo), por eso siguen con la
  /// versión liviana.
  void _alCambiarPrecioOCosto(String _) {
    _dirty = true;
    setState(() {});
  }

  /// Ganancia en vivo (El dueño, 2026-09-19: "que sea compacta a la vez que
  /// potente") — mismo cálculo que "Ganancia en vivo" de Productos en el
  /// escritorio (Regla 3, `gananciaBpDesdeCostoYPrecio`,
  /// `lib/domain/ganancia.dart`), que la companion no tenía todavía. Null si
  /// falta un dato o el costo es 0 (no hay ganancia que mostrar, no un error).
  ///
  /// "Lenguaje de diseño" (2026-09-26, mock `MovilEditar`): dice cuánto se
  /// gana por unidad, además del porcentaje, y avisa si el precio no cubre
  /// el costo.
  ({String texto, bool cubre})? get _margenTexto {
    final textoPrecio = _precioCtrl.text.trim();
    final costo = _costoParseado;
    if (textoPrecio.isEmpty || costo == null) return null;
    try {
      final precio = parsearARS(textoPrecio);
      if (precio <= costo) return (texto: 'El precio no cubre el costo', cubre: false);
      final gananciaBp = gananciaBpDesdeCostoYPrecio(costo, precio);
      return (
        texto: 'Ganás ${formatearARS(precio - costo)} ${_esPesable ? 'por kilo' : 'por unidad'} · ${(gananciaBp / 100).round()}%',
        cubre: true,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Null sin costo, o con costo $0 (Regla 4: no es un costo).
  int? get _costoParseado {
    final texto = _costoCtrl.text.trim();
    if (texto.isEmpty) return null;
    try {
      final costo = parsearARS(texto);
      return costo > 0 ? costo : null;
    } on FormatException {
      return null;
    }
  }

  /// Precio rápido: el que da [gananciaBp] de ganancia sobre el precio, redondeado hacia arriba al peso
  /// (`precioDesdeCostoYGanancia`, Regla 5) — un botón que se toca a
  /// propósito, nunca un autocompletado (Regla 14).
  void _aplicarPrecioRapido(int gananciaBp) {
    final costo = _costoParseado;
    if (costo == null) return;
    _precioCtrl.text = formatearARS(precioDesdeCostoYGanancia(costo, gananciaBp)).replaceAll('\$', '');
    _alCambiarPrecioOCosto('');
  }

  Future<void> _reescanear() async {
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() {
      _codigoCtrl.text = codigo;
      _dirty = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _proveedorId = widget.producto?.proveedorId;
    _categoriaId = widget.producto?.categoriaId;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _codigoCtrl.dispose();
    _precioCtrl.dispose();
    _costoCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }
    final int? precio;
    final int? costo;
    final int? stockTipeado;
    try {
      precio = _precioCtrl.text.trim().isEmpty
          ? null
          : parsearARS(_precioCtrl.text);
      costo = _costoCtrl.text.trim().isEmpty
          ? null
          : parsearARS(_costoCtrl.text);
      stockTipeado = _stockCtrl.text.trim().isEmpty
          ? null
          : int.parse(_stockCtrl.text.trim());
    } on FormatException {
      setState(() => _error = 'Precio, costo o stock inválido');
      return;
    }
    if (_esPesable && precio == null) {
      setState(() => _error = 'Un producto pesable necesita precio por kilo');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final producto = widget.producto;
      if (producto == null) {
        await widget.cliente.crearProducto(
          nombre: _nombreCtrl.text.trim(),
          codigoBarras: _codigoCtrl.text.trim().isEmpty
              ? null
              : _codigoCtrl.text.trim(),
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          precioCentavos: _esPesable ? null : precio,
          costoCentavos: _esPesable ? null : costo,
          precioPorKiloCentavos: _esPesable ? precio : null,
          costoPorKiloCentavos: _esPesable ? costo : null,
          stock: _esPesable ? 0 : (stockTipeado ?? 0),
          stockGramos: _esPesable ? stockTipeado : null,
          usuarioId: widget.usuarioId,
        );
      } else {
        // Stock nunca viaja por `actualizarProducto` (Regla 8/6: todo
        // movimiento de stock deja rastro en `movimientos_de_stock`,
        // cambiarlo "de paso" en una edición de precio no lo dejaría) — se
        // pasa el valor QUE YA TENÍA sin tocar, y si el campo de acá abajo
        // cambió, se dispara un `ajustarStock` aparte, mismo camino que
        // usa Conteo de stock.
        await widget.cliente.actualizarProducto(
          producto.id,
          nombre: _nombreCtrl.text.trim(),
          codigoBarras: _codigoCtrl.text.trim().isEmpty
              ? null
              : _codigoCtrl.text.trim(),
          categoriaId: _categoriaId,
          proveedorId: _proveedorId,
          esPesable: _esPesable,
          precioCentavos: _esPesable ? null : precio,
          costoCentavos: _esPesable ? null : costo,
          precioPorKiloCentavos: _esPesable ? precio : null,
          costoPorKiloCentavos: _esPesable ? costo : null,
          stock: producto.stock,
          stockGramos: producto.stockGramos,
          activo: _activo,
          usuarioId: widget.usuarioId,
        );
        final stockActual = _esPesable ? producto.stockGramos ?? 0 : producto.stock;
        if (stockTipeado != null && stockTipeado != stockActual) {
          await widget.cliente.ajustarStock(
            producto.id,
            stock: _esPesable ? producto.stock : stockTipeado,
            stockGramos: _esPesable ? stockTipeado : null,
            motivo: 'Editado desde ficha de producto',
            usuarioId: widget.usuarioId,
          );
        }
      }
      _dirty = false;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAlta = widget.producto == null;
    return PopScope(
      // Siempre `false`, no `!_dirty`: `_dirty` se marca sin pasar por
      // `setState` (no hace falta rebuild solo por eso), así que un
      // `canPop` calculado en el build anterior podría estar desactualizado
      // al momento real de tocar atrás. Se decide fresco adentro del
      // callback en vez de confiar en el valor ya construido.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_dirty || await confirmarSalirSinGuardar(context)) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            esAlta ? 'Nuevo producto' : 'Editar producto',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: Espaciado.md),
          // Alto acotado + scroll propio adentro de la hoja — con seis
          // campos más la ganancia en vivo, en un celular chico (o con el
          // teclado ya abierto achicando el espacio disponible) puede no
          // entrar entero; la hoja en sí no scrollea (`mostrarHojaVidrio`),
          // así que el que scrollea es este contenido, no la hoja completa
          // (el título y el botón de guardar siempre quedan visibles).
          // `ConstrainedBox` con un tope, no `Flexible`: adentro de una
          // `Column` con `mainAxisSize.min` (la hoja se achica a su
          // contenido) un `Flexible` no tiene "espacio sobrante" que
          // repartir y el `SingleChildScrollView` recibiría una altura sin
          // límite — error real de Flutter, no solo estético.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SeccionFormulario(
                    titulo: 'Datos básicos',
                    campos: [
                      CampoTexto(
                        controller: _nombreCtrl,
                        etiqueta: 'Nombre',
                        autofocus: esAlta,
                        textInputAction: TextInputAction.next,
                        onChanged: _marcarDirty,
                      ),
                      CampoTexto(
                        controller: _codigoCtrl,
                        etiqueta: 'Código de barras (opcional)',
                        textInputAction: TextInputAction.next,
                        onChanged: _marcarDirty,
                        suffixIcon: IconButton(
                          icon: const Icon(IconosPlazoleta.qrCodeScanner),
                          tooltip: 'Escanear',
                          onPressed: _reescanear,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espaciado.md),
                  _SeccionFormulario(
                    titulo: 'Precio',
                    campos: [
                      Row(
                        children: [
                          const Expanded(child: Text('Se vende pesado (por kilo)')),
                          Switch(
                            value: _esPesable,
                            onChanged: (v) => setState(() {
                              _esPesable = v;
                              _dirty = true;
                            }),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CampoPlata(
                              controller: _precioCtrl,
                              etiqueta: _esPesable ? 'Precio/kilo' : 'Precio',
                              textInputAction: TextInputAction.next,
                              onChanged: _alCambiarPrecioOCosto,
                            ),
                          ),
                          const SizedBox(width: Espaciado.md),
                          Expanded(
                            child: CampoPlata(
                              controller: _costoCtrl,
                              etiqueta: _esPesable ? 'Costo/kilo' : 'Costo',
                              textInputAction: TextInputAction.next,
                              onChanged: _alCambiarPrecioOCosto,
                            ),
                          ),
                        ],
                      ),
                      if (_margenTexto != null || _costoParseado != null) ...[
                        const SizedBox(height: Espaciado.sm),
                        Wrap(
                          spacing: Espaciado.sm,
                          runSpacing: Espaciado.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_margenTexto != null)
                              Insignia(
                                texto: _margenTexto!.texto,
                                tono: _margenTexto!.cubre ? Tono.ganancia : Tono.error,
                              ),
                            if (_costoParseado != null)
                              for (final bp in const [2000, 3000, 4000])
                                ActionChip(
                                  label: Text('${bp ~/ 100}% ganancia'),
                                  onPressed: () => _aplicarPrecioRapido(bp),
                                ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Espaciado.md),
                  _SeccionFormulario(
                    titulo: 'Organización',
                    campos: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _categoriaId,
                              // `isExpanded: true` — sin esto, un nombre
                              // largo de categoría desborda el ancho
                              // acotado que le toca acá adentro de la fila
                              // de dos columnas.
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Categoría'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin categoría'),
                                ),
                                for (final c in widget.categorias)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) => setState(() {
                                _categoriaId = v;
                                _dirty = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: Espaciado.md),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _proveedorId,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Proveedor'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin proveedor'),
                                ),
                                for (final p in widget.proveedores)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                      '${p.codigo} — ${p.nombre}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(() {
                                _proveedorId = v;
                                _dirty = true;
                              }),
                            ),
                          ),
                        ],
                      ),
                      CampoTexto(
                        controller: _stockCtrl,
                        etiqueta: _esPesable ? 'Stock (gramos)' : 'Stock (unidades)',
                        keyboardType: TextInputType.number,
                        onChanged: _marcarDirty,
                      ),
                      if (!esAlta)
                        Row(
                          children: [
                            const Expanded(child: Text('Activo (se puede vender)')),
                            Switch(
                              value: _activo,
                              onChanged: (v) => setState(() {
                                _activo = v;
                                _dirty = true;
                              }),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Espaciado.md),
                    ErrorEnLinea(_error!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(esAlta ? 'Dar de alta' : 'Guardar cambios'),
          ),
          const SizedBox(height: Espaciado.sm),
          // Cancelar hace lo mismo que volver atrás: pregunta antes de tirar lo tipeado.
          OutlinedButton(onPressed: _guardando ? null : _cancelar, child: const Text('Cancelar')),
        ],
      ),
    );
  }

  Future<void> _cancelar() async {
    if (!_dirty || await confirmarSalirSinGuardar(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// Una sección del formulario: título chico arriba, una sola `Superficie`
/// abajo con todos sus campos separados por aire, no una tarjeta por campo.
class _SeccionFormulario extends StatelessWidget {
  const _SeccionFormulario({required this.titulo, required this.campos});

  final String titulo;
  final List<Widget> campos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Espaciado.xs, bottom: Espaciado.sm),
          child: Text(
            titulo,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: context.colores.textoSecundario),
          ),
        ),
        Superficie(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < campos.length; i++) ...[
                if (i > 0) const SizedBox(height: Espaciado.lg),
                campos[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
