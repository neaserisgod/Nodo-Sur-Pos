// Hoja "Contar la caja" (docs/03 H2): contar la plata sin cerrar el día. Lo que se
// cuenta se guarda como arqueo del turno y queda precargado para el cierre.
// Muestra lo esperado de cada caja y, con los tres conteos, la diferencia en efectivo.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../cliente_companion.dart' show EstadoArqueoIntermedioCompanion;
import '../debounce.dart';
import '../app_ns.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import 'hoja_abrir_caja_ns.dart';
import '../servicio_companion.dart';

/// Devuelve `true` si el conteo quedó guardado. Con la caja cerrada no hay nada que contar: la hoja lo dice y ofrece abrirla.
Future<bool> mostrarHojaContarCaja(BuildContext context, {required ServicioCompanion servicio, required int usuarioId}) async {
  final app = AppNs.of(context);
  if (!app.cajaAbierta) {
    final abrir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Contar la caja',
        texto: 'No hay caja abierta en la PC ahora mismo. Para contar, primero abrí la caja.',
        bloques: const [InfoNs('Caja cerrada', tono: TonoNs.warn)],
        botones: [
          BotonNs.primario(ctx, 'Abrir caja', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Cerrar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (abrir == true && context.mounted) await mostrarHojaAbrirCaja(context, servicio: servicio, usuarioId: usuarioId);
    return false;
  }
  final pend = app.pendientes.value;
  final guardado = await mostrarHojaNs<bool>(
    context,
    builder: (_) => _HojaContarCaja(servicio: servicio, usuarioId: usuarioId, vencidoHace: pend.arqueoVencido ? duracionTextoNs(pend.minutosDesdeConteo) : null),
  );
  return guardado ?? false;
}

class _HojaContarCaja extends StatefulWidget {
  const _HojaContarCaja({required this.servicio, required this.usuarioId, this.vencidoHace});
  final String? vencidoHace;
  final ServicioCompanion servicio;
  final int usuarioId;

  @override
  State<_HojaContarCaja> createState() => _HojaContarCajaState();
}

class _HojaContarCajaState extends State<_HojaContarCaja> {
  final _efectivo = TextEditingController();
  final _mp = TextEditingController();
  final _lata = TextEditingController();
  final _debouncer = Debouncer();
  EstadoArqueoIntermedioCompanion? _estado;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void dispose() {
    _efectivo.dispose();
    _mp.dispose();
    _lata.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  int? _centavos(TextEditingController c) {
    final d = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    return d.isEmpty ? null : int.parse(d) * centavosPorPeso;
  }

  bool get _completo => _centavos(_efectivo) != null && _centavos(_mp) != null && _centavos(_lata) != null;

  /// Vista previa en vivo (no guarda nada): trae lo esperado y la diferencia.
  Future<void> _calcular() async {
    try {
      final e = await widget.servicio.calcularArqueoIntermedio(
        efectivoContadoCentavos: _centavos(_efectivo) ?? 0,
        mpContadoCentavos: _centavos(_mp),
        lataContadoCentavos: _centavos(_lata),
      );
      if (mounted) setState(() => _estado = e);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _guardar() async {
    if (!_completo) {
      mostrarAvisoNs(context, 'Falta el efectivo contado, el MP contado o la lata contada');
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final navegador = Navigator.of(context);
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.confirmarArqueoIntermedio(
        usuarioId: widget.usuarioId,
        efectivoContadoCentavos: _centavos(_efectivo)!,
        mpContadoCentavos: _centavos(_mp)!,
        lataContadoCentavos: _centavos(_lata)!,
      );
      if (!mounted) return;
      navegador.pop(true);
      mostrarAvisoEnNs(overlay, 'Conteo guardado');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final e = _estado;
    final dif = e == null || _centavos(_efectivo) == null ? null : _centavos(_efectivo)! - e.efectivoEsperadoCentavos;
    return HojaNs(
      titulo: 'Contar la caja',
      texto: 'Contá el efectivo del cajón, cigarrillos incluidos. Es opcional: lo que cuentes queda precargado en el cierre.',
      bloques: [
        if (widget.vencidoHace != null) InfoNs('Pasaron ${widget.vencidoHace} desde el último conteo.', tono: TonoNs.warn),
        FilaClaveValorNs(clave: 'Caja esperada', valor: e == null ? '…' : plataNs(e.efectivoEsperadoCentavos)),
        FilaClaveValorNs(clave: 'MP esperado', valor: e == null ? '…' : plataNs(e.mpEsperadoCentavos)),
        FilaClaveValorNs(clave: 'Lata esperada', valor: e == null ? '…' : plataNs(e.lataEsperadoCentavos)),
        CampoNs(etiqueta: 'Efectivo contado', controller: _efectivo, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        CampoNs(etiqueta: 'MP contado (según la app de Mercado Pago)', controller: _mp, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        CampoNs(etiqueta: 'Lata contada', controller: _lata, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        if (_completo && dif != null)
          FilaClaveValorNs(
            clave: 'Diferencia en efectivo',
            valor: dif == 0 ? 'Cuadró' : (dif < 0 ? 'Faltan ${plataNs(-dif)}' : 'Sobran ${plataNs(dif)}'),
            colorValor: dif == 0 ? ns.g : ns.b,
            sinLinea: true,
          ),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs(
          texto: _guardando ? 'Guardando…' : 'Guardar conteo',
          onTap: _guardando ? null : _guardar,
          alto: 60,
          tamanio: 17,
          fondo: _completo ? ns.prim : ns.s,
          color: _completo ? TokensNs.blanco : ns.mute,
          habilitado: !_guardando,
        ),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }

  void _alCambiar() {
    setState(() {});
    _debouncer.ejecutar(_calcular);
  }
}
