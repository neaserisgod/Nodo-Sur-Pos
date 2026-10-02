// Confirma que hay una sesión de caja abierta antes de dejar seguir —
// "Movimiento de caja" y vender desde el celular necesitan las dos
// exactamente lo mismo (Regla 3): si está cerrada, ofrece abrirla ahí mismo
// (apertura de emergencia, `POST /sesion/abrir`, el dueño 2026-09-07: "como
// comparten la misma bd no podemos abrirla desde la app"). Extraído de lo
// que era `pantalla_gasto_rapido.dart` (fusionada en
// `pantalla_movimiento_caja.dart`, 2026-09-18) al construir la pantalla de
// vender, para no repetir el mismo formulario dos veces.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'tema/superficie.dart';
import 'tema/error_en_linea.dart';

class SesionAbiertaGate extends StatefulWidget {
  const SesionAbiertaGate({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.onLista,
  });

  final ServicioCompanion cliente;
  final int usuarioId;

  /// Se llama una sola vez, apenas hay una sesión para usar — ya estaba
  /// abierta, o se acaba de abrir acá.
  final ValueChanged<int> onLista;

  @override
  State<SesionAbiertaGate> createState() => _SesionAbiertaGateState();
}

class _SesionAbiertaGateState extends State<SesionAbiertaGate> {
  bool _cargando = true;
  bool _sinSesion = false;
  String? _error;

  final _fondoInicialCtrl = TextEditingController();
  int? _lataQueSeArrastra;
  bool _abriendo = false;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  @override
  void dispose() {
    _fondoInicialCtrl.dispose();
    super.dispose();
  }

  Future<void> _consultar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final sesion = await widget.cliente.sesion();
      if (!mounted) return;
      if (sesion.abierta) {
        widget.onLista(sesion.id!);
        return;
      }
      if (sesion.fondoInicialSugeridoCentavos != null) {
        _fondoInicialCtrl.text = formatearARS(
          sesion.fondoInicialSugeridoCentavos!,
          conSigno: false,
        );
      }
      setState(() {
        _sinSesion = true;
        _lataQueSeArrastra = sesion.lataQueSeArrastraCentavos;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrirCaja() async {
    final int fondoInicial;
    try {
      fondoInicial = _fondoInicialCtrl.text.trim().isEmpty
          ? 0
          : parsearARS(_fondoInicialCtrl.text);
    } on FormatException {
      setState(() => _error = 'Fondo inicial inválido');
      return;
    }
    setState(() {
      _abriendo = true;
      _error = null;
    });
    try {
      final id = await widget.cliente.abrirSesion(
        usuarioId: widget.usuarioId,
        fondoInicialCentavos: fondoInicial,
      );
      widget.onLista(id);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (!_sinSesion) {
      // Ya se avisó a onLista y este widget está a punto de ser
      // reemplazado por el llamador — no hay nada que mostrar acá.
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No hay caja abierta en la PC ahora mismo.'),
          const SizedBox(height: Espaciado.md),
          Superficie(
            child: CampoPlata(
              controller: _fondoInicialCtrl,
              etiqueta: 'Fondo inicial (caja normal)',
            ),
          ),
          if (_lataQueSeArrastra != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(
              'Lata de cigarrillos: se arrastra sola, ya tiene '
              '${formatearARS(_lataQueSeArrastra!)} de antes — no hace falta contarla ahora.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Espaciado.md),
            ErrorEnLinea(_error!),
          ],
          const SizedBox(height: Espaciado.lg),
          FilledButton(
            onPressed: _abriendo ? null : _abrirCaja,
            child: _abriendo
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Abrir caja y continuar'),
          ),
        ],
      ),
    );
  }
}
