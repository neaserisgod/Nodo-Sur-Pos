// Cobro por terminal Point (Fase 12): crea la orden, poll de
// `GET /v1/orders/{id}` cada 2s hasta 60s, cancelable en cualquier
// momento. La venta se graba recién si se aprueba — nunca antes
// (`VentaControlador.confirmarCobroPosnetAprobado`).
//
// Un timeout (se acabaron los 60s sin resolver) NO marca la orden como
// rechazada ni cancelada: se deja tal cual, en 'pendiente', para que
// aparezca en el Cierre como "no sé si se cobró" — Regla de esta fase,
// nunca se asume un resultado que no se confirmó. Un cancel explícito de
// Bruno (el botón "Cancelar") le avisa a Mercado Pago (`POST
// /v1/orders/{id}/cancel`) además de anotarlo acá — sin eso la terminal se
// queda mostrando "esperando pago" aunque la app ya haya cerrado el
// diálogo (bug real, Bruno: "cuando cancelo el QR no cancela el
// dispositivo"). Esto solo funciona mientras la orden sigue en
// `status=created`: apenas llega a la terminal física (`at_terminal`, casi
// instantáneo) Mercado Pago ya no permite cancelarla por API — verificado
// contra el posnet real, ver `TRAMPAS.md`. En ese caso (el más común, dado
// lo rápido que pasa) el error se traduce a "cancelala a mano ahí" y la
// fila queda en 'pendiente', mismo criterio que el timeout: nunca se asume
// una cancelación que no se confirmó.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/cobro_posnet.dart';
import '../../domain/cobro_posnet.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'venta_controlador.dart';

Future<void> mostrarDialogoCobroPosnet(
  BuildContext context, {
  required VentaControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoCobroPosnet(controlador: controlador),
  );
}

enum _Fase {
  creando,
  esperando,
  cancelando,
  aprobado,
  rechazado,
  expirado,
  error,
}

class _DialogoCobroPosnet extends StatefulWidget {
  const _DialogoCobroPosnet({required this.controlador});
  final VentaControlador controlador;

  @override
  State<_DialogoCobroPosnet> createState() => _DialogoCobroPosnetState();
}

class _DialogoCobroPosnetState extends State<_DialogoCobroPosnet> {
  _Fase _fase = _Fase.creando;
  String? _error;
  int? _ordenPendienteId;
  String? _ordenIdMp;
  bool _cancelado = false;

  /// Distingue el error de cancelar (solo queda "Cerrar" — no hay nada que
  /// reintentar, la venta no se hizo) del error de crear/consultar la
  /// orden (donde sí tiene sentido "Reintentar"/"Cobrar a mano").
  bool _errorAlCancelar = false;

  // Capturados al abrir, no leídos de nuevo en cada build: `cobrarActual()`
  // (fase aprobado) vacía el carrito, y ahí `controlador.montoParaPosnet`
  // ya no tiene un `resultado` del que sacar el total — mostrar el monto
  // que se cobró de verdad no puede depender de un estado que cambia
  // debajo del diálogo.
  late final String _canal = widget.controlador.canalElegido == 'qr'
      ? 'QR'
      : 'Débito';
  late final String _monto = formatearARS(widget.controlador.montoParaPosnet);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final orden = await widget.controlador.iniciarCobroPosnet();
      if (_cancelado) {
        // Bruno canceló mientras la orden se estaba creando: ya existe del
        // lado de Mercado Pago (el POST recién terminó), así que no basta
        // con haber dejado de esperar acá — hay que cancelarla ahí
        // también, o la terminal se queda esperando el pago igual.
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
    } on CobroPosnetException catch (e) {
      if (_cancelado) {
        // La creación falló y además se había pedido cancelar: no llegó a
        // existir ninguna orden del lado de MP, no hay nada que cancelar.
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = e.toString();
      });
    }
  }

  // Cuenta intentos, no compara contra un reloj de pared: un timeout basado
  // en `DateTime.now()` depende de que el reloj real avance, y en los tests
  // de widget el tiempo virtual de `Future.delayed` no mueve esa aguja —
  // quedaba en un loop que nunca expiraba. Contar intentos sobre el mismo
  // `Future.delayed` que ya gobierna el ritmo del polling da el mismo
  // resultado en producción (30 x 2s = 60s) y es determinístico en tests.
  Future<void> _pollear() async {
    final intentos =
        timeoutPollingCobroPosnet.inMilliseconds ~/ intervaloPollingCobroPosnet.inMilliseconds;
    for (var i = 0; i < intentos && mounted && !_cancelado; i++) {
      await Future.delayed(intervaloPollingCobroPosnet);
      if (!mounted || _cancelado) return;

      final ResultadoOrdenCobro resultado;
      try {
        resultado = await widget.controlador.consultarEstadoPosnet(_ordenIdMp!);
      } on CobroPosnetException catch (e) {
        if (!mounted) return;
        setState(() {
          _fase = _Fase.error;
          _error = e.toString();
        });
        return;
      }
      if (!mounted || _cancelado) return;

      if (resultado == ResultadoOrdenCobro.aprobada) {
        await widget.controlador.confirmarCobroPosnetAprobado(
          _ordenPendienteId!,
        );
        if (mounted) setState(() => _fase = _Fase.aprobado);
        return;
      }
      if (resultado == ResultadoOrdenCobro.rechazada) {
        await widget.controlador.resolverCobroPosnetNoAprobado(
          _ordenPendienteId!,
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

  /// Si ya hay un id de orden (fase "esperando"), la cancela ahí mismo. Si
  /// todavía se está creando (fase "creando"), solo marca la intención —
  /// `_iniciar()` la cancela apenas la creación termine, en cuanto sepa si
  /// llegó a existir del lado de Mercado Pago o no.
  void _cancelar() {
    _cancelado = true;
    final id = _ordenPendienteId;
    if (id == null) {
      setState(() => _fase = _Fase.cancelando);
      return;
    }
    _ejecutarCancelacion(ordenPendienteId: id, ordenIdMp: _ordenIdMp);
  }

  /// Le avisa a Mercado Pago que cancele la orden (así la terminal deja de
  /// esperar el pago) y recién después cierra el diálogo. Si la
  /// cancelación en sí falla, la fila queda `'pendiente'`
  /// (`VentaControlador.cancelarCobroPosnet`, nunca se asume que quedó
  /// cancelada sin confirmación) y acá se avisa para que se cancele a mano
  /// en la terminal.
  Future<void> _ejecutarCancelacion({
    required int ordenPendienteId,
    String? ordenIdMp,
  }) async {
    if (mounted) setState(() => _fase = _Fase.cancelando);
    try {
      await widget.controlador.cancelarCobroPosnet(
        ordenPendienteId,
        ordenIdMp: ordenIdMp,
      );
      if (mounted) Navigator.of(context).pop();
    } on CobroPosnetException catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _errorAlCancelar = true;
        _error =
            'No se pudo cancelar automáticamente: $e '
            'Cancelala a mano en la terminal si sigue esperando el pago — '
            'quedó anotada para revisar en el cierre.';
      });
    }
  }

  Future<void> _cobrarAMano() async {
    await widget.controlador.cobrarActual();
    if (mounted) Navigator.of(context).pop();
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

  void _cerrar() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Cobrar por $_canal',
      contenido: _contenido(_canal, _monto),
      botones: _botones(),
    );
  }

  Widget _contenido(String canal, String monto) {
    return switch (_fase) {
      _Fase.creando => _filaCargando(
        'Enviando la orden a la terminal — $monto',
      ),
      _Fase.esperando => _filaCargando('Esperando el pago por $canal — $monto'),
      _Fase.cancelando => _filaCargando('Cancelando en la terminal...'),
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
        const SizedBox(width: Espaciado.md),
        Flexible(child: Text(texto)),
      ],
    );
  }

  List<Widget> _botones() {
    return switch (_fase) {
      _Fase.creando || _Fase.esperando => [
        BotonSecundario(texto: 'Cancelar', onPressed: _cancelar),
      ],
      // Sin botones mientras se confirma la cancelación en la terminal —
      // ya se pidió, no hay nada más que ofrecer hasta que responda.
      _Fase.cancelando => [],
      _Fase.aprobado => [BotonPrimario(texto: 'Listo', onPressed: _cerrar)],
      // La cancelación en sí falló: no hubo venta, no hay nada que
      // reintentar ni cobrar a mano, solo cerrar y anotarlo (ver aviso en
      // Cierre).
      _Fase.error when _errorAlCancelar => [
        BotonPrimario(texto: 'Cerrar', onPressed: _cerrar),
      ],
      _Fase.rechazado || _Fase.expirado || _Fase.error => [
        BotonSecundario(texto: 'Cobrar a mano', onPressed: _cobrarAMano),
        BotonPrimario(texto: 'Reintentar', onPressed: _reintentar),
      ],
    };
  }
}
