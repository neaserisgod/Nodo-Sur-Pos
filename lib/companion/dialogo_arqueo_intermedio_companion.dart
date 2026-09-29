// Arqueo obligatorio cada 2hs desde el celular (Bruno, 2026-09-13: "el
// bloqueo cada 2hs sincronizado con la app desktop") — mismo diálogo de
// dos fases que el escritorio (`dialogo_arqueo_intermedio.dart` +
// `arqueo_intermedio_controlador.dart`): conteo → revisado → confirmar, sin
// fase "cerrado" (esto no cierra la sesión). La sincronización sale sola de
// compartir la misma tabla `arqueos_intermedios`, vía HTTP con la PC o vía
// Supabase sin ella (Regla 6: un arqueo hecho en cualquier dispositivo
// resetea la cuenta del resto la próxima vez que consulten `sesion()`).
//
// Contra [ServicioCompanion], no [ClienteCompanion] a secas (Bruno,
// 2026-09-18: "no debería tener que escanear ya, es innecesario").

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart' show EstadoArqueoIntermedioCompanion;
import 'debounce.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'tema/hoja_vidrio.dart';

/// true si se confirmó — false si se canceló sin terminar (no debería
/// pasar en el uso normal: el diálogo no tiene botón de cancelar a
/// propósito, mismo criterio que el escritorio).
Future<bool> mostrarDialogoArqueoIntermedioCompanion(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
}) async {
  // Hoja de vidrio en vez de `AlertDialog` chico de 360px (Bruno,
  // 2026-09-18: "los modales no me gustan, hay que desplazarse demasiado")
  // — tres cajas para contar necesitan aire real, no un cuadro centrado que
  // obliga a scrollear adentro. `esDescartable: false`: sigue siendo un
  // chequeo obligatorio, no un diálogo opcional.
  final confirmado = await mostrarHojaVidrio<bool>(
    context,
    esDescartable: false,
    builder: (context) => _DialogoArqueoIntermedioCompanion(
      servicio: servicio,
      usuarioId: usuarioId,
    ),
  );
  return confirmado ?? false;
}

enum _Fase { conteo, revisado }

class _DialogoArqueoIntermedioCompanion extends StatefulWidget {
  const _DialogoArqueoIntermedioCompanion({
    required this.servicio,
    required this.usuarioId,
  });

  final ServicioCompanion servicio;
  final int usuarioId;

  @override
  State<_DialogoArqueoIntermedioCompanion> createState() =>
      _DialogoArqueoIntermedioCompanionState();
}

class _DialogoArqueoIntermedioCompanionState
    extends State<_DialogoArqueoIntermedioCompanion> {
  _Fase _fase = _Fase.conteo;

  final _efectivoCtrl = TextEditingController();
  final _mpCtrl = TextEditingController();
  final _lataCtrl = TextEditingController();
  final _debouncer = Debouncer();

  EstadoArqueoIntermedioCompanion? _estado;
  bool _calculando = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _mpCtrl.dispose();
    _lataCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  int? _parsear(String texto) {
    if (texto.trim().isEmpty) return null;
    try {
      return parsearARS(texto);
    } on FormatException {
      return null;
    }
  }

  Future<void> _confirmarConteo() async {
    final monto = _parsear(_efectivoCtrl.text);
    if (monto == null) {
      setState(() => _error = 'Contá el efectivo y anotalo antes de confirmar');
      return;
    }
    setState(() {
      _error = null;
      _fase = _Fase.revisado;
    });
    await _recalcular();
  }

  void _alCambiarConteo(String _) {
    if (_fase != _Fase.revisado) return;
    _debouncer.ejecutar(_recalcular);
  }

  Future<void> _recalcular() async {
    final efectivo = _parsear(_efectivoCtrl.text);
    if (efectivo == null) return;
    setState(() => _calculando = true);
    try {
      final estado = await widget.servicio.calcularArqueoIntermedio(
        efectivoContadoCentavos: efectivo,
        mpContadoCentavos: _parsear(_mpCtrl.text),
        lataContadoCentavos: _parsear(_lataCtrl.text),
      );
      if (mounted) setState(() => _estado = estado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  Future<void> _confirmar() async {
    final efectivo = _parsear(_efectivoCtrl.text);
    final mp = _parsear(_mpCtrl.text);
    final lata = _parsear(_lataCtrl.text);
    if (efectivo == null || mp == null || lata == null) {
      setState(() => _error = 'Falta el efectivo contado, el MP contado o la lata contada');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.confirmarArqueoIntermedio(
        usuarioId: widget.usuarioId,
        efectivoContadoCentavos: efectivo,
        mpContadoCentavos: mp,
        lataContadoCentavos: lata,
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
    // `PopScope` con `canPop: false`: ni el botón atrás del sistema ni
    // deslizar hacia afuera cierran esto — mismo criterio que el
    // escritorio, es un chequeo de disciplina obligatorio, no un diálogo
    // opcional (la hoja ya nace con `esDescartable: false`, esto además
    // bloquea el botón atrás del sistema).
    return PopScope(
      canPop: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Arqueo obligatorio', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Espaciado.lg),
          _fase == _Fase.conteo ? _contenidoConteo(context) : _contenidoRevisado(context),
          const SizedBox(height: Espaciado.lg),
          if (_fase == _Fase.conteo)
            FilledButton(onPressed: _confirmarConteo, child: const Text('Confirmar conteo'))
          else
            FilledButton(
              onPressed: _guardando ? null : _confirmar,
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar arqueo'),
            ),
        ],
      ),
    );
  }

  Widget _contenidoConteo(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Contá el efectivo del cajón, cigarrillos incluidos. Es '
          'opcional: lo que cuentes queda precargado en el cierre.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          controller: _efectivoCtrl,
          autofocus: true,
          etiqueta: 'Efectivo contado',
          onSubmitted: (_) => _confirmarConteo(),
        ),
        if (_error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(_error!, style: TextStyle(color: context.colores.error)),
        ],
      ],
    );
  }

  Widget _contenidoRevisado(BuildContext context) {
    final estado = _estado;
    final colorDiferencia = estado == null || estado.diferenciaCentavos == 0
        ? null
        : context.colores.error;
    final mpDiferencia = estado?.mpDiferenciaCentavos;
    final colorDiferenciaMp = mpDiferencia == null || mpDiferencia == 0
        ? null
        : context.colores.error;
    final lataDiferencia = estado?.lataDiferenciaCentavos;
    final colorDiferenciaLata = lataDiferencia == null || lataDiferencia == 0
        ? null
        : context.colores.error;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(
            controller: _efectivoCtrl,
            etiqueta: 'Efectivo contado (se puede corregir)',
            onChanged: _alCambiarConteo,
          ),
          if (estado != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'Caja esperada', estado.efectivoEsperadoCentavos),
            _filaDato(
              context,
              'Diferencia',
              estado.diferenciaCentavos,
              color: colorDiferencia,
              enfasis: true,
            ),
          ],
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            controller: _mpCtrl,
            etiqueta: 'MP contado (según la app de Mercado Pago)',
            onChanged: _alCambiarConteo,
          ),
          if (mpDiferencia != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'MP esperado', estado!.mpEsperadoCentavos),
            _filaDato(context, 'Diferencia', mpDiferencia, color: colorDiferenciaMp, enfasis: true),
          ],
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            controller: _lataCtrl,
            etiqueta: 'Lata contada',
            onChanged: _alCambiarConteo,
          ),
          if (lataDiferencia != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'Lata esperada', estado!.lataEsperadoCentavos),
            _filaDato(
              context,
              'Diferencia',
              lataDiferencia,
              color: colorDiferenciaLata,
              enfasis: true,
            ),
          ],
          if (_calculando) ...[
            const SizedBox(height: Espaciado.sm),
            const Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
    );
  }

  Widget _filaDato(
    BuildContext context,
    String etiqueta,
    int centavos, {
    Color? color,
    bool enfasis = false,
  }) {
    final estilo = enfasis
        ? Theme.of(context).textTheme.titleMedium?.copyWith(color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(formatearARS(centavos), style: estilo),
        ],
      ),
    );
  }
}
