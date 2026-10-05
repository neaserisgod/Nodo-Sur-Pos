// Hoja "Cambiar precio" (docs/03 H4): tocar un producto de la lista abre el campo
// del precio de venta (o por kilo) con "Guardar precio" y un atajo a la ficha completa.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

/// `true` si se guardó el precio; `false` si se pidió la ficha completa; `null` si se canceló.
Future<bool?> mostrarHojaCambiarPrecio(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
  required ProductoCompanion producto,
  required String? nombreProveedor,
}) {
  return mostrarHojaNs<bool>(context, builder: (_) => _HojaCambiarPrecio(servicio: servicio, usuarioId: usuarioId, producto: producto, nombreProveedor: nombreProveedor));
}

class _HojaCambiarPrecio extends StatefulWidget {
  const _HojaCambiarPrecio({required this.servicio, required this.usuarioId, required this.producto, required this.nombreProveedor});
  final ServicioCompanion servicio;
  final int usuarioId;
  final ProductoCompanion producto;
  final String? nombreProveedor;

  @override
  State<_HojaCambiarPrecio> createState() => _HojaCambiarPrecioState();
}

class _HojaCambiarPrecioState extends State<_HojaCambiarPrecio> {
  late final TextEditingController _precio = TextEditingController(text: '${((widget.producto.esPesable ? widget.producto.precioPorKiloCentavos : widget.producto.precioCentavos) ?? 0) ~/ centavosPorPeso}');
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pesos = int.tryParse(_precio.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (pesos <= 0) {
      mostrarAvisoNs(context, 'Escribí un precio');
      return;
    }
    final p = widget.producto;
    final centavos = pesos * centavosPorPeso;
    final overlay = Overlay.of(context, rootOverlay: true);
    final navegador = Navigator.of(context);
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.actualizarProducto(
        p.id,
        nombre: p.nombre,
        codigoBarras: p.codigoBarras,
        categoriaId: p.categoriaId,
        proveedorId: p.proveedorId,
        esPesable: p.esPesable,
        precioCentavos: p.esPesable ? p.precioCentavos : centavos,
        costoCentavos: p.costoCentavos,
        precioPorKiloCentavos: p.esPesable ? centavos : p.precioPorKiloCentavos,
        costoPorKiloCentavos: p.costoPorKiloCentavos,
        stock: p.stock,
        stockGramos: p.stockGramos,
        activo: p.activo,
        usuarioId: widget.usuarioId,
      );
      if (!mounted) return;
      navegador.pop(true);
      mostrarAvisoEnNs(overlay, 'Precio actualizado');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    return HojaNs(
      titulo: p.nombre,
      texto: '${widget.nombreProveedor ?? 'Sin proveedor'} · cambiá el precio de venta',
      bloques: [
        CampoNs(etiqueta: p.esPesable ? 'Precio de venta por kilo' : 'Precio de venta', controller: _precio, grande: true, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, autofoco: true, onSubmit: (_) => _guardar()),
        BotonNs.secundario(context, 'Editar ficha completa (costo, stock, categoría)', () => Navigator.of(context).pop(false), alto: 54, tamanio: 15),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar precio', _guardando ? null : _guardar, habilitado: !_guardando),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop()),
      ],
    );
  }
}
