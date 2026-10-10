// Más › Configuración › Agenda y seña (`REGLAS-NEGOCIO.md` §21): el horario de atención (uno solo, que usan la Agenda y el
// bot), cada cuánto se ofrecen turnos, y cómo se pide la seña y a dónde se transfiere. Es parte de los datos del negocio: el
// bot de WhatsApp los toma de acá, sin una configuración aparte.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_turnos.dart';
import '../../domain/dinero.dart' show parsearARS;
import '../../domain/turnos.dart';
import '../base_local.dart';
import '../kit/kit_ns.dart';

const _nombresDias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

class PantallaConfigAgendaNs extends StatefulWidget {
  /// [db] es para tests.
  const PantallaConfigAgendaNs({super.key, this.db});
  final AppDatabase? db;

  @override
  State<PantallaConfigAgendaNs> createState() => _PantallaConfigAgendaNsState();
}

class _DiaEditable {
  _DiaEditable(FranjaAtencion? f)
      : abierto = f != null,
        desde = TextEditingController(text: horaDeMinutos(f?.desdeMin ?? 540)),
        hasta = TextEditingController(text: horaDeMinutos(f?.hastaMin ?? 1200));
  bool abierto;
  final TextEditingController desde;
  final TextEditingController hasta;
}

class _PantallaConfigAgendaNsState extends State<PantallaConfigAgendaNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<_DiaEditable>? _dias;
  int _paso = 15;
  ModoSena _modo = ModoSena.algunos;
  bool _fijo = false;
  bool _devolver = false;
  final _porcentaje = TextEditingController();
  final _montoFijo = TextEditingController();
  final _alias = TextEditingController();
  final _titular = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    configAgendaActual(_db).then((c) {
      if (!mounted) return;
      setState(() {
        _dias = [for (var d = 1; d <= 7; d++) _DiaEditable(c.horario.dias[d])];
        _paso = c.pasoMinutos;
        _modo = c.sena.modo;
        _fijo = (c.sena.montoFijoCentavos ?? 0) > 0;
        _devolver = c.sena.devolverAlCancelar;
        _porcentaje.text = '${c.sena.porcentaje}';
        _montoFijo.text = _fijo ? '${c.sena.montoFijoCentavos! ~/ 100}' : '';
        _alias.text = c.aliasSena;
        _titular.text = c.titularSena;
      });
    });
  }

  @override
  void dispose() {
    for (final d in _dias ?? const <_DiaEditable>[]) {
      d.desde.dispose();
      d.hasta.dispose();
    }
    _porcentaje.dispose();
    _montoFijo.dispose();
    _alias.dispose();
    _titular.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final dias = <int, FranjaAtencion?>{};
    for (var i = 0; i < 7; i++) {
      final d = _dias![i];
      if (!d.abierto) {
        dias[i + 1] = null;
        continue;
      }
      final desde = minutosDeHora(d.desde.text), hasta = minutosDeHora(d.hasta.text);
      if (desde == null || hasta == null) return setState(() => _error = 'El horario del ${_nombresDias[i].toLowerCase()} va como 09:00');
      if (desde >= hasta) return setState(() => _error = 'El ${_nombresDias[i].toLowerCase()} cierra antes de abrir');
      dias[i + 1] = (desdeMin: desde, hastaMin: hasta);
    }
    final porcentaje = int.tryParse(_porcentaje.text.trim()) ?? -1;
    int? fijo;
    if (_modo != ModoSena.nunca) {
      if (_fijo) {
        try {
          fijo = parsearARS(_montoFijo.text.trim());
        } on FormatException {
          fijo = null;
        }
        if (fijo == null || fijo <= 0) return setState(() => _error = 'Poné el monto de la seña');
      } else if (porcentaje < 1 || porcentaje > 100) {
        return setState(() => _error = 'El porcentaje de la seña va de 1 a 100');
      }
    }
    try {
      await guardarConfigAgenda(
        _db,
        ConfigAgenda(
          horario: HorarioAtencion(dias),
          pasoMinutos: _paso,
          sena: ConfigSena(modo: _modo, porcentaje: porcentaje.clamp(0, 100), montoFijoCentavos: fijo, devolverAlCancelar: _devolver),
          aliasSena: _alias.text,
          titularSena: _titular.text,
        ),
      );
      if (mounted) {
        mostrarAvisoNs(context, 'Agenda guardada');
        Navigator.of(context).pop();
      }
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final dias = _dias;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: dias == null
            ? const Padding(padding: EdgeInsets.all(margenNs), child: EsqueletoListaNs())
            : ListView(
                padding: const EdgeInsets.fromLTRB(margenNs, 8, margenNs, 32),
                children: [
                  CabeceraSubNs(titulo: 'Agenda y seña', onVolver: () => Navigator.of(context).pop()),
                  const SizedBox(height: 8),
                  Text('Lo usan la Agenda y el bot de WhatsApp.', style: estiloNs(15, color: ns.mute)),
                  const SizedBox(height: 18),
                  const SeccionNs('Horario de atención'),
                  const SizedBox(height: 8),
                  for (var i = 0; i < 7; i++) ...[
                    InterruptorNs(
                      key: ValueKey('dia-abierto-$i'),
                      etiqueta: _nombresDias[i],
                      descripcion: dias[i].abierto ? null : 'Cerrado',
                      encendido: dias[i].abierto,
                      onCambio: (v) => setState(() => dias[i].abierto = v),
                    ),
                    if (dias[i].abierto)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(child: CampoNs(etiqueta: 'Abre', controller: dias[i].desde, placeholder: '09:00', teclado: TextInputType.datetime)),
                            const SizedBox(width: 10),
                            Expanded(child: CampoNs(etiqueta: 'Cierra', controller: dias[i].hasta, placeholder: '20:00', teclado: TextInputType.datetime)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                  const SeccionNs('Los turnos arrancan cada'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const [10, 15, 20, 30, 60]) ChipNs(texto: '$m min', activo: _paso == m, onTap: () => setState(() => _paso = m)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SeccionNs('Seña'),
                  const SizedBox(height: 8),
                  SegmentoNs(
                    opciones: const ['Nunca', 'Algunos', 'Todos'],
                    indice: ModoSena.values.indexOf(_modo),
                    onCambio: (i) => setState(() => _modo = ModoSena.values[i]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    switch (_modo) {
                      ModoSena.nunca => 'No se pide seña.',
                      ModoSena.algunos => 'Solo en los servicios marcados "Pide seña" (en Servicios).',
                      ModoSena.todos => 'En todos los servicios.',
                    },
                    style: estiloNs(14, color: ns.mute),
                  ),
                  if (_modo != ModoSena.nunca) ...[
                    const SizedBox(height: 12),
                    SegmentoNs(opciones: const ['Porcentaje', 'Monto fijo'], indice: _fijo ? 1 : 0, onCambio: (i) => setState(() => _fijo = i == 1)),
                    const SizedBox(height: 10),
                    if (_fijo)
                      CampoNs(etiqueta: 'Monto de la seña', controller: _montoFijo, placeholder: r'$ 5000', teclado: TextInputType.number, formatos: soloDigitosNs)
                    else
                      CampoNs(etiqueta: 'Porcentaje del precio', controller: _porcentaje, placeholder: '30', teclado: TextInputType.number, formatos: soloDigitosNs),
                    const SizedBox(height: 10),
                    SegmentoNs(opciones: const ['Si cancelan, se pierde', 'Se devuelve'], indice: _devolver ? 1 : 0, onCambio: (i) => setState(() => _devolver = i == 1)),
                    const SizedBox(height: 10),
                    CampoNs(etiqueta: 'Alias o CBU para la seña', controller: _alias, placeholder: 'tu.alias.mp'),
                    const SizedBox(height: 10),
                    CampoNs(etiqueta: 'A nombre de', controller: _titular, placeholder: 'Como figura en la cuenta'),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
                  ],
                  const SizedBox(height: 18),
                  BotonNs.primario(context, 'Guardar', _guardar, icono: IconoNs.tilde),
                ],
              ),
      ),
    );
  }
}
