// La Agenda del celular (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4; mock `docs/mock-servicios`, "Agenda"):
// en un negocio de servicios con el módulo Agenda reemplaza a Inicio. El día con sus turnos y los huecos libres, la tira de
// días, los profesionales, anotar un turno (con seña), cambiarle el estado, moverlo y cobrarlo (lo lleva a Vender con su
// seña). Horario de atención y seña se configuran desde acá.
//
// Trabaja sobre la base del celular, como Servicios: solo en "Solo celular". Con una PC, un aviso.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/repositorio_servicios.dart' show listarServicios, serviciosParaVender, ServicioConCosto;
import '../../data/repositorio_turnos.dart';
import '../../data/repositorio_usuarios.dart' show listarUsuariosActivos;
import '../../domain/dinero.dart' show formatearARS, parsearARS;
import '../../domain/modulos.dart';
import '../../domain/turnos.dart';
import '../../domain/venta.dart';
import '../../servicios/modulos_activos.dart';
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../modo_uso.dart';

const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _diasLargos = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);
String _hora(DateTime d) => textoDeMinutos(d.hour * 60 + d.minute);

int? _centavos(String texto) {
  if (texto.trim().isEmpty) return 0;
  try {
    final c = parsearARS(texto);
    return c < 0 ? null : c;
  } on FormatException {
    return null;
  }
}

class PantallaAgendaNs extends StatefulWidget {
  /// [db], [usuarioId], [soloCelular] y [hoy] son para tests (sin `AppNs` arriba).
  const PantallaAgendaNs({super.key, this.db, this.usuarioId, this.soloCelular, this.hoy});

  final AppDatabase? db;
  final int? usuarioId;
  final bool? soloCelular;
  final DateTime? hoy;

  @override
  State<PantallaAgendaNs> createState() => _PantallaAgendaNsState();
}

class _PantallaAgendaNsState extends State<PantallaAgendaNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  late final DateTime _hoy = _soloDia(widget.hoy ?? DateTime.now());
  late DateTime _dia = _hoy;
  int? _usuarioId;

  /// Profesional elegido en los chips (null: todos).
  int? _profesional;
  List<TurnoDeAgenda>? _turnos;
  Map<DateTime, int> _porDia = const {};
  List<Usuario> _profesionales = const [];
  HorarioSemana _horario = HorarioSemana.porDefecto;
  Map<int, String> _faltan = const {};
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    // Un turno que llega por la sync (otro celular, el bot) aparece sin salir de la pantalla.
    _sub = avisosCambiosCompanion.listen((_) => _cargar());
    _cargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  DateTime get _lunes => _dia.subtract(Duration(days: _dia.weekday - 1));

  Future<void> _cargar() async {
    final turnos = await turnosDelDia(_db, _dia);
    final porDia = await turnosPorDia(_db, _lunes, _lunes.add(const Duration(days: 7)));
    final profesionales = await listarUsuariosActivos(_db);
    final horario = await horarioActual(_db);
    final faltan = {for (final s in await serviciosParaVender(_db)) if (s.falta != null) s.servicio.id: s.falta!.nombre};
    if (!mounted) return;
    setState(() {
      _turnos = turnos;
      _porDia = porDia;
      _profesionales = profesionales;
      _horario = horario;
      _faltan = faltan;
    });
  }

  void _irADia(DateTime d) {
    setState(() {
      _dia = _soloDia(d);
      _turnos = null;
    });
    _cargar();
  }

  ControladorAppNs? get _app => context.dependOnInheritedWidgetOfExactType<AppNs>()?.controlador;

  bool get _soloCelular => widget.soloCelular ?? _app?.modoUso == ModoUso.soloCelular;

  int? get _sesionId => _app?.sesion?.id;

  Future<void> _nuevoTurno({DateTime? hora}) async {
    final usuario = _usuarioId;
    if (usuario == null) return mostrarAvisoNs(context, 'Falta elegir usuario');
    final servicios = await listarServicios(_db);
    if (!mounted) return;
    if (servicios.isEmpty) return mostrarAvisoNs(context, 'Primero cargá un servicio en la pestaña Servicios');
    final anotado = await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaNuevoTurno(
        db: _db,
        usuarioId: usuario,
        dia: _dia,
        hora: hora,
        servicios: servicios,
        profesionales: moduloActivo(Modulo.profesionales) ? _profesionales : const [],
        profesional: _profesional,
        horario: _horario,
        sesionCajaId: _sesionId,
      ),
    );
    if (anotado == true) {
      await _cargar();
      if (mounted) mostrarAvisoNs(context, 'Turno anotado');
    }
  }

  Future<void> _abrirTurno(TurnoDeAgenda t) async {
    final accion = await mostrarHojaNs<String>(context, builder: (_) => _HojaTurno(t: t, falta: _faltan[t.servicio.id], conCaja: _sesionId != null));
    if (accion == null || !mounted) return;
    final usuario = _usuarioId;
    if (usuario == null) return;
    try {
      switch (accion) {
        case 'cobrar':
          return await _cobrar(t);
        case 'mover':
          await _mover(t);
        case 'sena':
          await _tomarSena(t);
        default:
          final estado = EstadoTurno.desdeClave(accion)!;
          final devuelto = await cambiarEstadoTurno(_db, turnoId: t.turno.id, estado: estado, usuarioId: usuario, sesionCajaId: _sesionId);
          if (mounted && devuelto > 0) mostrarAvisoNs(context, 'Devolvé ${plataNs(devuelto)} de seña');
      }
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
    }
    await _cargar();
  }

  /// Lleva el servicio del turno a Vender, con el turno para que se descuente su seña y quede cobrado (Regla 21).
  Future<void> _cobrar(TurnoDeAgenda t) async {
    final app = _app;
    if (app == null) return;
    final falta = _faltan[t.servicio.id];
    if (falta != null) {
      return mostrarAvisoNs(context, 'Falta ${falta.toLowerCase()}: ${t.servicio.nombre} no se puede cobrar hasta que cargues la compra.', largo: true);
    }
    app.carrito
      ..clear()
      ..add(LineaVentaPorUnidad(
        productoId: '${t.servicio.id}',
        nombreProducto: t.servicio.nombre,
        proveedorId: null,
        cantidad: 1,
        precioUnitarioCentavos: t.servicio.precioCentavos ?? 0,
        costoUnitarioCentavos: t.servicio.costoCentavos,
      ));
    app.turnoEnVenta.value = t.turno.id;
    app.irAPestania(PestaniaNs.vender);
  }

  Future<void> _mover(TurnoDeAgenda t) async {
    final ctrl = TextEditingController(text: _hora(t.turno.inicio));
    var dia = _soloDia(t.turno.inicio);
    final nuevo = await mostrarHojaNs<DateTime>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHoja) => HojaNs(
          titulo: 'Mover el turno',
          texto: '${t.cliente.nombre} · ${t.servicio.nombre}',
          bloques: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var k = 0; k < 7; k++)
                  ChipNs(
                    texto: _etiquetaDia(_hoy.add(Duration(days: k))),
                    activo: dia == _hoy.add(Duration(days: k)),
                    onTap: () => setHoja(() => dia = _hoy.add(Duration(days: k))),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            CampoNs(etiqueta: 'Hora', controller: ctrl, placeholder: 'Ej.: 16:30', teclado: TextInputType.datetime, autofoco: true),
          ],
          botones: [
            BotonNs.primario(ctx, 'Mover', () {
              final m = minutosDesdeTexto(ctrl.text);
              if (m != null) Navigator.of(ctx).pop(dia.add(Duration(minutes: m)));
            }),
          ],
        ),
      ),
    );
    if (nuevo == null) return;
    await moverTurno(_db, turnoId: t.turno.id, inicio: nuevo, profesionalId: t.turno.profesionalId);
    if (mounted) mostrarAvisoNs(context, 'Turno movido');
  }

  Future<void> _tomarSena(TurnoDeAgenda t) async {
    final sesion = _sesionId;
    final usuario = _usuarioId;
    if (sesion == null || usuario == null) return mostrarAvisoNs(context, 'Para tomar una seña abrí la caja');
    final sugerida = senaSugerida(precioCentavos: t.servicio.precioCentavos ?? 0, config: await configSenaActual(_db), servicioPideSena: true);
    if (!mounted) return;
    final r = await mostrarHojaNs<({int monto, bool efectivo})>(context, builder: (_) => _HojaSena(sugeridaCentavos: sugerida, cliente: t.cliente.nombre));
    if (r == null) return;
    await tomarSenaDeTurno(_db, turnoId: t.turno.id, montoCentavos: r.monto, esEfectivo: r.efectivo, sesionCajaId: sesion, usuarioId: usuario);
    if (mounted) mostrarAvisoNs(context, 'Seña de ${plataNs(r.monto)} anotada');
  }

  Future<void> _configurar() async {
    final guardo = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PantallaHorarioYSenaNs(db: _db)));
    if (guardo == true) await _cargar();
  }

  String _etiquetaDia(DateTime d) {
    if (d == _hoy) return 'Hoy';
    if (d == _hoy.add(const Duration(days: 1))) return 'Mañana';
    return '${_diasCortos[d.weekday - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) {
        final varios = modulos.estaActivo(Modulo.profesionales);
        return PantallaEntradaNs(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dia == _hoy ? 'Hoy' : '${_diasLargos[_dia.weekday - 1]} ${_dia.day}',
                          style: tituloNs(42, track: -0.055, color: ns.ink),
                        ),
                      ),
                      if (_soloCelular) ...[
                        BotonCircularNs(icono: IconoNs.ajustes, onTap: _configurar, etiqueta: 'Horario y seña'),
                        const SizedBox(width: 10),
                        BotonCircularNs(icono: IconoNs.masMas, onTap: () => _nuevoTurno(), etiqueta: 'Nuevo turno'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: !_soloCelular
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: margenNs),
                          child: InfoNs('La agenda se maneja desde el celular en modo "Solo celular". Con la PC todavía no está: llega en una próxima versión.'),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado - 8),
                          children: [
                            _TiraDias(lunes: _lunes, elegido: _dia, hoy: _hoy, porDia: _porDia, onElegir: _irADia),
                            const SizedBox(height: 12),
                            if (varios && _profesionales.length > 1) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChipNs(texto: 'Todos', activo: _profesional == null, onTap: () => setState(() => _profesional = null)),
                                  for (final p in _profesionales)
                                    ChipNs(texto: p.nombre, activo: _profesional == p.id, onTap: () => setState(() => _profesional = p.id)),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            ..._lista(context, varios),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _lista(BuildContext context, bool varios) {
    final turnos = _turnos;
    if (turnos == null) return const [EsqueletoListaNs()];
    final visibles = [for (final t in turnos) if (!varios || _profesional == null || t.turno.profesionalId == _profesional) t];
    // Los huecos libres solo tienen sentido mirando UNA agenda (sin varios profesionales, o con uno elegido), como el mock.
    final unaAgenda = !varios || _profesional != null;
    final huecos = unaAgenda ? huecosLibres(dia: _dia, horario: _horario, turnos: [for (final t in visibles) t.paraAgenda]) : const <({DateTime desde, DateTime hasta})>[];
    final filas = <(DateTime, Widget)>[
      for (final t in visibles) (t.turno.inicio, _FilaTurno(t: t, varios: varios, falta: _faltan[t.servicio.id], onTap: () => _abrirTurno(t))),
      for (final h in huecos)
        (
          h.desde,
          _FilaLibre(
            desde: h.desde,
            hasta: h.hasta,
            onTap: () => _nuevoTurno(hora: h.desde),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [
      if (_horario.franjaDe(_dia) == null) const InfoNs('Este día el local está cerrado. Igual podés anotar un turno.'),
      if (visibles.isEmpty && _horario.franjaDe(_dia) != null && huecos.isEmpty) const InfoNs('No hay turnos este día.'),
      if (visibles.isEmpty) const SizedBox(height: 8),
      for (final (_, w) in filas) Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
    ];
  }
}

class _TiraDias extends StatelessWidget {
  const _TiraDias({required this.lunes, required this.elegido, required this.hoy, required this.porDia, required this.onElegir});

  final DateTime lunes;
  final DateTime elegido;
  final DateTime hoy;
  final Map<DateTime, int> porDia;
  final ValueChanged<DateTime> onElegir;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      children: [
        BotonCircularNs(icono: IconoNs.volver, onTap: () => onElegir(elegido.subtract(const Duration(days: 7))), etiqueta: 'Semana anterior', tamanioIcono: 16),
        for (var k = 0; k < 7; k++)
          Expanded(
            child: Builder(builder: (context) {
              final d = lunes.add(Duration(days: k));
              final activo = d == elegido;
              final n = porDia[d] ?? 0;
              return PresionNs(
                onTap: () => onElegir(d),
                etiqueta: '${_diasLargos[k]} ${d.day}${n > 0 ? ', $n turnos' : ''}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: activo ? ns.prim : (d == hoy ? ns.ibg : ns.s), borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    children: [
                      Text(_diasCortos[k], style: estiloNs(12, peso: FontWeight.w600, color: activo ? TokensNs.blanco : ns.mute)),
                      Text('${d.day}', style: estiloNs(17, peso: FontWeight.w700, color: activo ? TokensNs.blanco : ns.ink, tabular: true)),
                      Text(n == 0 ? ' ' : '•' * (n > 4 ? 3 : n > 1 ? 2 : 1), style: estiloNs(11, color: activo ? TokensNs.blanco : ns.i)),
                    ],
                  ),
                ),
              );
            }),
          ),
        BotonCircularNs(icono: IconoNs.chevron, onTap: () => onElegir(elegido.add(const Duration(days: 7))), etiqueta: 'Semana siguiente', tamanioIcono: 16),
      ],
    );
  }
}

class _FilaTurno extends StatelessWidget {
  const _FilaTurno({required this.t, required this.varios, required this.falta, required this.onTap});

  final TurnoDeAgenda t;
  final bool varios;
  final String? falta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final estado = t.estado;
    final hecho = estado == EstadoTurno.cobrado || estado == EstadoTurno.noVino || estado == EstadoTurno.cancelado;
    final color = switch (estado) {
      EstadoTurno.sinConfirmar => ns.w,
      EstadoTurno.confirmado => ns.i,
      EstadoTurno.llego => ns.g,
      EstadoTurno.cobrado => ns.mute,
      EstadoTurno.noVino || EstadoTurno.cancelado => ns.b,
    };
    final etiquetas = [
      estado.nombre,
      if (t.origen == OrigenTurno.whatsapp) 'WhatsApp',
      if (t.turno.senaCentavos > 0) 'Seña ${plataNs(t.turno.senaCentavos)}',
      if (falta != null && !hecho) 'Falta ${falta!.toLowerCase()}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_hora(t.turno.inicio), style: estiloNs(16, peso: FontWeight.w700, color: ns.ink, tabular: true)),
                Text('${t.turno.duracionMinutos} min', style: estiloNs(12, color: ns.mute)),
              ],
            ),
          ),
        ),
        Expanded(
          child: Opacity(
            opacity: hecho ? 0.6 : 1,
            child: PresionNs(
              onTap: onTap,
              etiqueta: '${t.cliente.nombre}, ${_hora(t.turno.inicio)}',
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: ns.s,
                  borderRadius: BorderRadius.circular(24),
                  border: Border(left: BorderSide(color: color, width: 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.cliente.nombre, style: estiloNs(17, peso: FontWeight.w600, color: ns.ink)),
                    Text('${t.servicio.nombre}${varios && t.profesional != null ? ' · ${t.profesional!.nombre}' : ''}', style: estiloNs(14, color: ns.mute)),
                    const SizedBox(height: 4),
                    Text(etiquetas.join(' · '), style: estiloNs(13, peso: FontWeight.w600, color: falta != null && !hecho ? ns.b : color)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilaLibre extends StatelessWidget {
  const _FilaLibre({required this.desde, required this.hasta, required this.onTap});

  final DateTime desde;
  final DateTime hasta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      children: [
        SizedBox(width: 58, child: Text(_hora(desde), style: estiloNs(16, peso: FontWeight.w600, color: ns.mute, tabular: true))),
        Expanded(
          child: PresionNs(
            onTap: onTap,
            etiqueta: 'Libre desde las ${_hora(desde)}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: ns.line)),
              child: Row(
                children: [
                  Expanded(child: Text('Libre hasta las ${_hora(hasta)}', style: estiloNs(15, color: ns.mute))),
                  Text('+ Turno', style: estiloNs(15, peso: FontWeight.w700, color: ns.i)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lo que se puede hacer con un turno. Devuelve la acción: 'cobrar', 'mover', 'sena' o la clave del estado nuevo.
class _HojaTurno extends StatelessWidget {
  const _HojaTurno({required this.t, required this.falta, required this.conCaja});

  final TurnoDeAgenda t;
  final String? falta;
  final bool conCaja;

  @override
  Widget build(BuildContext context) {
    final estado = t.estado;
    void elegir(String a) => Navigator.of(context).pop(a);
    final detalle = [
      '${t.servicio.nombre} · ${_hora(t.turno.inicio)} · ${t.turno.duracionMinutos} min',
      if (t.profesional != null) 'Con ${t.profesional!.nombre}',
      if (t.cliente.telefono != null) 'Tel. ${t.cliente.telefono}',
      if (t.turno.senaCentavos > 0) 'Seña ${plataNs(t.turno.senaCentavos)} (${t.turno.senaEsEfectivo ? 'efectivo' : 'Mercado Pago'})',
      'Precio ${plataNs(t.servicio.precioCentavos ?? 0)}',
    ].join('\n');
    return HojaNs(
      titulo: t.cliente.nombre,
      texto: detalle,
      bloques: [
        if (estado.terminado) InfoNs('Este turno está ${estado.nombre.toLowerCase()}.'),
        if (!estado.terminado && falta != null)
          InfoNs('No se puede cobrar: falta ${falta!.toLowerCase()}. Cargá la compra primero.', tono: TonoNs.bad, icono: IconoNs.candado),
        if (!estado.terminado && t.turno.senaCentavos > 0)
          const InfoNs('Si lo cancelás, la seña se devuelve. Si no viene, según lo que configuraste en Horario y seña.', tamanio: 13, vertical: 10),
      ],
      botones: estado.terminado
          ? const []
          : [
              BotonNs.primario(context, 'Cobrar este turno', falta == null ? () => elegir('cobrar') : null, habilitado: falta == null, icono: IconoNs.carrito),
              if (estado == EstadoTurno.sinConfirmar) BotonNs.secundario(context, 'Confirmar', () => elegir(EstadoTurno.confirmado.clave)),
              Row(
                children: [
                  if (estado != EstadoTurno.llego) ...[
                    Expanded(child: BotonNs.secundario(context, 'Llegó', () => elegir(EstadoTurno.llego.clave))),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: BotonNs.secundario(context, 'No vino', () => elegir(EstadoTurno.noVino.clave))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: BotonNs.secundario(context, 'Mover', () => elegir('mover'))),
                  const SizedBox(width: 8),
                  Expanded(child: BotonNs.secundario(context, 'Seña', conCaja ? () => elegir('sena') : null)),
                ],
              ),
              BotonNs.peligroSuave(context, 'Cancelar el turno', () => elegir(EstadoTurno.cancelado.clave)),
            ],
    );
  }
}

class _HojaSena extends StatefulWidget {
  const _HojaSena({required this.sugeridaCentavos, required this.cliente});

  final int sugeridaCentavos;
  final String cliente;

  @override
  State<_HojaSena> createState() => _HojaSenaState();
}

class _HojaSenaState extends State<_HojaSena> {
  late final _monto = TextEditingController(text: widget.sugeridaCentavos > 0 ? formatearARS(widget.sugeridaCentavos, conSigno: false) : '');
  bool _efectivo = true;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Seña',
      texto: 'Lo que deja ${widget.cliente} ahora. Entra a la caja y se descuenta al cobrar el turno.',
      bloques: [
        CampoNs(etiqueta: 'Monto', controller: _monto, teclado: const TextInputType.numberWithOptions(decimal: true), autofoco: true,
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]),
        const SizedBox(height: 10),
        SegmentoNs(opciones: const ['Efectivo', 'Mercado Pago'], indice: _efectivo ? 0 : 1, onCambio: (i) => setState(() => _efectivo = i == 0)),
      ],
      botones: [
        BotonNs.primario(context, 'Anotar la seña', () {
          final m = _centavos(_monto.text);
          if (m != null && m > 0) Navigator.of(context).pop((monto: m, efectivo: _efectivo));
        }),
      ],
    );
  }
}

class _HojaNuevoTurno extends StatefulWidget {
  const _HojaNuevoTurno({
    required this.db,
    required this.usuarioId,
    required this.dia,
    required this.hora,
    required this.servicios,
    required this.profesionales,
    required this.profesional,
    required this.horario,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;
  final DateTime dia;
  final DateTime? hora;
  final List<ServicioConCosto> servicios;

  /// Vacío sin el módulo "Varios profesionales".
  final List<Usuario> profesionales;
  final int? profesional;
  final HorarioSemana horario;
  final int? sesionCajaId;

  @override
  State<_HojaNuevoTurno> createState() => _HojaNuevoTurnoState();
}

class _HojaNuevoTurnoState extends State<_HojaNuevoTurno> {
  final _cliente = TextEditingController();
  final _telefono = TextEditingController();
  late final _horaCtrl = TextEditingController(text: widget.hora == null ? '' : _hora(widget.hora!));
  final _sena = TextEditingController();
  late Producto _servicio = widget.servicios.first.servicio;
  late int? _profesional = widget.profesional ?? (widget.profesionales.isEmpty ? null : widget.profesionales.first.id);
  bool _senaEfectivo = true;
  ConfigSena _config = ConfigSena.porDefecto;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    configSenaActual(widget.db).then((c) {
      if (!mounted) return;
      setState(() => _config = c);
      _sugerirSena();
    });
  }

  @override
  void dispose() {
    for (final c in [_cliente, _telefono, _horaCtrl, _sena]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sugerirSena() {
    final s = senaSugerida(precioCentavos: _servicio.precioCentavos ?? 0, config: _config, servicioPideSena: _servicio.pideSena);
    _sena.text = s > 0 && widget.sesionCajaId != null ? formatearARS(s, conSigno: false) : '';
  }

  Future<void> _guardar() async {
    final minutos = minutosDesdeTexto(_horaCtrl.text);
    final sena = _centavos(_sena.text);
    String? error;
    if (_cliente.text.trim().isEmpty) {
      error = 'Falta el nombre del cliente';
    } else if (minutos == null) {
      error = 'Poné la hora, por ejemplo 16:30';
    } else if (sena == null) {
      error = 'Revisá el monto de la seña';
    } else if (sena > 0 && widget.sesionCajaId == null) {
      error = 'Para tomar una seña abrí la caja';
    }
    if (error != null) return setState(() => _error = error);
    setState(() => _guardando = true);
    try {
      await anotarTurno(
        widget.db,
        cliente: _cliente.text,
        telefono: _telefono.text,
        servicioId: _servicio.id,
        profesionalId: _profesional,
        inicio: widget.dia.add(Duration(minutes: minutos!)),
        senaCentavos: sena!,
        senaEsEfectivo: _senaEfectivo,
        sesionCajaId: widget.sesionCajaId,
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutos = minutosDesdeTexto(_horaCtrl.text);
    final fueraDeHorario = minutos != null &&
        !dentroDeHorario(widget.horario, inicio: widget.dia.add(Duration(minutes: minutos)), duracionMinutos: _servicio.duracionMinutos ?? 30);
    return HojaNs(
      titulo: 'Nuevo turno',
      texto: '${_diasLargos[widget.dia.weekday - 1]} ${widget.dia.day}. Para quien llama o viene al local.',
      bloques: [
        CampoNs(etiqueta: 'Cliente', controller: _cliente, placeholder: 'Nombre', autofoco: true, onChanged: (_) => setState(() => _error = null)),
        const SizedBox(height: 8),
        CampoNs(etiqueta: 'Teléfono (opcional)', controller: _telefono, teclado: TextInputType.phone),
        const SizedBox(height: 12),
        const SeccionNs('Servicio'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in widget.servicios)
              ChipNs(
                texto: '${s.servicio.nombre} · ${s.servicio.duracionMinutos ?? 30} min',
                activo: s.servicio.id == _servicio.id,
                onTap: () => setState(() {
                  _servicio = s.servicio;
                  _sugerirSena();
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        CampoNs(
          etiqueta: 'Hora',
          controller: _horaCtrl,
          placeholder: 'Ej.: 16:30',
          teclado: TextInputType.datetime,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (fueraDeHorario) ...[
          const SizedBox(height: 6),
          const InfoNs('Queda fuera del horario de atención. Se puede anotar igual.', tono: TonoNs.warn, tamanio: 13, vertical: 10),
        ],
        if (widget.profesionales.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SeccionNs('Con'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in widget.profesionales) ChipNs(texto: p.nombre, activo: p.id == _profesional, onTap: () => setState(() => _profesional = p.id)),
            ],
          ),
        ],
        if (widget.sesionCajaId != null) ...[
          const SizedBox(height: 12),
          CampoNs(
            etiqueta: 'Seña (opcional)',
            controller: _sena,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          ),
          const SizedBox(height: 8),
          SegmentoNs(opciones: const ['Efectivo', 'Mercado Pago'], indice: _senaEfectivo ? 0 : 1, onCambio: (i) => setState(() => _senaEfectivo = i == 0)),
        ],
        if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
      ],
      botones: [BotonNs.primario(context, _guardando ? 'Anotando…' : 'Anotar turno', _guardando ? null : _guardar, icono: IconoNs.tilde)],
    );
  }
}

// ───────────────────────── Horario y seña ─────────────────────────

class PantallaHorarioYSenaNs extends StatefulWidget {
  const PantallaHorarioYSenaNs({super.key, required this.db});

  final AppDatabase db;

  @override
  State<PantallaHorarioYSenaNs> createState() => _PantallaHorarioYSenaNsState();
}

class _PantallaHorarioYSenaNsState extends State<PantallaHorarioYSenaNs> {
  final _desde = [for (var k = 0; k < 7; k++) TextEditingController()];
  final _hasta = [for (var k = 0; k < 7; k++) TextEditingController()];
  final _abierto = List<bool>.filled(7, false);
  final _valor = TextEditingController();
  ConfigSena _sena = ConfigSena.porDefecto;
  List<Producto> _servicios = const [];
  final Set<int> _piden = {};
  bool _cargado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final horario = await horarioActual(widget.db);
    final sena = await configSenaActual(widget.db);
    final servicios = [for (final s in await listarServicios(widget.db)) s.servicio];
    if (!mounted) return;
    setState(() {
      for (var k = 0; k < 7; k++) {
        final f = horario.dias[k];
        _abierto[k] = f != null;
        _desde[k].text = textoDeMinutos(f?.desdeMinutos ?? 540);
        _hasta[k].text = textoDeMinutos(f?.hastaMinutos ?? 1200);
      }
      _sena = sena;
      _valor.text = sena.esPorcentaje ? '${sena.valor ~/ 100}' : formatearARS(sena.valor, conSigno: false);
      _servicios = servicios;
      _piden
        ..clear()
        ..addAll([for (final s in servicios) if (s.pideSena) s.id]);
      _cargado = true;
    });
  }

  @override
  void dispose() {
    for (final c in [..._desde, ..._hasta, _valor]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    var horario = HorarioSemana.porDefecto;
    for (var k = 0; k < 7; k++) {
      if (!_abierto[k]) {
        horario = horario.conDia(k + 1, null);
        continue;
      }
      final d = minutosDesdeTexto(_desde[k].text), h = minutosDesdeTexto(_hasta[k].text);
      if (d == null || h == null || d >= h) return setState(() => _error = 'Revisá el horario del ${_diasLargos[k].toLowerCase()}');
      horario = horario.conDia(k + 1, FranjaHoraria(desdeMinutos: d, hastaMinutos: h));
    }
    final int valor;
    if (_sena.esPorcentaje) {
      final p = int.tryParse(_valor.text.trim().replaceAll('%', ''));
      if (p == null || p < 0 || p > 100) return setState(() => _error = 'El porcentaje va de 0 a 100');
      valor = p * 100;
    } else {
      final c = _centavos(_valor.text);
      if (c == null) return setState(() => _error = 'Revisá el monto de la seña');
      valor = c;
    }
    await configurarHorario(widget.db, horario);
    await configurarSena(widget.db, ConfigSena(modo: _sena.modo, esPorcentaje: _sena.esPorcentaje, valor: valor, siNoViene: _sena.siNoViene));
    for (final s in _servicios) {
      if (s.pideSena != _piden.contains(s.id)) await configurarPideSena(widget.db, s.id, pide: _piden.contains(s.id));
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PaginaNs(
      titulo: 'Horario y seña',
      cuerpo: !_cargado
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                const SeccionNs('Horario de atención'),
                const SizedBox(height: 8),
                for (var k = 0; k < 7; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 92, child: Text(_diasLargos[k], style: estiloNs(16, peso: FontWeight.w500, color: ns.ink))),
                        if (_abierto[k]) ...[
                          Expanded(child: CampoNs(etiqueta: 'Desde', controller: _desde[k], teclado: TextInputType.datetime)),
                          const SizedBox(width: 6),
                          Expanded(child: CampoNs(etiqueta: 'Hasta', controller: _hasta[k], teclado: TextInputType.datetime)),
                        ] else
                          Expanded(child: Text('Cerrado', style: estiloNs(15, color: ns.mute))),
                        Switch(value: _abierto[k], onChanged: (v) => setState(() => _abierto[k] = v)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const SeccionNs('Seña'),
                const SizedBox(height: 8),
                SegmentoNs(
                  opciones: const ['No pedir', 'Algunos', 'Todos'],
                  indice: ModoSena.values.indexOf(_sena.modo),
                  onCambio: (i) => setState(() => _sena = ConfigSena(modo: ModoSena.values[i], esPorcentaje: _sena.esPorcentaje, valor: _sena.valor, siNoViene: _sena.siNoViene)),
                ),
                if (_sena.modo != ModoSena.nunca) ...[
                  const SizedBox(height: 10),
                  SegmentoNs(
                    opciones: const ['% del precio', 'Monto fijo'],
                    indice: _sena.esPorcentaje ? 0 : 1,
                    onCambio: (i) => setState(() {
                      _sena = ConfigSena(modo: _sena.modo, esPorcentaje: i == 0, valor: _sena.valor, siNoViene: _sena.siNoViene);
                      _valor.text = '';
                    }),
                  ),
                  const SizedBox(height: 10),
                  CampoNs(
                    etiqueta: _sena.esPorcentaje ? 'Porcentaje del precio' : 'Monto fijo',
                    controller: _valor,
                    teclado: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  Text('Si el cliente no viene', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                  const SizedBox(height: 6),
                  SegmentoNs(
                    opciones: const ['La seña se pierde', 'Se devuelve'],
                    indice: _sena.siNoViene == SiNoViene.pierde ? 0 : 1,
                    onCambio: (i) => setState(() => _sena = ConfigSena(modo: _sena.modo, esPorcentaje: _sena.esPorcentaje, valor: _sena.valor, siNoViene: SiNoViene.values[i])),
                  ),
                  const SizedBox(height: 8),
                  const InfoNs('Si avisa y cancela, la seña se devuelve siempre.', tamanio: 13, vertical: 10),
                  if (_sena.modo == ModoSena.algunos && _servicios.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SeccionNs('Servicios que piden seña'),
                    const SizedBox(height: 8),
                    for (final s in _servicios)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InterruptorNs(
                          etiqueta: s.nombre,
                          encendido: _piden.contains(s.id),
                          onCambio: (v) => setState(() => v ? _piden.add(s.id) : _piden.remove(s.id)),
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 12),
              ],
            ),
      botones: [
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        BotonNs.primario(context, 'Guardar', _cargado ? _guardar : null, habilitado: _cargado, icono: IconoNs.tilde),
      ],
    );
  }
}
