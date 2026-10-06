// `.sbig` del mock v4 dentro de una pantalla (Proveedores, Separaciones, Historial...): el buscador grande y gris que
// filtra lo de esa pantalla. Al enfocarse se pone blanco con el aro azul, como el campo único de Venta. Esc lo vacía.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ic.dart';
import 'mov.dart';
import 'paleta.dart';
import 'texto.dart';
import 'tocable.dart';

class BuscadorPagina extends StatefulWidget {
  const BuscadorPagina({
    super.key,
    required this.pista,
    required this.onCambio,
    this.alto = 54,
    this.campoKey,
    this.focusNode,
  });

  final String pista;

  /// Cada tecla, con el texto recortado (vacío = sin filtro).
  final ValueChanged<String> onCambio;
  final double alto;
  final Key? campoKey;
  final FocusNode? focusNode;

  @override
  State<BuscadorPagina> createState() => _BuscadorPaginaState();
}

class _BuscadorPaginaState extends State<BuscadorPagina> {
  final _texto = TextEditingController();
  FocusNode? _propio;
  FocusNode get _foco => widget.focusNode ?? (_propio ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _foco.addListener(_refrescar);
  }

  void _refrescar() => setState(() {});

  @override
  void dispose() {
    _foco.removeListener(_refrescar);
    _propio?.dispose();
    _texto.dispose();
    super.dispose();
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && _texto.text.isNotEmpty) {
      _texto.clear();
      widget.onCambio('');
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final enfocado = _foco.hasFocus;
    final estiloTexto = estilo(19, 450, color: p.tinta, em: -.02);
    return GestureDetector(
      onTap: _foco.requestFocus,
      excludeFromSemantics: true,
      child: AnimatedContainer(
        duration: ms(250),
        height: widget.alto,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: enfocado ? p.papel : p.s,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enfocado ? const [BoxShadow(color: PaletaMock.foco, spreadRadius: 3)] : null,
        ),
        child: Row(
          children: [
            Icono(Ic.search, size: 22, color: p.tinta),
            const SizedBox(width: 16),
            Expanded(
              child: Focus(
                onKeyEvent: _tecla,
                child: AreaMinimaToque(
                  child: TextField(
                    key: widget.campoKey,
                    controller: _texto,
                    focusNode: _foco,
                    style: estiloTexto,
                    cursorColor: p.azul,
                    decoration: decoracionSinBorde(widget.pista, estiloTexto.copyWith(color: p.mute)),
                    onChanged: (t) {
                      setState(() {});
                      widget.onCambio(t.trim());
                    },
                  ),
                ),
              ),
            ),
            if (_texto.text.isNotEmpty)
              Tocable(
                radio: 999,
                etiqueta: 'Borrar la búsqueda',
                onTap: () {
                  _texto.clear();
                  widget.onCambio('');
                  setState(() {});
                },
                child: Padding(padding: const EdgeInsets.all(6), child: Icono(Ic.x, size: 18, color: p.mute)),
              ),
          ],
        ),
      ),
    );
  }
}
