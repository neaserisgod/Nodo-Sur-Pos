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
import '../domain/venta.dart';
import '../servicios/avisos_cobro_mp.dart';
import 'cliente_companion.dart' show ErrorCompanion;
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'kit/kit_ns.dart';

/// Devuelve `(ventaId, totalCentavos, aMano)` si se aprobó y se grabó la venta,
/// `null` en cualquier otro cierre (cancelado, rechazado sin reintentar).
/// [montoCentavos] ya viene con el descuento aplicado (lo calculó
/// `PantallaCarritoVenta` antes de abrir este diálogo) — [tipoDescuento]/
/// [valorDescuento] viajan igual, para que `iniciarCobroPosnet`/
/// `confirmarCobroPosnet` recalculen el mismo total del lado del servidor.
Future<({int ventaId, int totalCentavos, bool aMano})?> mostrarDialogoCobroPosnetCompanion(
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
  int? montoEfectivoMixtoCentavos,
  int? turnoId,
}) {
  return mostrarHojaNs<({int ventaId, int totalCentavos, bool aMano})?>(
    context,
    descartable: false,
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
      montoEfectivoMixtoCentavos: montoEfectivoMixtoCentavos,
      turnoId: turnoId,
    ),
  );
}

enum _Fase {
  creando,
  esperando,
  cancelando,
  cobrandoAMano,
  guardandoVenta,
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
    this.montoEfectivoMixtoCentavos,
    this.turnoId,
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

  /// El turno de la agenda que esta venta cobra (Regla 21): su seña se descuenta y queda cobrado.
  final int? turnoId;

  /// Con valor, la venta es mixta: [montoCentavos] es solo la parte que va a la terminal.
  final int? montoEfectivoMixtoCentavos;

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
  ({int ventaId, int totalCentavos, bool aMano})? _resultadoAprobado;

  /// La terminal ya aprobó el pago: el cliente PAGÓ. Desde acá, "Reintentar" no puede crear otra orden (cobraría dos veces) ni
  /// "Cobrar a mano" grabar otra venta (quizá la primera sí se guardó y solo se perdió la respuesta): lo único seguro es volver a
  /// pedir que se guarde ESTA venta, que el servidor resuelve de forma idempotente (misma orden = misma venta).
  bool _pagoAprobado = false;

  /// Cuántas veces se intenta guardar la venta antes de mostrar el error, y cuánto se espera entre una y otra (sin red un momento).
  static const _intentosDeGuardado = 4;
  Duration esperaEntreIntentosDeGuardado(int intento) => Duration(seconds: 1 << intento); // 1, 2, 4 s

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
        montoEfectivoMixtoCentavos: widget.montoEfectivoMixtoCentavos,
        turnoId: widget.turnoId,
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
        _pagoAprobado = true;
        await _guardarVentaAprobada();
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

  /// Graba la venta de un pago ya aprobado. Un corte de red NO es un rechazo: se reintenta solo unas veces (el servidor es
  /// idempotente por orden, así que repetir nunca duplica la venta) antes de pedirle algo a la persona. Una respuesta del servidor
  /// (`ErrorCompanion`: por ejemplo "la caja ya se cerró") es definitiva y se muestra de una.
  Future<void> _guardarVentaAprobada() async {
    if (mounted) setState(() => _fase = _Fase.guardandoVenta);
    Object? ultimoError;
    for (var intento = 0; intento < _intentosDeGuardado; intento++) {
      if (intento > 0) await Future<void>.delayed(esperaEntreIntentosDeGuardado(intento));
      if (!mounted) return;
      try {
        final r = await widget.cliente.confirmarCobroPosnet(
          ordenPendienteId: _ordenPendienteId!,
          lineas: widget.lineas,
          canal: widget.canal,
          sesionCajaId: widget.sesionCajaId,
          usuarioId: widget.usuarioId,
          tipoDescuento: widget.tipoDescuento,
          valorDescuento: widget.valorDescuento,
          montoEfectivoMixtoCentavos: widget.montoEfectivoMixtoCentavos,
          encargueId: widget.encargueId,
          turnoId: widget.turnoId,
        );
        _resultadoAprobado = (ventaId: r.ventaId, totalCentavos: r.totalCentavos, aMano: false);
        if (mounted) setState(() => _fase = _Fase.aprobado);
        return;
      } on ErrorCompanion catch (e) {
        ultimoError = e;
        break;
      } catch (e) {
        ultimoError = e;
      }
    }
    if (!mounted) return;
    setState(() {
      _fase = _Fase.error;
      _error = 'El pago YA se cobró en la terminal, pero no se pudo guardar la venta: ${mensajeDeError(ultimoError!)} '
          'No cobres de nuevo: tocá Reintentar para guardarla.';
    });
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
        montoEfectivoMixtoCentavos: widget.montoEfectivoMixtoCentavos,
        encargueId: widget.encargueId,
        turnoId: widget.turnoId,
      );
      if (mounted) Navigator.of(context).pop((ventaId: resultado.ventaId, totalCentavos: resultado.totalCentavos, aMano: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = 'No se pudo grabar la venta: ${mensajeDeError(e)}';
      });
    }
  }

  void _cerrar() => Navigator.of(context).pop(_resultadoAprobado);

  static const _textoSinPc = 'No se pudo conectar con la PC — revisá que esté prendida, con la app abierta, y que el celular esté en la misma WiFi.';

  String get _nombreCanal => switch (widget.canal) {
    canalDebito => 'Débito',
    canalCredito => 'Crédito',
    canalQr => 'QR',
    _ => 'Mercado Pago',
  };

  /// Hoja de la terminal del mock (09 · estados de la terminal): una sola hoja "Cobrar por QR / Débito / Crédito" que cambia de
  /// bloque según el estado. No se cierra tocando afuera.
  @override
  Widget build(BuildContext context) {
    final monto = plataNs(widget.montoCentavos);
    final List<Widget> bloques = switch (_fase) {
      _Fase.creando => [FilaEsperaNs('Enviando la orden a la terminal — $monto')],
      _Fase.esperando => [FilaEsperaNs(_enTerminal ? 'El cliente tiene que confirmar en la terminal — $monto' : 'Esperando el pago — $monto')],
      _Fase.cancelando => [const FilaEsperaNs('Cancelando en la terminal...')],
      _Fase.cobrandoAMano || _Fase.guardandoVenta => [FilaEsperaNs('Grabando la venta — $monto')],
      _Fase.aprobado => [HeroHojaNs(rotulo: 'Pago aprobado', cifra: monto, apoyo: _nombreCanal)],
      _Fase.rechazado => [const InfoNs('El pago no se aprobó en la terminal.', tono: TonoNs.warn), const InfoNs('Todavía no se cobró nada.')],
      _Fase.expirado => [const InfoNs('No se pudo confirmar el pago a tiempo. Revisá la terminal.', tono: TonoNs.warn)],
      _Fase.error when _pagoAprobado => [InfoNs(_error ?? '', tono: TonoNs.bad), HeroHojaNs(rotulo: 'Ya cobrado', cifra: monto, apoyo: _nombreCanal)],
      _Fase.error => [InfoNs(_error ?? _textoSinPc, tono: TonoNs.warn)],
    };
    return PopScope(
      canPop: false,
      child: HojaNs(titulo: 'Cobrar por $_nombreCanal', bloques: bloques, botones: _botones()),
    );
  }

  List<Widget> _botones() {
    return switch (_fase) {
      _Fase.creando || _Fase.esperando => [BotonNs.secundario(context, 'Cancelar', _cancelar)],
      _Fase.cancelando || _Fase.cobrandoAMano || _Fase.guardandoVenta => [],
      _Fase.aprobado => [BotonNs.primario(context, 'Listo', _cerrar)],
      _Fase.error when _errorAlCancelar => [BotonNs.primario(context, 'Cerrar', () => Navigator.of(context).pop())],
      // Pago ya aprobado: solo se puede volver a guardar ESTA venta (o cerrar y revisarla en el cierre: la orden queda "sin resolver").
      _Fase.error when _pagoAprobado => [
        BotonNs.primario(context, 'Reintentar', _guardarVentaAprobada),
        BotonNs.secundario(context, 'Cerrar', () => Navigator.of(context).pop()),
      ],
      // El mock no dibuja "Cancelar" acá, pero sin salida la hoja (que no se cierra tocando afuera) dejaba a la persona encerrada.
      _Fase.rechazado || _Fase.expirado || _Fase.error => [
        BotonNs.primario(context, 'Reintentar', _reintentar),
        BotonNs.secundario(context, 'Cobrar a mano', _cobrarAMano),
        BotonNs.texto(context, 'Cancelar', () => Navigator.of(context).pop()),
      ],
    };
  }
}
