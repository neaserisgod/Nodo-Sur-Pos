// Hoja "Abrir caja" (docs/03 H1): campo grande con la plata con la que se
// arranca. Abre la sesión de verdad (`abrirSesion`); sin la PC no se puede y
// la hoja lo dice en vez de fingir.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../servicio_companion.dart';

/// Devuelve `true` si la caja quedó abierta.
Future<bool> mostrarHojaAbrirCaja(BuildContext context, {required ServicioCompanion servicio, required int usuarioId}) async {
  int? sugerido;
  int? lata;
  try {
    final sesion = await servicio.sesion();
    if (sesion.abierta) return true;
    sugerido = sesion.fondoInicialSugeridoCentavos;
    lata = sesion.lataQueSeArrastraCentavos;
  } catch (_) {
    // Sin la sesión a mano igual se puede intentar abrir.
  }
  if (!context.mounted) return false;
  final abierta = await mostrarHojaNs<bool>(
    context,
    builder: (_) => _HojaAbrirCaja(servicio: servicio, usuarioId: usuarioId, sugeridoCentavos: sugerido, lataCentavos: lata),
  );
  return abierta ?? false;
}

class _HojaAbrirCaja extends StatefulWidget {
  const _HojaAbrirCaja({required this.servicio, required this.usuarioId, this.sugeridoCentavos, this.lataCentavos});

  final ServicioCompanion servicio;
  final int usuarioId;
  final int? sugeridoCentavos;
  final int? lataCentavos;

  @override
  State<_HojaAbrirCaja> createState() => _HojaAbrirCajaState();
}

class _HojaAbrirCajaState extends State<_HojaAbrirCaja> {
  late final TextEditingController _fondo = TextEditingController(
    text: widget.sugeridoCentavos == null ? '' : formatearARS(widget.sugeridoCentavos!, conSigno: false).replaceAll('.', ''),
  );
  bool _abriendo = false;
  String? _error;

  @override
  void dispose() {
    _fondo.dispose();
    super.dispose();
  }

  Future<void> _abrir() async {
    final texto = _fondo.text.trim();
    final int centavos;
    try {
      centavos = texto.isEmpty ? 0 : parsearARS(texto);
    } on FormatException {
      setState(() => _error = 'Fondo inicial inválido');
      return;
    }
    // El aviso sale después de cerrar la hoja: se toma el overlay ahora.
    final overlay = Overlay.of(context, rootOverlay: true);
    final navegador = Navigator.of(context);
    setState(() {
      _abriendo = true;
      _error = null;
    });
    try {
      await widget.servicio.abrirSesion(usuarioId: widget.usuarioId, fondoInicialCentavos: centavos);
      if (!mounted) return;
      navegador.pop(true);
      mostrarAvisoEnNs(overlay, 'Caja abierta con ${plataNs(centavos)}');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Abrir caja',
      texto: 'No hay caja abierta en la PC ahora mismo.',
      bloques: [
        CampoNs(etiqueta: 'Fondo inicial (caja normal)', controller: _fondo, grande: true, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs),
        if (widget.lataCentavos != null) InfoNs('Lata de cigarrillos: se arrastra sola, ya tiene ${plataNs(widget.lataCentavos!)} de antes — no hace falta contarla ahora.'),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, _abriendo ? 'Abriendo…' : 'Abrir caja y continuar', _abriendo ? null : _abrir, habilitado: !_abriendo),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
