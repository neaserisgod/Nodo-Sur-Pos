// Gastos fijos en el celular (El dueño, 2026-10-09: independizar el celular; antes solo en la PC): cada fijo con el monto de este
// mes y el día en que vence, cargar o corregir el monto, y sumar uno nuevo. Desde la v64 los fijos viajan entre la PC y el
// celular, así que se trabaja sobre la base del celular como Proveedores. Las reglas son las de la PC (`repositorio_equilibrio.dart`):
// un mes sin monto propio repite el último cargado.

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositorio_equilibrio.dart';
import '../domain/dinero.dart';
import 'base_local.dart';
import 'kit/kit_ns.dart';

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

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    final r = await fijosDelMes(_db, _mes);
    if (mounted) setState(() => _resumen = r);
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const InfoNs('Un mes sin monto propio repite el último que cargaste. Tocá uno para cambiarlo.'),
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
                            IconoNsWidget(IconoNs.chevron, tamanio: 16, color: ns.mute, grosor: 2.2),
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
