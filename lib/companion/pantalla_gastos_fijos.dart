// Gastos fijos en el celular (El dueño, 2026-10-09: independizar el celular; antes solo en la PC): cada fijo con el monto de este
// mes y el día en que vence, cargar o corregir el monto, y sumar uno nuevo. Desde la v64 los fijos viajan entre la PC y el
// celular, así que se trabaja sobre la base del celular como Proveedores. Las reglas son las de la PC (`repositorio_equilibrio.dart`):
// un mes sin monto propio repite el último cargado.
//
// Pagar un fijo (El dueño, 2026-10-12: "tal como lo tengo en la PC"): mismo `registrarPagoFijo` que Equilibrio en la PC,
// sobre la caja abierta del celular; el movimiento viaja a la PC por la sync como cualquier gasto.

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositorio_equilibrio.dart';
import '../data/repositorio_ventas.dart' show SesionCerradaException;
import '../domain/dinero.dart';
import '../domain/equilibrio.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';

class PantallaGastosFijos extends StatefulWidget {
  /// [db] y [ahora] son para tests.
  const PantallaGastosFijos({super.key, this.db, this.ahora});

  final AppDatabase? db;
  final DateTime? ahora;

  @override
  State<PantallaGastosFijos> createState() => _PantallaGastosFijosState();
}

class _PantallaGastosFijosState extends State<PantallaGastosFijos> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  late final String _mes = mesAnioDe(widget.ahora ?? DateTime.now());
  ResumenFijosDelMes? _resumen;
  Map<int, int> _pagado = const {};

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    final r = await fijosDelMes(_db, _mes);
    final pagado = await pagadoPorConceptoDelMes(_db, _mes);
    if (mounted) {
      setState(() {
        _resumen = r;
        _pagado = pagado;
      });
    }
  }

  Future<void> _pagar(GastoFijoDelMes f) async {
    final pagado = _pagado[f.concepto.id] ?? 0;
    final falta = f.montoCentavos == null ? 0 : (f.montoCentavos! - pagado).clamp(0, f.montoCentavos!);
    final guardado = await mostrarHojaNs<bool>(context, builder: (_) => _HojaPagarFijo(db: _db, fijo: f, sugeridoCentavos: falta, hoy: widget.ahora ?? DateTime.now()));
    if (guardado == true) {
      await _recargar();
      if (mounted) mostrarAvisoNs(context, 'Pago de ${f.concepto.nombre} anotado');
    }
  }

  Future<void> _editar(GastoFijoDelMes f) async {
    final guardado = await mostrarHojaNs<bool>(context, builder: (_) => _HojaFijo(db: _db, mes: _mes, fijo: f));
    if (guardado == true) await _recargar();
  }

  Future<void> _nuevo() async {
    final guardado = await mostrarHojaNs<bool>(context, builder: (_) => _HojaFijo(db: _db, mes: _mes));
    if (guardado == true) await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final r = _resumen;
    return PaginaNs(
      titulo: 'Gastos fijos',
      derecha: BotonNs(texto: '+ Nuevo', onTap: _nuevo, alto: 44, tamanio: 15, fondo: ns.prim, color: TokensNs.blanco, rellenar: false, paddingH: 20),
      cuerpo: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fijos de este mes', style: estiloNs(15, peso: FontWeight.w500, color: ns.mute)),
                      const SizedBox(height: 4),
                      Text(r.total == null ? 'Falta cargar ${r.faltantes.length}' : plataNs(r.total!), style: tituloNs(36, color: r.total == null ? ns.w : ns.ink)),
                      const SizedBox(height: 6),
                      Text('Pagado ${plataNs(_pagado.values.fold(0, (a, b) => a + b))}', style: estiloNs(14, peso: FontWeight.w600, color: ns.g)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const InfoNs('Un mes sin monto propio repite el último que cargaste. Tocá uno para cambiar el monto; "Pagar" anota el pago.'),
                const SizedBox(height: 12),
                if (r.conceptos.isEmpty) const InfoNs('Todavía no hay gastos fijos. Con "+ Nuevo" sumás el primero.'),
                for (final f in r.conceptos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PresionNs(
                      onTap: () => _editar(f),
                      etiqueta: f.concepto.nombre,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.concepto.nombre, style: estiloNs(17, peso: FontWeight.w500, color: ns.ink)),
                                  Text(
                                    [
                                      switch (estadoDelFijo(montoCentavos: f.montoCentavos, pagadoCentavos: _pagado[f.concepto.id] ?? 0)) {
                                        EstadoFijo.pagado => 'Pagado',
                                        EstadoFijo.pendiente => (_pagado[f.concepto.id] ?? 0) > 0 ? 'Pagado ${plataNs(_pagado[f.concepto.id]!)}' : 'Sin pagar',
                                        EstadoFijo.faltaCargar => 'Falta el monto',
                                      },
                                      if (f.concepto.diaVencimiento != null) 'Vence el ${f.concepto.diaVencimiento}',
                                      if (f.heredadoDe != null) 'Mismo monto que ${f.heredadoDe}',
                                    ].join(' · '),
                                    style: estiloNs(13, color: ns.mute),
                                  ),
                                ],
                              ),
                            ),
                            Text(f.montoCentavos == null ? 'Sin cargar' : plataNs(f.montoCentavos!),
                                style: estiloNs(17, peso: FontWeight.w600, color: f.montoCentavos == null ? ns.w : ns.ink, tabular: true)),
                            const SizedBox(width: 8),
                            if (estadoDelFijo(montoCentavos: f.montoCentavos, pagadoCentavos: _pagado[f.concepto.id] ?? 0) == EstadoFijo.pagado)
                              IconoNsWidget(IconoNs.chevron, tamanio: 16, color: ns.mute, grosor: 2.2)
                            else
                              BotonNs(texto: 'Pagar', onTap: () => _pagar(f), alto: 34, tamanio: 13, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Alta (sin [fijo]) o edición del monto de este mes y el día de vencimiento.
class _HojaFijo extends StatefulWidget {
  const _HojaFijo({required this.db, required this.mes, this.fijo});
  final AppDatabase db;
  final String mes;
  final GastoFijoDelMes? fijo;

  @override
  State<_HojaFijo> createState() => _HojaFijoState();
}

class _HojaFijoState extends State<_HojaFijo> {
  late final _nombre = TextEditingController(text: widget.fijo?.concepto.nombre ?? '');
  late final _monto = TextEditingController(text: widget.fijo?.montoCentavos == null ? '' : '${widget.fijo!.montoCentavos! ~/ centavosPorPeso}');
  late final _dia = TextEditingController(text: widget.fijo?.concepto.diaVencimiento?.toString() ?? '');
  String? _error;

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final monto = int.tryParse(_monto.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final dia = int.tryParse(_dia.text.trim());
    if (widget.fijo == null && nombre.isEmpty) return setState(() => _error = 'Falta el nombre');
    if (_dia.text.trim().isNotEmpty && (dia == null || dia < 1 || dia > 31)) return setState(() => _error = 'El día tiene que ser del 1 al 31');
    try {
      var id = widget.fijo?.concepto.id;
      if (id == null) {
        final todos = await widget.db.select(widget.db.gastosFijos).get();
        if (todos.any((g) => g.nombre.trim().toLowerCase() == nombre.toLowerCase())) return setState(() => _error = 'Ya hay un fijo llamado "$nombre"');
        id = await crearConcepto(widget.db, nombre);
      }
      if (monto != null) await cargarMontoDelMes(widget.db, gastoFijoId: id, mesAnio: widget.mes, montoCentavos: monto * centavosPorPeso);
      if (dia != widget.fijo?.concepto.diaVencimiento) await configurarVencimiento(widget.db, gastoFijoId: id, dia: dia);
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fijo;
    return HojaNs(
      titulo: f == null ? 'Nuevo gasto fijo' : f.concepto.nombre,
      bloques: [
        if (f == null) CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej: Alquiler del local', autofoco: true),
        CampoNs(etiqueta: 'Monto de este mes', controller: _monto, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, grande: true, autofoco: f != null),
        CampoNs(etiqueta: 'Día en que vence (opcional)', controller: _dia, placeholder: 'Ej: 10', teclado: TextInputType.number, formatos: soloDigitosNs),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, f == null ? 'Dar de alta' : 'Guardar', _guardar)],
    );
  }
}

/// Pagar un fijo: monto (sugerido = lo que falta del mes), de dónde sale y la fecha real del pago. Mismas reglas que el
/// diálogo de la PC (`dialogo_registrar_pago_fijo.dart`): hace falta la caja abierta, y la fecha se puede cambiar porque
/// el alquiler a veces se paga un día y se anota otro.
class _HojaPagarFijo extends StatefulWidget {
  const _HojaPagarFijo({required this.db, required this.fijo, required this.sugeridoCentavos, required this.hoy});
  final AppDatabase db;
  final DateTime hoy;
  final GastoFijoDelMes fijo;
  final int sugeridoCentavos;

  @override
  State<_HojaPagarFijo> createState() => _HojaPagarFijoState();
}

class _HojaPagarFijoState extends State<_HojaPagarFijo> {
  late final _monto = TextEditingController(text: widget.sugeridoCentavos > 0 ? '${widget.sugeridoCentavos ~/ centavosPorPeso}' : '');
  late final _fecha = TextEditingController(text: _formatearFecha(widget.hoy));
  bool _conMp = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _fecha.dispose();
    super.dispose();
  }

  Future<void> _pagar() async {
    final pesos = int.tryParse(_monto.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (pesos == null || pesos <= 0) return setState(() => _error = 'El monto tiene que ser mayor a cero');
    final fecha = _parsearFecha(_fecha.text);
    if (fecha == null) return setState(() => _error = 'Fecha inválida (DD/MM/AAAA)');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final usuario = await leerUsuario();
      if (usuario == null) throw StateError('Falta elegir usuario.');
      final sesion = await PuertoLocal(widget.db).sesion();
      if (!sesion.abierta) throw StateError('No hay caja abierta: abrila desde Caja.');
      await registrarPagoFijo(
        widget.db,
        gastoFijoId: widget.fijo.concepto.id,
        sesionCajaId: sesion.id!,
        usuarioId: usuario.id,
        montoCentavos: pesos * centavosPorPeso,
        pagadoConMp: _conMp,
        fecha: fecha,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on SesionCerradaException {
      if (mounted) setState(() => _error = 'La caja ya se cerró: el pago no se guardó');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return HojaNs(
      titulo: 'Pagar ${widget.fijo.concepto.nombre}',
      bloques: [
        CampoNs(etiqueta: 'Monto pagado', controller: _monto, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, grande: true, autofoco: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('De dónde salió la plata', style: estiloNs(13, peso: FontWeight.w500, color: ns.mute)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipNs(texto: 'Del cajón', activo: !_conMp, onTap: () => setState(() => _conMp = false)),
                ChipNs(texto: 'Mercado Pago', activo: _conMp, onTap: () => setState(() => _conMp = true)),
              ],
            ),
          ],
        ),
        CampoNs(etiqueta: 'Fecha del pago (DD/MM/AAAA)', controller: _fecha, placeholder: 'Ej: 10/10/2026', teclado: TextInputType.datetime),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, _guardando ? 'Anotando…' : 'Anotar pago', _guardando ? null : _pagar, habilitado: !_guardando)],
    );
  }
}

// Mismo parseo/formato que el diálogo de la PC.
DateTime? _parsearFecha(String texto) {
  final partes = texto.trim().split('/');
  if (partes.length != 3) return null;
  final dia = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final anio = int.tryParse(partes[2]);
  if (dia == null || mes == null || anio == null || mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  final f = DateTime(anio, mes, dia, 12);
  return f.month == mes ? f : null;
}

String _formatearFecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}
