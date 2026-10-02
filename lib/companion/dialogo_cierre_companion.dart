// Cerrar caja de verdad desde el celular (El dueño, 2026-09-19: "que deje
// cerrar caja desde el celular") — mismo molde de fases que el escritorio
// (`cierre_controlador.dart`, Regla 10: contar, comparar, separar) y el
// mismo patrón de diálogo de dos pasos que ya tiene el arqueo intermedio de
// la companion (`dialogo_arqueo_intermedio_companion.dart`), con una
// tercera fase `cerrado` (esto sí cierra la sesión) que reusa
// `SeccionExtraCierreCompanion` — el mismo widget que ya muestra el detalle
// de un cierre viejo en `pantalla_cierres.dart` (Regla 3: una sola forma de
// "cómo se ve un cierre").

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart' show ResumenCierreCompanion;
import 'debounce.dart';
import 'mensaje_error.dart';
import 'seccion_extra_cierre_companion.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/hoja_vidrio.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

/// true si se cerró de verdad — false si se canceló (solo posible en la
/// fase de conteo, antes de confirmar: una vez revelado el resumen, cerrar
/// se vuelve la única salida, mismo criterio que el escritorio).
Future<bool> mostrarDialogoCierreCompanion(
  BuildContext context, {
  required ServicioCompanion servicio,
  required int usuarioId,
  int? precargaEfectivoCentavos,
  int? precargaMpCentavos,
  DateTime? horaPrecarga,
}) async {
  final cerrado = await mostrarHojaVidrio<bool>(
    context,
    esDescartable: false,
    builder: (context) => _DialogoCierreCompanion(
      servicio: servicio,
      usuarioId: usuarioId,
      precargaEfectivoCentavos: precargaEfectivoCentavos,
      precargaMpCentavos: precargaMpCentavos,
      horaPrecarga: horaPrecarga,
    ),
  );
  return cerrado ?? false;
}

enum _Fase { conteo, revisado, cerrado }

class _DialogoCierreCompanion extends StatefulWidget {
  const _DialogoCierreCompanion({
    required this.servicio,
    required this.usuarioId,
    this.precargaEfectivoCentavos,
    this.precargaMpCentavos,
    this.horaPrecarga,
  });

  final ServicioCompanion servicio;
  final int usuarioId;

  /// Lo contado en el último arqueo del turno (El dueño, 2026-09-28). La lata
  /// no se precarga: el arqueo del turno la cuenta antes de separar los
  /// cigarrillos y el cierre después (mismo criterio que el escritorio,
  /// `CierreControlador._precargarDelUltimoArqueo`).
  final int? precargaEfectivoCentavos;
  final int? precargaMpCentavos;
  final DateTime? horaPrecarga;

  @override
  State<_DialogoCierreCompanion> createState() => _DialogoCierreCompanionState();
}

class _DialogoCierreCompanionState extends State<_DialogoCierreCompanion> {
  _Fase _fase = _Fase.conteo;

  late final _efectivoCtrl = TextEditingController(
    text: widget.precargaEfectivoCentavos == null ? '' : formatearARS(widget.precargaEfectivoCentavos!, conSigno: false),
  );
  late final _mpCtrl = TextEditingController(
    text: widget.precargaMpCentavos == null ? '' : formatearARS(widget.precargaMpCentavos!, conSigno: false),
  );
  final _lataCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _debouncer = Debouncer();

  ResumenCierreCompanion? _resumen;
  bool _calculando = false;
  bool _guardando = false;
  String? _error;

  bool get _offline => widget.servicio is ServicioCompanionOffline;

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _mpCtrl.dispose();
    _lataCtrl.dispose();
    _notaCtrl.dispose();
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
      final resumen = await widget.servicio.calcularCierre(
        efectivoContadoCentavos: efectivo,
        mpContadoCentavos: _parsear(_mpCtrl.text),
        lataContadoCentavos: _parsear(_lataCtrl.text),
      );
      if (mounted) setState(() => _resumen = resumen);
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
      await widget.servicio.confirmarCierre(
        usuarioId: widget.usuarioId,
        efectivoContadoCentavos: efectivo,
        mpContadoCentavos: mp,
        lataContadoCentavos: lata,
        nota: _notaCtrl.text,
      );
      if (mounted) setState(() => _fase = _Fase.cerrado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Bloqueado hasta cerrar de verdad — mismo criterio que el arqueo
      // intermedio: es un chequeo obligatorio, no algo para cancelar a
      // mitad de camino. Una vez `cerrado`, ya no hay nada que perder.
      canPop: _fase == _Fase.cerrado,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _fase == _Fase.cerrado ? 'Caja cerrada' : 'Cerrar caja',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_offline && _fase != _Fase.cerrado) ...[
            const SizedBox(height: Espaciado.sm),
            _avisoOffline(context),
          ],
          const SizedBox(height: Espaciado.lg),
          switch (_fase) {
            _Fase.conteo => _contenidoConteo(context),
            _Fase.revisado => _contenidoRevisado(context),
            _Fase.cerrado => _contenidoCerrado(context),
          },
          const SizedBox(height: Espaciado.lg),
          switch (_fase) {
            _Fase.conteo => FilledButton(
              onPressed: _confirmarConteo,
              child: const Text('Confirmar conteo'),
            ),
            _Fase.revisado => FilledButton(
              onPressed: _guardando ? null : _confirmar,
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cerrar caja'),
            ),
            _Fase.cerrado => FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Listo'),
            ),
          },
        ],
      ),
    );
  }

  Widget _avisoOffline(BuildContext context) {
    final colores = context.colores;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.md, vertical: Espaciado.sm),
      decoration: BoxDecoration(
        color: colores.textoTenue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(IconosPlazoleta.cloudOff, size: 18, color: colores.textoSecundario),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              'Sin conexión con la PC — este cierre se calcula con los datos ya '
              'sincronizados a este celular. Si algo de la PC todavía no llegó, '
              'puede no coincidir.',
              style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
            ),
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
          'Contá el efectivo del cajón, cigarrillos incluidos, antes de ver la '
          'diferencia y la separación.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          controller: _efectivoCtrl,
          autofocus: true,
          etiqueta: 'Efectivo contado',
          onSubmitted: (_) => _confirmarConteo(),
        ),
        if (widget.precargaEfectivoCentavos != null && widget.horaPrecarga != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'Precargado con el arqueo de las ${widget.horaPrecarga!.hour.toString().padLeft(2, '0')}:'
            '${widget.horaPrecarga!.minute.toString().padLeft(2, '0')}. '
            'Si vendiste o sacaste plata después, corregilo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: Espaciado.sm),
          ErrorEnLinea(_error!),
        ],
      ],
    );
  }

  Widget _contenidoRevisado(BuildContext context) {
    final r = _resumen;
    final colorDiferencia = r == null || r.diferenciaCentavos == 0 ? null : context.colores.error;
    final mpDiferencia = r?.mpDiferenciaCentavos;
    final colorDiferenciaMp = mpDiferencia == null || mpDiferencia == 0 ? null : context.colores.error;
    final lataDiferencia = r?.lataDiferenciaCentavos;
    final colorDiferenciaLata = lataDiferencia == null || lataDiferencia == 0 ? null : context.colores.error;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(
            controller: _efectivoCtrl,
            etiqueta: 'Efectivo contado (se puede corregir)',
            textInputAction: TextInputAction.next,
            onChanged: _alCambiarConteo,
          ),
          if (r != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'Caja esperada', r.efectivoEsperadoCentavos),
            _filaDato(context, 'Diferencia', r.diferenciaCentavos, color: colorDiferencia, enfasis: true),
          ],
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            controller: _mpCtrl,
            etiqueta: 'MP contado (según la app de Mercado Pago)',
            textInputAction: TextInputAction.next,
            onChanged: _alCambiarConteo,
          ),
          if (mpDiferencia != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'MP esperado', r!.mpEsperadoCentavos),
            _filaDato(context, 'Diferencia', mpDiferencia, color: colorDiferenciaMp, enfasis: true),
          ],
          const SizedBox(height: Espaciado.lg),
          CampoPlata(controller: _lataCtrl, etiqueta: 'Lata contada', onChanged: _alCambiarConteo),
          if (lataDiferencia != null) ...[
            const SizedBox(height: Espaciado.md),
            _filaDato(context, 'Lata esperada', r!.lataFinalCentavos),
            _filaDato(context, 'Diferencia', lataDiferencia, color: colorDiferenciaLata, enfasis: true),
          ],
          if (r != null) ...[
            const SizedBox(height: Espaciado.lg),
            const Divider(),
            const SizedBox(height: Espaciado.sm),
            SeccionExtraCierreCompanion(resumen: r),
          ],
          const SizedBox(height: Espaciado.lg),
          CampoTexto(controller: _notaCtrl, etiqueta: 'Nota (opcional)'),
          if (_calculando) ...[
            const SizedBox(height: Espaciado.sm),
            const Center(
              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Espaciado.md),
            ErrorEnLinea(_error!),
          ],
        ],
      ),
    );
  }

  Widget _contenidoCerrado(BuildContext context) {
    final r = _resumen!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filaDato(
            context,
            'Diferencia',
            r.diferenciaCentavos,
            color: r.diferenciaCentavos == 0 ? null : context.colores.error,
            enfasis: true,
          ),
          _filaDato(context, 'Lata al cierre', r.lataFinalCentavos),
          const SizedBox(height: Espaciado.sm),
          SeccionExtraCierreCompanion(resumen: r),
        ],
      ),
    );
  }

  Widget _filaDato(BuildContext context, String etiqueta, int centavos, {Color? color, bool enfasis = false}) {
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
