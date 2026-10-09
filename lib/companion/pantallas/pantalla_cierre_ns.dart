// Cerrar caja, tal cual el mock (lote 2): dos etapas y la caja cerrada.
//   Etapa 1 · se cuenta el efectivo SIN ver cuánto debería haber ("a ciegas").
//   Etapa 2 · se ve la diferencia, se pueden corregir los conteos y se cuenta Mercado Pago y la lata; todavía no se
//             cerró nada: "Cerrar caja" es lo que cierra.
//   Cerrada · el resultado, con lo que un cierre real tiene además de las tres cajas.
// Una caja cerrada no se reabre, por eso el resultado se revisa ANTES de cerrar (etapa 2), no después.
//
// "Traer saldo de Mercado Pago" (El dueño, 2026-10-09: independizar el celular): el mismo botón del cierre de la PC
// (`traerSaldoMpDeCuenta`, con la cuenta vinculada de este celular) llena el "MP contado" con el saldo real.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositorio_faltantes.dart' show DestinoFaltante, destinoPosible;
import '../../domain/dinero.dart';
import '../../domain/faltantes_cierre.dart';
import '../../domain/saldo_mp.dart' show SaldoMp;
import '../../servicios/saldo_mp_nube.dart';
import '../app_ns.dart';
import '../cliente_companion.dart' show ProveedorCompanion, ResumenCierreCompanion;
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../seccion_extra_cierre_companion.dart';
import '../servicio_companion.dart';
import '../servicio_companion_offline.dart';
import '../sync_nube_companion.dart';

class PantallaCierreNs extends StatefulWidget {
  const PantallaCierreNs({
    super.key,
    required this.servicio,
    required this.usuarioId,
    this.precargaEfectivoCentavos,
    this.precargaMpCentavos,
    this.precargaLataCentavos,
    this.horaPrecarga,
    this.traerSaldoMp,
  });

  /// Para tests. En la app sale de la cuenta vinculada del celular.
  final TraerSaldoMp? traerSaldoMp;

  final ServicioCompanion servicio;
  final int usuarioId;

  /// Lo contado en el último arqueo del turno: el cierre arranca con eso cargado.
  final int? precargaEfectivoCentavos;
  final int? precargaMpCentavos;
  final int? precargaLataCentavos;
  final DateTime? horaPrecarga;

  @override
  State<PantallaCierreNs> createState() => _PantallaCierreNsState();
}

enum _Etapa { conteo, revisar, cerrada }

class _PantallaCierreNsState extends State<PantallaCierreNs> {
  _Etapa _etapa = _Etapa.conteo;

  late final _efectivo = TextEditingController(text: _pesos(widget.precargaEfectivoCentavos));
  late final _mp = TextEditingController(text: _pesos(widget.precargaMpCentavos));
  late final _lata = TextEditingController(text: _pesos(widget.precargaLataCentavos));
  final _nota = TextEditingController();

  /// Lo esperado y el resto del cierre (separación, redondeo, sin costo…): llega al confirmar el conteo de la etapa 1.
  ResumenCierreCompanion? _resumen;
  bool _trabajando = false;
  String? _error;

  SaldoMp? _saldo;
  bool _pidiendoSaldo = false;

  /// "¿A dónde fue esta plata?" (El dueño, 2026-10-07; en el celular desde el 2026-10-09). Null: todavía no se pidió, o la PC
  /// no la ofrece (versión vieja): entonces no se pregunta, como antes.
  OpcionesFaltanteCompanion? _opcionesFaltante;

  /// Lo que falta en cada caja (desde el mínimo), con lo contado ahora. Se recalcula al anotar o corregir un conteo.
  Map<CajaDelCierre, int> get _faltantes {
    final r = _resumen;
    final o = _opcionesFaltante;
    if (r == null || o == null) return const {};
    final mp = _centavos(_mp);
    final lata = _centavos(_lata);
    return faltantesPorExplicar(
      diferenciaEfectivoCentavos: (_centavos(_efectivo) ?? 0) - r.efectivoEsperadoCentavos,
      diferenciaMpCentavos: mp == null ? null : mp - r.mpEsperadoCentavos,
      diferenciaLataCentavos: lata == null ? null : lata - r.lataFinalCentavos,
      umbral: o.umbralCentavos,
    );
  }

  Future<void> _cargarOpcionesFaltante() async {
    if (_opcionesFaltante != null) return;
    try {
      final o = await widget.servicio.opcionesFaltante();
      if (mounted) setState(() => _opcionesFaltante = o);
    } catch (_) {
      // Sin poder preguntar, el cierre sigue como siempre.
    }
  }

  /// Vuelve a pedir lo esperado (anotar un faltante lo cambia: un gasto, un retiro o un pago salen de la caja).
  Future<void> _recalcular() async {
    final r = await widget.servicio.calcularCierre(
      efectivoContadoCentavos: _centavos(_efectivo) ?? 0,
      mpContadoCentavos: _centavos(_mp),
      lataContadoCentavos: _centavos(_lata),
    );
    if (mounted) setState(() => _resumen = r);
  }

  Future<void> _explicar(CajaDelCierre caja, int falta) async {
    final opciones = _opcionesFaltante;
    if (opciones == null) return;
    List<ProveedorCompanion> proveedores = const [];
    try {
      proveedores = await widget.servicio.proveedores();
    } catch (_) {}
    if (!mounted) return;
    final anotado = await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaFaltante(servicio: widget.servicio, usuarioId: widget.usuarioId, caja: caja, falta: falta, fijos: opciones.fijos, proveedores: proveedores),
    );
    if (anotado == true) {
      try {
        await _recalcular();
      } catch (e) {
        if (mounted) setState(() => _error = mensajeDeError(e));
      }
    }
  }

  /// Pide el saldo real de la cuenta de Mercado Pago (tarda: el reporte lo arma Mercado Pago) y lo pone en "MP contado",
  /// editable. Nunca frena el cierre: si falla, se avisa y se sigue con lo contado a mano.
  Future<void> _traerSaldo() async {
    final desde = AppNs.of(context).sesion?.fechaApertura;
    if (desde == null || _pidiendoSaldo) return;
    setState(() => _pidiendoSaldo = true);
    try {
      final traer = widget.traerSaldoMp ?? await () async {
        final sync = await syncNubeDelCelular();
        return traerSaldoMpDeCuenta(sync.almacen, sync.cliente);
      }();
      final saldo = await traer(desde);
      if (!mounted) return;
      setState(() {
        _saldo = saldo;
        _mp.text = '${(saldo.contadoSugeridoCentavos / centavosPorPeso).round()}';
      });
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
    } finally {
      if (mounted) setState(() => _pidiendoSaldo = false);
    }
  }

  static String _pesos(int? centavos) => centavos == null ? '' : '${centavos ~/ centavosPorPeso}';

  @override
  void dispose() {
    _efectivo.dispose();
    _mp.dispose();
    _lata.dispose();
    _nota.dispose();
    super.dispose();
  }

  int? _centavos(TextEditingController c) {
    final d = c.text.replaceAll(RegExp(r'[^0-9]'), '');
    return d.isEmpty ? null : int.parse(d) * centavosPorPeso;
  }

  bool get _completo => _centavos(_efectivo) != null && _centavos(_mp) != null && _centavos(_lata) != null;

  Future<void> _confirmarConteo() async {
    if (_centavos(_efectivo) == null) {
      mostrarAvisoNs(context, 'Contá el efectivo y anotalo antes de confirmar');
      return;
    }
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      // Vista previa: todavía no guarda nada. Trae lo esperado y el resto de las cifras del cierre.
      final r = await widget.servicio.calcularCierre(
        efectivoContadoCentavos: _centavos(_efectivo)!,
        mpContadoCentavos: _centavos(_mp),
        lataContadoCentavos: _centavos(_lata),
      );
      if (mounted) {
        setState(() {
          _resumen = r;
          _etapa = _Etapa.revisar;
        });
        unawaited(_cargarOpcionesFaltante());
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _cerrarDeVerdad() async {
    if (!_completo) {
      mostrarAvisoNs(context, 'Falta el efectivo contado, el MP contado o la lata contada');
      return;
    }
    // Nunca traba el cierre ("No sé"), pero avisa antes: es plata que Equilibrio sigue mostrando como retirable.
    final sinExplicar = _faltantes.values.fold<int>(0, (a, b) => a + b);
    if (sinExplicar > 0) {
      final seguir = await mostrarHojaNs<bool>(
        context,
        builder: (ctx) => HojaNs(
          titulo: 'Quedan ${plataNs(sinExplicar)} sin explicar',
          texto: 'Si cerrás así, esa plata queda como si siguiera en la caja. Podés anotar a dónde fue antes de cerrar.',
          botones: [
            BotonNs.primario(ctx, 'Cerrar igual (no sé)', () => Navigator.of(ctx).pop(true)),
            BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
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
    if (_etapa == _Etapa.revisar) {
      setState(() {
        _etapa = _Etapa.conteo;
        _error = null;
      });
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

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final cerrada = _etapa == _Etapa.cerrada;
    return PopScope(
      canPop: _etapa == _Etapa.conteo || cerrada,
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
                  Expanded(
                    child: switch (_etapa) {
                      _Etapa.conteo => _conteo(context),
                      _Etapa.revisar => _revisar(context),
                      _Etapa.cerrada => _cerradaVista(context),
                    },
                  ),
                  const SizedBox(height: 14),
                  _boton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titulo(BuildContext context, String etapa, String titulo) {
    final ns = context.ns;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mayusculasNs(etapa), style: seccionNs(ns.mute)),
          const SizedBox(height: 8),
          Text(titulo, style: tituloNs(34, track: -0.05, altura: 1.08, color: ns.ink)),
        ],
      ),
    );
  }

  Widget _conteo(BuildContext context) {
    final hora = widget.horaPrecarga;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _titulo(context, 'Etapa 1 de 2', 'Contá el efectivo del cajón'),
        const SizedBox(height: 10),
        const InfoNs('Contá el efectivo del cajón, cigarrillos incluidos, antes de ver la diferencia y la separación.'),
        if (widget.servicio is ServicioCompanionOffline) ...[
          const SizedBox(height: 10),
          const InfoNs('Sin conexión con la PC: este cierre se calcula con los datos ya sincronizados a este celular. Si algo de la PC todavía no llegó, puede no coincidir.', tono: TonoNs.warn),
        ],
        const SizedBox(height: 10),
        CampoNs(etiqueta: 'Efectivo contado', controller: _efectivo, grande: true, placeholder: '\$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, autofoco: true, onChanged: (_) => setState(() {})),
        if (hora != null && _centavos(_efectivo) != null) ...[
          const SizedBox(height: 10),
          InfoNs('Precargado con el arqueo de las ${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}. Si vendiste o sacaste plata después, corregilo.'),
        ],
        if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
      ],
    );
  }

  String _dif(int d) => d == 0 ? 'Cuadró' : (d < 0 ? 'Faltan ${plataNs(-d)}' : 'Sobran ${plataNs(d)}');

  Widget _revisar(BuildContext context) {
    final ns = context.ns;
    final r = _resumen!;
    final ef = _centavos(_efectivo);
    final mp = _centavos(_mp);
    final la = _centavos(_lata);
    Color color(int d) => d == 0 ? ns.g : ns.b;
    Widget campo(String etiqueta, TextEditingController c, {String? placeholder}) => CampoNs(
      etiqueta: etiqueta,
      controller: c,
      placeholder: placeholder ?? '\$ 0',
      teclado: TextInputType.number,
      formatos: soloDigitosNs,
      onChanged: (_) => setState(() {}),
    );
    Widget dato(String clave, int esperado, int? contado) => Column(
      children: [
        FilaClaveValorNs(clave: clave, valor: plataNs(esperado)),
        if (contado != null) FilaClaveValorNs(clave: 'Diferencia', valor: _dif(contado - esperado), colorValor: color(contado - esperado)),
      ],
    );
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _titulo(context, 'Etapa 2 de 2', 'Revisá antes de cerrar'),
        const SizedBox(height: 10),
        const InfoNs('Todavía no se cerró nada. Podés corregir lo contado: la diferencia se actualiza sola.'),
        const SizedBox(height: 10),
        campo('Efectivo contado (se puede corregir)', _efectivo),
        if (ef != null) dato('Caja esperada', r.efectivoEsperadoCentavos, ef),
        const SizedBox(height: 4),
        campo('MP contado (según la app de Mercado Pago)', _mp),
        const SizedBox(height: 8),
        BotonNs.secundario(context, _pidiendoSaldo ? 'Pidiendo el saldo a Mercado Pago…' : 'Traer saldo de Mercado Pago', _pidiendoSaldo ? null : _traerSaldo, icono: IconoNs.descarga),
        if (_saldo != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InfoNs(
              _saldo!.aLiberarConocido
                  ? 'Mercado Pago: disponible ${plataNs(_saldo!.disponibleCentavos)} + por liberar ${plataNs(_saldo!.aLiberarCentavos!)}. Se puede corregir.'
                  : 'Mercado Pago: disponible ${plataNs(_saldo!.disponibleCentavos)} (no se pudo saber lo que falta liberar). Se puede corregir.',
            ),
          ),
        if (mp != null) dato('MP esperado', r.mpEsperadoCentavos, mp),
        const SizedBox(height: 4),
        campo('Lata contada', _lata),
        if (la != null) dato('Lata esperada', r.lataFinalCentavos, la),
        for (final f in _faltantes.entries)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
              decoration: BoxDecoration(color: ns.wbg, borderRadius: BorderRadius.circular(24)),
              child: Row(
                children: [
                  Expanded(child: Text('Faltan ${plataNs(f.value)} en ${_nombreCaja(f.key)}', style: estiloNs(15, peso: FontWeight.w600, color: ns.w))),
                  BotonNs(texto: '¿A dónde fue?', onTap: () => _explicar(f.key, f.value), alto: 40, tamanio: 14, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 14),
                ],
              ),
            ),
          ),
        SeccionExtraCierreCompanion(resumen: r),
        const SizedBox(height: 14),
        campo('Nota (opcional)', _nota, placeholder: 'Ej: faltó cambio'),
        if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
      ],
    );
  }

  Widget _cerradaVista(BuildContext context) {
    final ns = context.ns;
    final r = _resumen!;
    final de = (_centavos(_efectivo) ?? 0) - r.efectivoEsperadoCentavos;
    final dm = (_centavos(_mp) ?? 0) - r.mpEsperadoCentavos;
    final dl = (_centavos(_lata) ?? 0) - r.lataFinalCentavos;
    final todo = de == 0 && dm == 0 && dl == 0;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        HeroHojaNs(
          rotulo: todo ? 'Todo cuadró' : 'Revisá la diferencia',
          cifra: todo ? 'Cuadró' : plataNs(de.abs()),
          apoyo: todo ? 'El conteo coincide con lo esperado.' : 'Diferencia en efectivo: ${_dif(de).toLowerCase()}.',
        ),
        FilaClaveValorNs(clave: 'Diferencia', valor: _dif(de), colorValor: de == 0 ? ns.g : ns.b),
        FilaClaveValorNs(clave: 'Lata al cierre', valor: plataNs(r.lataFinalCentavos)),
        SeccionExtraCierreCompanion(resumen: r, nota: _nota.text),
      ],
    );
  }

  Widget _boton(BuildContext context) {
    final ns = context.ns;
    switch (_etapa) {
      case _Etapa.conteo:
        final ok = _centavos(_efectivo) != null;
        return BotonNs(
          texto: _trabajando ? 'Calculando…' : 'Confirmar conteo',
          onTap: _trabajando ? null : _confirmarConteo,
          alto: 60,
          tamanio: 17,
          fondo: ok ? ns.prim : ns.s,
          color: ok ? TokensNs.blanco : ns.mute,
          habilitado: !_trabajando,
        );
      case _Etapa.revisar:
        return BotonNs(
          texto: _trabajando ? 'Cerrando…' : 'Cerrar caja',
          onTap: _trabajando ? null : _cerrarDeVerdad,
          alto: 60,
          tamanio: 17,
          fondo: _completo ? ns.prim : ns.s,
          color: _completo ? TokensNs.blanco : ns.mute,
          habilitado: !_trabajando,
        );
      case _Etapa.cerrada:
        return BotonNs.primario(context, 'Listo', _listo);
    }
  }
}

String _nombreCaja(CajaDelCierre c) => switch (c) {
  CajaDelCierre.efectivo => 'el cajón',
  CajaDelCierre.mercadoPago => 'Mercado Pago',
  CajaDelCierre.lata => 'la lata',
};

/// A dónde fue un faltante: gasto mío (retiro), un proveedor (baja la deuda), un fijo (lo marca pagado; desde la lata no) u
/// otro gasto del negocio. El monto arranca con todo lo que falta y se puede achicar para anotarlo en partes.
class _HojaFaltante extends StatefulWidget {
  const _HojaFaltante({required this.servicio, required this.usuarioId, required this.caja, required this.falta, required this.fijos, required this.proveedores});
  final ServicioCompanion servicio;
  final int usuarioId;
  final CajaDelCierre caja;
  final int falta;
  final List<({int id, String nombre})> fijos;
  final List<ProveedorCompanion> proveedores;

  @override
  State<_HojaFaltante> createState() => _HojaFaltanteState();
}

class _HojaFaltanteState extends State<_HojaFaltante> {
  late final _monto = TextEditingController(text: '${widget.falta ~/ centavosPorPeso}');
  final _nota = TextEditingController();
  DestinoFaltante _destino = DestinoFaltante.gastoMio;
  int? _proveedorId;
  int? _fijoId;
  String? _error;
  bool _guardando = false;

  static const _nombres = {
    DestinoFaltante.gastoMio: 'Gasto mío',
    DestinoFaltante.proveedor: 'Proveedor',
    DestinoFaltante.fijo: 'Fijo',
    DestinoFaltante.negocio: 'Otro gasto',
  };

  Future<void> _anotar() async {
    final monto = (int.tryParse(_monto.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * centavosPorPeso;
    if (monto <= 0) return setState(() => _error = 'Escribí el monto');
    if (_destino == DestinoFaltante.proveedor && _proveedorId == null) return setState(() => _error = 'Elegí el proveedor');
    if (_destino == DestinoFaltante.fijo && _fijoId == null) return setState(() => _error = 'Elegí el fijo');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.anotarFaltante(
        usuarioId: widget.usuarioId,
        caja: widget.caja,
        montoCentavos: monto,
        destino: _destino,
        proveedorId: _destino == DestinoFaltante.proveedor ? _proveedorId : null,
        gastoFijoId: _destino == DestinoFaltante.fijo ? _fijoId : null,
        nota: _nota.text,
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
    final destinos = [for (final d in DestinoFaltante.values) if (destinoPosible(d, widget.caja)) d];
    return HojaNs(
      titulo: '¿A dónde fue esta plata?',
      texto: 'Faltan ${plataNs(widget.falta)} en ${_nombreCaja(widget.caja)}. Se puede anotar en partes.',
      bloques: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in destinos) ChipNs(texto: _nombres[d]!, activo: _destino == d, onTap: () => setState(() => _destino = d)),
        ]),
        if (_destino == DestinoFaltante.proveedor)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in widget.proveedores) ChipNs(texto: p.nombre, activo: _proveedorId == p.id, onTap: () => setState(() => _proveedorId = p.id)),
          ]),
        if (_destino == DestinoFaltante.fijo)
          widget.fijos.isEmpty
              ? const InfoNs('No hay gastos fijos cargados.')
              : Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in widget.fijos) ChipNs(texto: f.nombre, activo: _fijoId == f.id, onTap: () => setState(() => _fijoId = f.id)),
                ]),
        CampoNs(etiqueta: 'Monto', controller: _monto, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs),
        CampoNs(etiqueta: 'Nota (opcional)', controller: _nota, placeholder: 'Ej: luz de septiembre'),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, _guardando ? 'Anotando…' : 'Anotar', _guardando ? null : _anotar, habilitado: !_guardando)],
    );
  }
}
