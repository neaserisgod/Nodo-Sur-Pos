// Doble clic en la cantidad (o los gramos) de una línea del carrito
// (El dueño, 2026-09-06: "que se pueda ajustar la cantidad... haciendo doble
// click") — para saltar de un tirón (ej. de x1 a x12) sin tocar "+" once
// veces. 0 o menos se interpreta como "sacar la línea" (mismo criterio que
// restar hasta el fondo con el botón "−"), lo decide quien llama, no este
// diálogo.
//
// "Lenguaje de diseño" (mock `DialogosVenta` → Cambiar cantidad): número
// grande, subtotal en vivo y un teclado numérico para usarlo con el mouse o
// la pantalla táctil — el teclado físico sigue andando igual, el campo
// arranca con foco y todo seleccionado.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../domain/pesables.dart';
import '../../domain/venta.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/iconos.dart';
import '../tema/presionable.dart';
import '../tema/tokens.dart';

/// Devuelve el nuevo valor tipeado, o null si se canceló. [titulo] identifica
/// qué se está editando ("Cantidad" o "Gramos") — mismo diálogo para los dos
/// casos, la única diferencia real es el rótulo. Con [linea], muestra el
/// producto y el subtotal que va a quedar.
Future<int?> mostrarDialogoEditarCantidad(
  BuildContext context, {
  required String titulo,
  required int valorActual,
  LineaVenta? linea,
}) {
  return mostrarModal<int>(
    context,
    builder: (context) => _DialogoEditarCantidad(titulo: titulo, valorActual: valorActual, linea: linea),
  );
}

class _DialogoEditarCantidad extends StatefulWidget {
  const _DialogoEditarCantidad({required this.titulo, required this.valorActual, this.linea});
  final String titulo;
  final int valorActual;
  final LineaVenta? linea;

  @override
  State<_DialogoEditarCantidad> createState() => _DialogoEditarCantidadState();
}

class _DialogoEditarCantidadState extends State<_DialogoEditarCantidad> {
  late final _controlador = TextEditingController(text: widget.valorActual.toString());
  final _foco = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controlador.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _foco.requestFocus();
      _controlador.selection = TextSelection(baseOffset: 0, extentOffset: _controlador.text.length);
    });
  }

  void _confirmar() {
    final valor = int.tryParse(_controlador.text.trim());
    if (valor == null) {
      setState(() => _error = 'Ingresá un número');
      return;
    }
    Navigator.of(context).pop(valor);
  }

  /// Una tecla del teclado en pantalla. Con todo seleccionado (recién
  /// abierto) el primer dígito reemplaza, igual que con el teclado físico.
  void _tecla(String t) {
    final sel = _controlador.selection;
    final todoElegido = sel.isValid && sel.start == 0 && sel.end == _controlador.text.length && !sel.isCollapsed;
    var texto = todoElegido ? '' : _controlador.text;
    if (t == 'C') {
      texto = '';
    } else if (t == '⌫') {
      if (texto.isNotEmpty) texto = texto.substring(0, texto.length - 1);
    } else if (texto.length < 6) {
      texto = texto == '0' ? t : texto + t;
    }
    _controlador.value = TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
    _error = null;
  }

  String? get _subtitulo {
    final l = widget.linea;
    return switch (l) {
      null => null,
      LineaVentaPorUnidad() => '${l.nombreProducto} · ${formatearARS(l.precioUnitarioCentavos)} c/u',
      LineaVentaPesable() => '${l.nombreProducto} · ${formatearARS(l.precioPorKiloCentavos)} el kilo',
    };
  }

  int? get _subtotal {
    final l = widget.linea;
    final v = int.tryParse(_controlador.text.trim());
    if (l == null || v == null || v < 0) return null;
    return switch (l) {
      LineaVentaPorUnidad() => l.precioUnitarioCentavos * v,
      // Convención 4: el subtotal de un pesable pasa siempre por su helper.
      LineaVentaPesable() => subtotalPesable(montoPorKiloCentavos: l.precioPorKiloCentavos, gramos: v),
    };
  }

  @override
  void dispose() {
    _controlador.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final subtotal = _subtotal;
    return Modal(
      titulo: 'Cambiar ${widget.titulo.toLowerCase()}',
      subtitulo: _subtitulo,
      ancho: 620,
      contenido: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.titulo, style: textTheme.labelMedium),
                const SizedBox(height: Espaciado.xs + 2),
                Container(
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: colores.acento, width: 2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    key: const Key('campo_cantidad'),
                    controller: _controlador,
                    focusNode: _foco,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: textTheme.displayMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                    ),
                    onSubmitted: (_) => _confirmar(),
                  ),
                ),
                if (subtotal != null) ...[
                  const SizedBox(height: Espaciado.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
                    decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Expanded(child: Text('Subtotal', style: textTheme.labelLarge)),
                        Text(formatearARS(subtotal), style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte).tabular),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Espaciado.sm),
                  Text(_error!, style: TextStyle(color: colores.error)),
                ],
              ],
            ),
          ),
          const SizedBox(width: Espaciado.lg),
          SizedBox(
            width: 260,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: Espaciado.sm,
              crossAxisSpacing: Espaciado.sm,
              childAspectRatio: 1.45,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '⌫'])
                  Presionable(
                    radio: 16,
                    color: t == 'C' || t == '⌫' ? colores.borde : colores.fondo,
                    onTap: () => _tecla(t),
                    child: Center(
                      child: t == '⌫'
                          ? const Icon(IconosPlazoleta.backspace, semanticLabel: 'Borrar')
                          : Text(t, style: textTheme.titleLarge?.copyWith(fontWeight: Pesos.fuerte)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: 'Listo', onPressed: _confirmar),
      ],
    );
  }
}
