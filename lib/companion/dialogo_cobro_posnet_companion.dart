// Cobro por terminal Point desde el celular — mismo ciclo de tres pasos que
// `dialogo_cobro_posnet.dart` del escritorio (Fase 12): crea la orden, poll
// de estado con el mismo ritmo (`intervaloPollingCobroPosnet`/
// `timeoutPollingCobroPosnet`, `domain/cobro_posnet.dart` — Regla 3), y
// recién graba la venta si se aprueba.
//
// Contra [ServicioCompanion], no [ClienteCompanion] a secas: con la PC
// emparejada y alcanzable la orden va por HTTP a la PC, que tiene las
// credenciales de Mercado Pago (`resolverServicioCompanion` decide una sola
// vez cuál). Sin la PC (`PuertoLocal`) no hay credenciales y se avisa.

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/cobro_posnet.dart';
import '../domain/descuento.dart';
import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../ui/tema/tokens.dart';
import '../servicios/avisos_cobro_mp.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'tema/hoja_vidrio.dart';

/// Devuelve `(ventaId, totalCentavos)` si se aprobó y se grabó la venta,
/// `null` en cualquier otro cierre (cancelado, rechazado sin reintentar).
/// [montoCentavos] ya viene con el descuento aplicado (lo calculó
/// `PantallaCarritoVenta` antes de abrir este diálogo) — [tipoDescuento]/
/// [valorDescuento] viajan igual, para que `iniciarCobroPosnet`/
/// `confirmarCobroPosnet` recalculen el mismo total del lado del servidor.
Future<({int ventaId, int totalCentavos})?> mostrarDialogoCobroPosnetCompanion(
  BuildContext context, {
  required ServicioCompanion cliente,
  required int usuarioId,
  required int sesionCajaId,
  required List<LineaVenta> lineas,
  required String canal,
  required int montoCentavos,
  TipoDescuento? tipoDescuento,
  int valorDescuento = 0,
  int? encargueId,
}) {
  return mostrarHojaVidrio<({int ventaId, int totalCentavos})?>(
    context,
    esDescartable: false,
    builder: (context) => _DialogoCobroPosnetCompanion(
      cliente: cliente,
      usuarioId: usuarioId,
      sesionCajaId: sesionCajaId,
      lineas: lineas,
      canal: canal,
      montoCentavos: montoCentavos,
      tipoDescuento: tipoDescuento,
      valorDescuento: valorDescuento,
      encargueId: encargueId,
    ),
  );
}

enum _Fase {
  creando,
  esperando,
  cancelando,
  cobrandoAMano,
  aprobado,
  rechazado,
  expirado,
  error,
}

class _DialogoCobroPosnetCompanion extends StatefulWidget {
  const _DialogoCobroPosnetCompanion({
    required this.cliente,
    required this.usuarioId,
    required this.sesionCajaId,
    required this.lineas,
    required this.canal,
    required this.montoCentavos,
    this.tipoDescuento,
    this.valorDescuento = 0,
    this.encargueId,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final int sesionCajaId;
  final List<LineaVenta> lineas;
  final String canal;
  final int montoCentavos;
  final TipoDescuento? tipoDescuento;
  final int valorDescuento;

  /// El encargue por apartado que esta venta entrega: se libera al grabar la venta, por Point o a mano.
  final int? encargueId;

  @override
  State<_DialogoCobroPosnetCompanion> createState() =>
      _DialogoCobroPosnetCompanionState();
}

class _DialogoCobroPosnetCompanionState
    extends State<_DialogoCobroPosnetCompanion> {
  _Fase _fase = _Fase.creando;
  String? _error;
  int? _ordenPendienteId;
  String? _ordenIdMp;
  bool _cancelado = false;

  /// La Point le pidió algo al cliente (`action_required`): se avisa en pantalla, el cobro sigue esperando.
  bool _enTerminal = false;

  /// Consultas seguidas que fallaron (sin red un momento). Recién después de [_maxFallasSeguidas] se muestra el error: una
  /// falla suelta con la orden viva en la terminal no puede cortar el cobro.
  int _fallasSeguidas = 0;
  static const _maxFallasSeguidas = 3;
  bool _errorAlCancelar = false;
  ({int ventaId, int totalCentavos})? _resultadoAprobado;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final orden = await widget.cliente.iniciarCobroPosnet(
        lineas: widget.lineas,
        canal: widget.canal,
        sesionCajaId: widget.sesionCajaId,
        tipoDescuento: widget.tipoDescuento,
        valorDescuento: widget.valorDescuento,
      );
      if (_cancelado) {
        await _ejecutarCancelacion(
          ordenPendienteId: orden.ordenPendienteId,
          ordenIdMp: orden.ordenIdMp,
        );
        return;
      }
      if (!mounted) return;
      _ordenPendienteId = orden.ordenPendienteId;
      _ordenIdMp = orden.ordenIdMp;
      setState(() => _fase = _Fase.esperando);
      await _pollear();
    } catch (e) {
      if (_cancelado) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = mensajeDeError(e);
      });
    }
  }

  Future<void> _pollear() async {
    final intentos =
        timeoutPollingCobroPosnet.inMilliseconds ~/
        intervaloPollingCobroPosnet.inMilliseconds;
    for (var i = 0; i < intentos && mounted && !_cancelado; i++) {
      // Con aviso en vivo de Mercado Pago se consulta al instante; sin aviso, la pausa de siempre.
      await esperarAvisoOrden(_ordenIdMp!, intervaloPollingCobroPosnet);
      if (!mounted || _cancelado) return;

      final ResultadoOrdenCobro resultado;
      try {
        resultado = await widget.cliente.consultarEstadoPosnet(_ordenIdMp!);
      } catch (e) {
        if (++_fallasSeguidas < _maxFallasSeguidas) continue;
        if (!mounted) return;
        setState(() {
          _fase = _Fase.error;
          _error = mensajeDeError(e);
        });
        return;
      }
      if (!mounted || _cancelado) return;
      _fallasSeguidas = 0;
      final enTerminal = resultado == ResultadoOrdenCobro.confirmarEnTerminal;
      if (enTerminal != _enTerminal) setState(() => _enTerminal = enTerminal);

      if (resultado == ResultadoOrdenCobro.aprobada) {
        try {
          _resultadoAprobado = await widget.cliente.confirmarCobroPosnet(
            ordenPendienteId: _ordenPendienteId!,
            lineas: widget.lineas,
            canal: widget.canal,
            sesionCajaId: widget.sesionCajaId,
            usuarioId: widget.usuarioId,
            tipoDescuento: widget.tipoDescuento,
            valorDescuento: widget.valorDescuento,
            encargueId: widget.encargueId,
          );
          if (mounted) setState(() => _fase = _Fase.aprobado);
        } catch (e) {
          if (mounted) {
            setState(() {
              _fase = _Fase.error;
              _error = mensajeDeError(e);
            });
          }
        }
        return;
      }
      if (resultado == ResultadoOrdenCobro.rechazada) {
        await widget.cliente.resolverCobroPosnetNoAprobado(
          ordenPendienteId: _ordenPendienteId!,
          estado: 'rechazada',
        );
        if (mounted) setState(() => _fase = _Fase.rechazado);
        return;
      }
      // pendiente: sigue el loop hasta el timeout.
    }
    if (mounted && _fase == _Fase.esperando) {
      setState(() => _fase = _Fase.expirado);
    }
  }

  void _cancelar() {
    _cancelado = true;
    final id = _ordenPendienteId;
    if (id == null) {
      setState(() => _fase = _Fase.cancelando);
      return;
    }
    _ejecutarCancelacion(ordenPendienteId: id, ordenIdMp: _ordenIdMp);
  }

  Future<void> _ejecutarCancelacion({
    required int ordenPendienteId,
    String? ordenIdMp,
  }) async {
    if (mounted) setState(() => _fase = _Fase.cancelando);
    try {
      await widget.cliente.cancelarCobroPosnet(
        ordenPendienteId: ordenPendienteId,
        ordenIdMp: ordenIdMp,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _errorAlCancelar = true;
        _error =
            'No se pudo cancelar automáticamente: ${mensajeDeError(e)} '
            'Cancelala a mano en la terminal si sigue esperando el pago.';
      });
    }
  }

  Future<void> _reintentar() async {
    setState(() {
      _fase = _Fase.creando;
      _error = null;
      _ordenPendienteId = null;
      _ordenIdMp = null;
    });
    await _iniciar();
  }

  /// "Cobrar a mano" (El dueño, 2026-09-07: "para cargar las ventas de hoy y
  /// seguir cargando mientras tanto") — mismo criterio que
  /// `VentaControlador.cobrarActual()` del escritorio: graba la venta
  /// directo, sin esperar más al posnet, conservando el canal elegido.
  Future<void> _cobrarAMano() async {
    setState(() {
      _fase = _Fase.cobrandoAMano;
      _error = null;
    });
    try {
      final resultado = await widget.cliente.cobrarVirtualAMano(
        lineas: widget.lineas,
        sesionCajaId: widget.sesionCajaId,
        usuarioId: widget.usuarioId,
        canal: widget.canal,
        tipoDescuento: widget.tipoDescuento,
        valorDescuento: widget.valorDescuento,
        encargueId: widget.encargueId,
      );
      if (mounted) Navigator.of(context).pop(resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = 'No se pudo grabar la venta: ${mensajeDeError(e)}';
      });
    }
  }

  void _cerrar() => Navigator.of(context).pop(_resultadoAprobado);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cobrar por ${nombreCanal(widget.canal)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Espaciado.lg),
          _contenido(),
          const SizedBox(height: Espaciado.lg),
          _filaBotones(),
        ],
      ),
    );
  }

  /// `_botones()` puede devolver 0, 1 o 2 botones según la fase — con dos,
  /// van lado a lado (mismo ancho cada uno); con uno, ocupa todo el ancho.
  Widget _filaBotones() {
    final botones = _botones();
    if (botones.isEmpty) return const SizedBox.shrink();
    if (botones.length == 1) return botones.first;
    return Row(
      children: [
        for (var i = 0; i < botones.length; i++) ...[
          if (i > 0) const SizedBox(width: Espaciado.sm),
          Expanded(child: botones[i]),
        ],
      ],
    );
  }

  Widget _contenido() {
    final monto = formatearARS(widget.montoCentavos);
    return switch (_fase) {
      _Fase.creando => _filaCargando(
        'Enviando la orden a la terminal — $monto',
      ),
      _Fase.esperando => _filaCargando(
        _enTerminal ? 'El cliente tiene que confirmar en la terminal — $monto' : 'Esperando el pago — $monto',
      ),
      _Fase.cancelando => _filaCargando('Cancelando en la terminal...'),
      _Fase.cobrandoAMano => _filaCargando('Grabando la venta — $monto'),
      _Fase.aprobado => Text('Pago aprobado — $monto'),
      _Fase.rechazado => const Text('El pago no se aprobó en la terminal.'),
      _Fase.expirado => const Text(
        'No se pudo confirmar el pago a tiempo. Revisá la terminal.',
      ),
      _Fase.error => Text(_error ?? 'No se pudo conectar con Mercado Pago.'),
    };
  }

  Widget _filaCargando(String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 16),
        Flexible(child: Text(texto)),
      ],
    );
  }

  List<Widget> _botones() {
    return switch (_fase) {
      _Fase.creando || _Fase.esperando => [
        TextButton(onPressed: _cancelar, child: const Text('Cancelar')),
      ],
      _Fase.cancelando || _Fase.cobrandoAMano => [],
      _Fase.aprobado => [
        FilledButton(onPressed: _cerrar, child: const Text('Listo')),
      ],
      _Fase.error when _errorAlCancelar => [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
      _Fase.rechazado || _Fase.expirado || _Fase.error => [
        TextButton(onPressed: _cobrarAMano, child: const Text('Cobrar a mano')),
        FilledButton(onPressed: _reintentar, child: const Text('Reintentar')),
      ],
    };
  }
}
