// "Lenguaje de diseño" (mock `DialogosVenta` → Varios): precio y cantidad
// lado a lado. El mock también traía "qué es", proveedor y costo — quedan
// afuera a propósito: "Varios" es un monto suelto SIN costo, que no genera
// reposición (REGLAS-NEGOCIO.md), y darle proveedor o costo lo convertiría
// en un producto a medias. Lo que no está cargado se da de alta en
// Proveedores.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';

/// Devuelve el monto total cargado (precio × cantidad), o null si se canceló.
Future<int?> mostrarDialogoMontoVarios(BuildContext context) {
  return mostrarModal<int>(context, builder: (context) => const _DialogoMontoVarios());
}

class _DialogoMontoVarios extends StatefulWidget {
  const _DialogoMontoVarios();

  @override
  State<_DialogoMontoVarios> createState() => _DialogoMontoVariosState();
}

class _DialogoMontoVariosState extends State<_DialogoMontoVarios> {
  final _precioCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  String? _error;

  void _confirmar() {
    final int precio;
    try {
      precio = parsearARS(_precioCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    final cantidad = int.tryParse(_cantidadCtrl.text.trim());
    if (cantidad == null || cantidad <= 0) {
      setState(() => _error = 'La cantidad tiene que ser 1 o más');
      return;
    }
    Navigator.of(context).pop(precio * cantidad);
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    _cantidadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Modal(
      titulo: 'Varios',
      subtitulo: 'Un producto que no está cargado',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: CampoPlata(
                  controller: _precioCtrl,
                  etiqueta: 'Precio',
                  autofocus: true,
                  onSubmitted: (_) => _confirmar(),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CampoTexto(
                  controller: _cantidadCtrl,
                  etiqueta: 'Cantidad',
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _confirmar(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Varios no tiene costo: no se separa para reponer y cuenta todo como ganancia.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: 'Agregar al ticket', onPressed: _confirmar),
      ],
    );
  }
}
