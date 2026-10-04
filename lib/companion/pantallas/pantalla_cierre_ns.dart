// Cerrar caja, tal cual el mock (docs/03 D1): tres pasos (efectivo, Mercado Pago,
// lata) y el resultado. Una diferencia con el mock, a propósito: el mock da por
// cerrada la caja al ver el resultado, pero una caja cerrada no se reabre, así
// que acá el resultado primero se revisa ("Cerrar caja" lo confirma de verdad y
// "Volver a contar" corrige un conteo) y recién después dice "Caja cerrada".

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../app_ns.dart';
import '../cliente_companion.dart' show ResumenCierreCompanion;
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../seccion_extra_cierre_companion.dart';
import '../servicio_companion.dart';
import '../servicio_companion_offline.dart';

class PantallaCierreNs extends StatefulWidget {
  const PantallaCierreNs({super.key, required this.servicio, required this.usuarioId, this.precargaEfectivoCentavos, this.precargaMpCentavos, this.horaPrecarga});

  final ServicioCompanion servicio;
  final int usuarioId;

  /// Lo contado en el último arqueo del turno: el cierre arranca con eso cargado.
  final int? precargaEfectivoCentavos;
  final int? precargaMpCentavos;
  final DateTime? horaPrecarga;

  @override
  State<PantallaCierreNs> createState() => _PantallaCierreNsState();
}

enum _Etapa { conteo, resultado, cerrada }

class _PantallaCierreNsState extends State<PantallaCierreNs> {
  _Etapa _etapa = _Etapa.conteo;
  int _paso = 0;

  late final _efectivo = TextEditingController(text: _pesos(widget.precargaEfectivoCentavos));
  late final _mp = TextEditingController(text: _pesos(widget.precargaMpCentavos));
  final _lata = TextEditingController();
  final _nota = TextEditingController();

  ResumenCierreCompanion? _resumen;
  bool _trabajando = false;
  String? _error;

  static String _pesos(int? centavos) => centavos == null ? '' : '${centavos ~/ centavosPorPeso}';

  @override
  void dispose() {
    _efectivo.dispose();
    _mp.dispose();
    _lata.dispose();
    _nota.dispose();
    super.dispose();
  }

  TextEditingController get _campo => [_efectivo, _mp, _lata][_paso];

  int? _centavos(TextEditingController c) {
    final d = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    return d.isEmpty ? null : int.parse(d) * centavosPorPeso;
  }

  Future<void> _siguiente() async {
    if (_centavos(_campo) == null) {
      mostrarAvisoNs(context, 'Escribí cuánto contaste');
      return;
    }
    if (_paso < 2) {
      setState(() => _paso++);
      return;
    }
    // "Ver si cuadra": vista previa, todavía no guarda nada.
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final r = await widget.servicio.calcularCierre(
        efectivoContadoCentavos: _centavos(_efectivo)!,
        mpContadoCentavos: _centavos(_mp),
        lataContadoCentavos: _centavos(_lata),
      );
      if (mounted) {
        setState(() {
          _resumen = r;
          _etapa = _Etapa.resultado;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _cerrarDeVerdad() async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await widget.servicio.confirmarCierre(
        usuarioId: widget.usuarioId,
        efectivoContadoCentavos: _centavos(_efectivo)!,
        mpContadoCentavos: _centavos(_mp)!,
        lataContadoCentavos: _centavos(_lata)!,
        nota: _nota.text,
      );
      if (mounted) setState(() => _etapa = _Etapa.cerrada);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _atras() {
    if (_etapa == _Etapa.resultado) {
      setState(() {
        _etapa = _Etapa.conteo;
        _paso = 2;
        _error = null;
      });
    } else if (_etapa == _Etapa.conteo && _paso > 0) {
      setState(() => _paso--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _listo() async {
    final app = AppNs.of(context);
    Navigator.of(context).pop(true);
    await app.refrescar();
    app.irAPestania(PestaniaNs.caja);
  }

  static const _pasos = [
    ('¿Cuánta plata hay en el cajón?', 'Contá billetes y monedas. Incluí los cigarrillos si los guardás ahí.', 'Efectivo contado'),
    ('¿Cuánto hay en Mercado Pago?', 'Mirá el saldo del día en la app de Mercado Pago.', 'Mercado Pago'),
    ('¿Cuánto hay en la lata de cigarrillos?', 'Contá lo que hay en la lata, solo la plata.', 'Lata de cigarrillos'),
  ];

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final cerrada = _etapa == _Etapa.cerrada;
    return PopScope(
      canPop: _etapa == _Etapa.conteo && _paso == 0 || cerrada,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _atras();
      },
      child: Scaffold(
        backgroundColor: ns.paper,
        body: SafeArea(
          child: PantallaEntradaNs(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CabeceraSubNs(titulo: cerrada ? 'Caja cerrada' : 'Cerrar caja', tamanio: 32, onVolver: _atras),
                  const SizedBox(height: 14),
                  Expanded(child: _etapa == _Etapa.conteo ? _conteo(context) : _resultadoVista(context)),
                  const SizedBox(height: 14),
                  ..._botones(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _conteo(BuildContext context) {
    final ns = context.ns;
    final (pregunta, pista, etiqueta) = _pasos[_paso];
    final precargado = _paso == 0 && widget.precargaEfectivoCentavos != null && widget.horaPrecarga != null;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PASO ${_paso + 1} DE 3', style: seccionNs(ns.mute)),
              const SizedBox(height: 8),
              Text(pregunta, style: tituloNs(34, track: -0.05, altura: 1.08, color: ns.ink)),
            ],
          ),
        ),
        InfoNs(pista, tamanio: 15),
        if (precargado) ...[
          const SizedBox(height: 10),
          InfoNs('Precargado con el arqueo de las ${widget.horaPrecarga!.hour.toString().padLeft(2, '0')}:${widget.horaPrecarga!.minute.toString().padLeft(2, '0')}. Si vendiste o sacaste plata después, corregilo.', tamanio: 14),
        ],
        if (widget.servicio is ServicioCompanionOffline) ...[
          const SizedBox(height: 10),
          const InfoNs('Sin conexión con la PC: este cierre se calcula con los datos ya sincronizados a este celular. Si algo de la PC todavía no llegó, puede no coincidir.', tono: TonoNs.warn),
        ],
        const SizedBox(height: 10),
        CampoNs(
          key: ValueKey(_paso),
          etiqueta: etiqueta,
          controller: _campo,
          grande: true,
          placeholder: '\$ 0',
          teclado: TextInputType.number,
          formatos: soloDigitosNs,
          autofoco: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_paso == 2) ...[const SizedBox(height: 10), CampoNs(etiqueta: 'Nota (opcional)', controller: _nota, placeholder: 'Ej: faltó cambio')],
        if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
      ],
    );
  }

  Widget _resultadoVista(BuildContext context) {
    final ns = context.ns;
    final r = _resumen!;
    final de = r.diferenciaCentavos;
    final dm = r.mpDiferenciaCentavos ?? 0;
    final dl = r.lataDiferenciaCentavos ?? 0;
    final todo = de == 0 && dm == 0 && dl == 0;

    String texto(int d) => d == 0 ? 'Cuadró' : (d < 0 ? 'Faltan ${plataNs(-d)}' : 'Sobran ${plataNs(d)}');
    Color color(int d) => d == 0 ? ns.g : ns.b;
    Widget bloque(String titulo, int esperado, int? contado, int dif) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: SeccionNs(titulo)),
        FilaClaveValorNs(clave: 'Debería haber', valor: plataNs(esperado), tamanioValor: 18, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
        FilaClaveValorNs(clave: 'Contaste', valor: plataNs(contado ?? 0), tamanioValor: 18, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
        FilaClaveValorNs(clave: 'Diferencia', valor: texto(dif), colorValor: color(dif), tamanioValor: 18, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)),
      ],
    );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        HeroNs(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(todo ? 'Todo cuadró' : 'Revisá la diferencia', style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
              const SizedBox(height: 6),
              Text(todo ? 'Cuadró' : plataNs(de.abs() + dm.abs() + dl.abs()), style: tituloNs(44, track: -0.058, altura: 1.02, color: TokensNs.blanco)),
              const SizedBox(height: 6),
              Text(todo ? 'El conteo coincide con lo esperado.' : 'Es la suma de las diferencias de abajo.', style: estiloNs(14, altura: 1.4, color: const Color(0xCCFFFFFF))),
            ],
          ),
        ),
        bloque('Efectivo', r.efectivoEsperadoCentavos, _centavos(_efectivo), de),
        bloque('Mercado Pago', r.mpEsperadoCentavos, _centavos(_mp), dm),
        bloque('Lata de cigarrillos', r.lataFinalCentavos, _centavos(_lata), dl),
        const Padding(padding: EdgeInsets.only(top: 14, bottom: 8), child: SeccionNs('Apartar para proveedores')),
        for (final p in r.porProveedor)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
              child: Row(
                children: [
                  Expanded(child: Text(p.nombreProveedor, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
                  Text(plataNs(p.costoRealCentavos), style: estiloNs(18, peso: FontWeight.w500, track: -0.03, color: ns.ink, tabular: true)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        // Lo que un cierre real tiene además de las tres cajas (cigarrillos, redondeo, vendido sin costo…).
        SeccionExtraCierreCompanion(resumen: r),
        if (r.reservaDiariaFijosCentavos == null || r.reservaDiariaFijosCentavos == 0) ...[
          const SizedBox(height: 10),
          const InfoNs('Todavía no cargaste los gastos fijos de este mes.'),
        ],
        if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
      ],
    );
  }

  List<Widget> _botones(BuildContext context) {
    final ns = context.ns;
    switch (_etapa) {
      case _Etapa.conteo:
        final ok = _centavos(_campo) != null;
        return [
          BotonNs(
            texto: _trabajando ? 'Calculando…' : (_paso == 2 ? 'Ver si cuadra' : 'Siguiente'),
            onTap: _trabajando ? null : _siguiente,
            alto: 60,
            tamanio: 17,
            fondo: ok ? ns.prim : ns.s,
            color: ok ? TokensNs.blanco : ns.mute,
            habilitado: !_trabajando,
          ),
        ];
      case _Etapa.resultado:
        return [
          BotonNs.primario(context, _trabajando ? 'Cerrando…' : 'Cerrar caja', _trabajando ? null : _cerrarDeVerdad, habilitado: !_trabajando),
          const SizedBox(height: 8),
          BotonNs.secundario(context, 'Volver a contar', _trabajando ? null : _atras),
        ];
      case _Etapa.cerrada:
        return [BotonNs.primario(context, 'Listo', _listo)];
    }
  }
}
