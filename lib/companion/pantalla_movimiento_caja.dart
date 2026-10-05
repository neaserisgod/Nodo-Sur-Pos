// "Gasto o ingreso", tal cual el mock (docs/03 C2): anotar la plata que sale o
// entra de la caja sin ser una venta. Una sola pantalla para los dos (El dueño,
// 2026-09-18: gasto e ingreso rápidos se fusionaron). Con la caja cerrada ofrece
// abrirla ahí mismo. Además de "Cajón normal" y "Mercado Pago" del mock, sigue la
// "Lata cigarrillos" que la app ya tenía.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import 'app_ns.dart';
import 'cliente_companion.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';

enum TipoMovimientoCaja { gasto, ingreso }

class PantallaMovimientoCaja extends StatefulWidget {
  const PantallaMovimientoCaja({super.key, this.tipoInicial = TipoMovimientoCaja.gasto});

  final TipoMovimientoCaja tipoInicial;

  @override
  State<PantallaMovimientoCaja> createState() => _PantallaMovimientoCajaState();
}

class _PantallaMovimientoCajaState extends State<PantallaMovimientoCaja> {
  late TipoMovimientoCaja _tipo = widget.tipoInicial;
  final _montoCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  MedioGastoCompanion _medio = MedioGastoCompanion.cajonNormal;
  bool _guardando = false;
  bool _guardado = false;
  String? _error;
  final _fondoCtrl = TextEditingController();
  int? _lataArrastra;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarSesion());
  }

  /// Con la caja cerrada: el fondo sugerido y cuánto trae la lata de antes.
  Future<void> _cargarSesion() async {
    final app = AppNs.of(context);
    if (app.cajaAbierta || app.servicio == null) return;
    try {
      final sesion = await app.servicio!.sesion();
      if (!mounted) return;
      setState(() {
        _lataArrastra = sesion.lataQueSeArrastraCentavos;
        if (sesion.fondoInicialSugeridoCentavos != null && _fondoCtrl.text.isEmpty) _fondoCtrl.text = '${sesion.fondoInicialSugeridoCentavos! ~/ centavosPorPeso}';
      });
    } catch (_) {
      // Sin la sesión a mano igual se puede abrir.
    }
  }

  Future<void> _abrirCaja(ControladorAppNs app) async {
    final servicio = app.servicio;
    final usuario = app.usuarioId;
    if (servicio == null || usuario == null) return;
    final centavos = (int.tryParse(_fondoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * centavosPorPeso;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await servicio.abrirSesion(usuarioId: usuario, fondoInicialCentavos: centavos);
      if (!mounted) return;
      mostrarAvisoNs(context, 'Caja abierta con ${plataNs(centavos)}');
      await app.refrescar();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _motivoCtrl.dispose();
    _fondoCtrl.dispose();
    super.dispose();
  }

  int get _montoCentavos => (int.tryParse(_montoCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * centavosPorPeso;

  Future<void> _guardar() async {
    final app = AppNs.of(context);
    if (_montoCentavos <= 0) {
      mostrarAvisoNs(context, 'Escribí el monto');
      return;
    }
    final servicio = app.servicio;
    final sesionId = app.sesion?.id;
    final usuarioId = app.usuarioId;
    if (servicio == null || sesionId == null || usuarioId == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_tipo == TipoMovimientoCaja.gasto) {
        await servicio.registrarGasto(sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: _montoCentavos, medio: _medio, motivo: _motivoCtrl.text);
      } else {
        await servicio.registrarIngreso(sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: _montoCentavos, medio: _medio, motivo: _motivoCtrl.text);
      }
      if (!mounted) return;
      // Guardar limpia el monto y el motivo y muestra el aviso verde (el esperado de caja cambió).
      setState(() {
        _montoCtrl.clear();
        _motivoCtrl.clear();
        _guardado = true;
      });
      await app.refrescar();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    final gasto = _tipo == TipoMovimientoCaja.gasto;
    final listo = _montoCentavos > 0 && !_guardando;
    final cajas = [
      ('Cajón normal', MedioGastoCompanion.cajonNormal),
      ('Lata cigarrillos', MedioGastoCompanion.lata),
      ('Mercado Pago', MedioGastoCompanion.mercadoPago),
    ];
    return Scaffold(
      backgroundColor: ns.paper,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CabeceraSubNs(titulo: 'Gasto o ingreso', onVolver: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                if (!app.cajaAbierta)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              const InfoNs('No hay caja abierta en la PC ahora mismo.', tono: TonoNs.warn, tamanio: 15, peso: FontWeight.w600),
                              const SizedBox(height: 10),
                              CampoNs(etiqueta: 'Fondo inicial (caja normal)', controller: _fondoCtrl, grande: true, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {})),
                              if (_lataArrastra != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                                  child: Text('Lata de cigarrillos: se arrastra sola, ya tiene ${plataNs(_lataArrastra!)} de antes — no hace falta contarla ahora.', style: estiloNs(14, altura: 1.4, color: ns.mute)),
                                ),
                              if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        BotonNs.primario(context, _guardando ? 'Abriendo…' : 'Abrir caja y continuar', _guardando ? null : () => _abrirCaja(app), alto: 64, tamanio: 18, habilitado: !_guardando),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Anotá la plata que sale o entra de la caja sin ser una venta.', style: estiloNs(15, altura: 1.4, color: ns.mute)),
                        const SizedBox(height: 14),
                        SegmentoNs(
                          opciones: const ['Sale plata', 'Entra plata'],
                          indice: gasto ? 0 : 1,
                          alto: 48,
                          onCambio: (i) => setState(() {
                            _tipo = i == 0 ? TipoMovimientoCaja.gasto : TipoMovimientoCaja.ingreso;
                            _guardado = false;
                          }),
                        ),
                        const SizedBox(height: 14),
                        Text(gasto ? 'De dónde sale la plata' : 'A dónde entra la plata', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (var i = 0; i < cajas.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: PresionNs(
                                  onTap: () => setState(() => _medio = cajas[i].$2),
                                  etiqueta: cajas[i].$1,
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    decoration: BoxDecoration(color: _medio == cajas[i].$2 ? ns.prim : ns.s, borderRadius: BorderRadius.circular(999)),
                                    alignment: Alignment.center,
                                    child: Text(cajas[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w600, color: _medio == cajas[i].$2 ? TokensNs.blanco : ns.ink)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        CampoNs(
                          etiqueta: 'Monto',
                          controller: _montoCtrl,
                          placeholder: '\$ 0',
                          radio: 30,
                          teclado: TextInputType.number,
                          formatos: soloDigitosNs,
                          onChanged: (_) => setState(() => _guardado = false),
                          estiloGrande: 46,
                        ),
                        const SizedBox(height: 14),
                        CampoNs(
                          etiqueta: 'Motivo (opcional)',
                          controller: _motivoCtrl,
                          placeholder: 'Ej: compra de cambio',
                          radio: 26,
                          onChanged: (_) => setState(() => _guardado = false),
                        ),
                        const Spacer(),
                        if (_error != null) ...[InfoNs(_error!, tono: TonoNs.bad), const SizedBox(height: 14)],
                        if (_guardado) ...[EntradaNs(child: InfoNs('Listo: el movimiento quedó anotado en la caja.', tono: TonoNs.good, peso: FontWeight.w600, tamanio: 15)), const SizedBox(height: 14)],
                        BotonNs(
                          texto: gasto ? 'Anotar gasto' : 'Anotar ingreso',
                          onTap: _guardar,
                          alto: 64,
                          tamanio: 18,
                          fondo: listo ? ns.prim : ns.s,
                          color: listo ? TokensNs.blanco : ns.mute,
                          habilitado: !_guardando,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
