// Hoja "Contar la caja" (docs/03 H2): contar la plata sin cerrar el día. Lo que se
// cuenta se guarda como arqueo del turno y queda precargado para el cierre.
// Muestra lo esperado de cada caja y, con los tres conteos, la diferencia en efectivo.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../cliente_companion.dart' show EstadoArqueoIntermedioCompanion;
import '../debounce.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

/// Devuelve `true` si el conteo quedó guardado.
Future<bool> mostrarHojaContarCaja(BuildContext context, {required ServicioCompanion servicio, required int usuarioId}) async {
  final guardado = await mostrarHojaNs<bool>(context, builder: (_) => _HojaContarCaja(servicio: servicio, usuarioId: usuarioId));
  return guardado ?? false;
}

class _HojaContarCaja extends StatefulWidget {
  const _HojaContarCaja({required this.servicio, required this.usuarioId});
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
      mostrarAvisoNs(context, 'Contá el efectivo, el Mercado Pago y la lata antes de guardar');
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
    final dif = e?.diferenciaCentavos;
    return HojaNs(
      titulo: 'Contar la caja',
      texto: 'Contá el efectivo del cajón, cigarrillos incluidos. No cierra la caja: lo que cuentes queda precargado para el cierre.',
      bloques: [
        _Esperado(clave: 'Efectivo esperado', valor: e == null ? '…' : plataNs(e.efectivoEsperadoCentavos)),
        _Esperado(clave: 'Mercado Pago esperado', valor: e == null ? '…' : plataNs(e.mpEsperadoCentavos)),
        _Esperado(clave: 'Lata esperada', valor: e == null ? '…' : plataNs(e.lataEsperadoCentavos)),
        CampoNs(etiqueta: 'Efectivo contado', controller: _efectivo, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        CampoNs(etiqueta: 'Mercado Pago contado', controller: _mp, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        CampoNs(etiqueta: 'Lata contada', controller: _lata, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => _alCambiar()),
        if (_completo && dif != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(color: dif == 0 ? ns.gbg : ns.bbg, borderRadius: BorderRadius.circular(22)),
            child: Row(
              children: [
                Expanded(child: Text('Diferencia en efectivo', style: estiloNs(15, color: dif == 0 ? ns.g : ns.b))),
                Text(dif == 0 ? 'Cuadró' : (dif < 0 ? 'Faltan ${plataNs(-dif)}' : 'Sobran ${plataNs(dif)}'), style: estiloNs(17, peso: FontWeight.w600, color: dif == 0 ? ns.g : ns.b, tabular: true)),
              ],
            ),
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

class _Esperado extends StatelessWidget {
  const _Esperado({required this.clave, required this.valor});
  final String clave;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Expanded(child: Text(clave, style: estiloNs(15, color: ns.mute))),
          Text(valor, style: estiloNs(19, peso: FontWeight.w600, color: ns.ink, tabular: true)),
        ],
      ),
    );
  }
}
