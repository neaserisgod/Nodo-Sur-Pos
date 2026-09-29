// Escáner de código de barras reusable — lo usan tanto "Precios y alta de
// producto" como "Consultar precio". Un solo lugar para no repetir el
// manejo de la cámara (Regla 3).

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'navegacion.dart';

/// Abre la cámara a pantalla completa y devuelve el primer código detectado,
/// o `null` si se cancela.
Future<String?> escanearCodigo(BuildContext context) {
  return pushSinTeclado<String>(context, (_) => const _PantallaEscaner());
}

class _PantallaEscaner extends StatefulWidget {
  const _PantallaEscaner();

  @override
  State<_PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<_PantallaEscaner> {
  bool _yaDetectado = false;

  void _alDetectar(BarcodeCapture captura) {
    if (_yaDetectado) return;
    final valor = captura.barcodes.isEmpty
        ? null
        : captura.barcodes.first.rawValue;
    if (valor == null || valor.isEmpty) return;
    _yaDetectado = true;
    Navigator.of(context).pop(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código')),
      body: MobileScanner(onDetect: _alDetectar),
    );
  }
}
