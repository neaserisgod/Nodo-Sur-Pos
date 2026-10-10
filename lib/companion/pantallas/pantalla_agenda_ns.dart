// La Agenda (`docs/PLAN-SERVICIOS.md`, etapa 4; `REGLAS-NEGOCIO.md` §21): en un negocio de servicios reemplaza al Inicio y es
// donde abre la app. Un día por vez: los turnos por hora, dar uno nuevo con los horarios libres a mano, y en cada turno
// cobrar (con la seña descontada), anotar la seña, mover, "no vino" y cancelar.
//
// Trabaja sobre la base del celular, como Servicios: los servicios son de "Solo celular" (con la PC llegan después). Las
// cuentas son las de `domain/turnos.dart`, por `data/repositorio_turnos.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/repositorio_servicios.dart' show listarServicios, ServicioListado;
import '../../data/repositorio_turnos.dart';
import '../../data/repositorio_ventas.dart' show registrarVentaSegunMedio;
import '../../domain/dinero.dart' show parsearARS;
import '../../domain/medio_pago.dart';
import '../../domain/turnos.dart';
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../modo_uso.dart';

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Hoy", "Mañana" o "jueves 15".
String textoDiaNs(DateTime dia, {DateTime? hoy}) {
  final h = _soloDia(hoy ?? DateTime.now());
  final d = _soloDia(dia);
  final dif = d.difference(h).inDays;
  if (dif == 0) return 'Hoy';
  if (dif == 1) return 'Mañana';
  if (dif == -1) return 'Ayer';
  return '${_dias[d.weekday - 1]} ${d.day}';
}

String _fechaLarga(DateTime d) => '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}';

String horaNs(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class PantallaAgendaNs extends StatefulWidget {
  /// [db], [usuarioId] y [hoy] son para tests.
  const PantallaAgendaNs({super.key, this.db, this.usuarioId, this.hoy});

  final AppDatabase? db;
  final int? usuarioId;
  final DateTime? hoy;

  @override
  State<PantallaAgendaNs> createState() => _PantallaAgendaNsState();
}

class _PantallaAgendaNsState extends State<PantallaAgendaNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  late DateTime _dia = _soloDia(widget.hoy ?? DateTime.now());
  List<TurnoAgenda>? _turnos;
  int? _usuarioId;
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
    _sub = avisosCambiosCompanion.listen((_) => _recargar());
    _recargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _recargar() async {
    // Los turnos del bot que no pagaron la seña a tiempo liberan su horario solos (§21).
    await liberarSenasVencidas(_db);
    final turnos = await turnosDelDia(_db, _dia);
    if (!mounted) return;
    setState(() => _turnos = turnos);
  }

  void _irADia(DateTime d) {
    setState(() {
      _dia = _soloDia(d);
      _turnos = null;
    });
    _recargar();
  }

  Future<void> _conUsuario(Future<void> Function(int usuarioId) hacer) async {
    final u = _usuarioId;
    if (u == null) {
      mostrarAvisoNs(context, 'Falta elegir usuario');
      return;
    }
    await hacer(u);
  }

  Future<void> _nuevoTurno({DateTime? hora}) => _conUsuario((u) async {
        final listo = await mostrarHojaNs<String>(
          context,
          builder: (_) => HojaTurnoNs(db: _db, usuarioId: u, dia: _dia, horaElegida: hora, sesionCajaId: AppNs.maybeOf(context)?.sesion?.id),
        );
        await _recargar();
        if (listo != null && mounted) {
          mostrarAvisoNs(context, listo);
          AppNs.maybeOf(context)?.refrescar();
        }
      });

  Future<void> _acciones(TurnoAgenda t) => _conUsuario((u) async {
        final estado = t.estado;
        final abierto = estado.abierto;
        final pideSena = t.turno.senaPedidaCentavos > 0 && t.turno.senaCentavos == 0;
        final elegido = await mostrarHojaNs<String>(
          context,
          builder: (ctx) => HojaNs(
            titulo: '${horaNs(t.inicio)} · ${t.turno.nombreCliente}',
            texto: _detalle(t),
            botones: [
              if (abierto) BotonNs.primario(ctx, 'Cobrar', () => Navigator.of(ctx).pop('cobrar'), icono: IconoNs.billetes),
              if (abierto && pideSena) BotonNs.secundario(ctx, 'Anotar la seña', () => Navigator.of(ctx).pop('sena'), icono: IconoNs.tilde),
              if (abierto) BotonNs.secundario(ctx, 'Mover', () => Navigator.of(ctx).pop('mover'), icono: IconoNs.reloj),
              if (t.turno.telefono != null) BotonNs.secundario(ctx, 'Escribirle por WhatsApp', () => Navigator.of(ctx).pop('whatsapp'), icono: IconoNs.celular),
              BotonNs.secundario(ctx, 'Agregar a Google Calendar', () => Navigator.of(ctx).pop('calendar'), icono: IconoNs.calendario),
              if (abierto) BotonNs.secundario(ctx, 'No vino', () => Navigator.of(ctx).pop('novino'), icono: IconoNs.alertaCirculo),
              if (abierto) BotonNs.peligroSuave(ctx, 'Cancelar el turno', () => Navigator.of(ctx).pop('cancelar')),
            ],
          ),
        );
        if (!mounted || elegido == null) return;
        final sesion = AppNs.maybeOf(context)?.sesion?.id;
        try {
          String? aviso;
          switch (elegido) {
            case 'cobrar':
              aviso = await mostrarHojaNs<String>(context, builder: (_) => _HojaCobrarTurno(db: _db, usuarioId: u, turno: t, sesionCajaId: sesion));
            case 'sena':
              aviso = await mostrarHojaNs<String>(context, builder: (_) => _HojaSena(db: _db, usuarioId: u, turno: t, sesionCajaId: sesion));
            case 'mover':
              aviso = await mostrarHojaNs<String>(
                context,
                builder: (_) => HojaTurnoNs(db: _db, usuarioId: u, dia: _soloDia(t.inicio), existente: t, sesionCajaId: sesion),
              );
            case 'whatsapp':
              await _abrir(Uri.parse('https://wa.me/${t.turno.telefono!.replaceAll(RegExp(r'\D'), '')}'));
            case 'calendar':
              await _abrir(enlaceGoogleCalendar(t));
            case 'novino':
              await marcarNoVino(_db, t.turno.id);
              aviso = 'Anotado: ${t.turno.nombreCliente} no vino';
            case 'cancelar':
              aviso = await _cancelar(t, u, sesion);
          }
          await _recargar();
          if (aviso != null && mounted) {
            mostrarAvisoNs(context, aviso);
            AppNs.maybeOf(context)?.refrescar();
          }
        } on ArgumentError catch (e) {
          if (mounted) mostrarAvisoNs(context, '${e.message}', largo: true);
        }
      });

  Future<String?> _cancelar(TurnoAgenda t, int usuarioId, int? sesion) async {
    final config = await configAgendaActual(_db);
    if (!mounted) return null;
    final sena = t.turno.senaCentavos;
    final devuelve = sena > 0 && config.sena.devolverAlCancelar;
    final ok = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Cancelar el turno?',
        texto: sena == 0
            ? 'Se libera el horario de las ${horaNs(t.inicio)}.'
            : devuelve
                ? 'Se libera el horario y se devuelve la seña de ${plataNs(sena)} por la caja por la que entró.'
                : 'Se libera el horario. La seña de ${plataNs(sena)} queda en la caja (así está configurado: si cancelan, se pierde).',
        botones: [
          BotonNs.peligroSuave(ctx, 'Cancelar el turno', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (ok != true) return null;
    final devuelto = await cancelarTurno(_db, t.turno.id, usuarioId: usuarioId, sesionCajaId: sesion);
    return devuelto > 0 ? 'Turno cancelado. Devolvé ${plataNs(devuelto)} de la seña.' : 'Turno cancelado';
  }

  Future<void> _abrir(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) {
      mostrarAvisoNs(context, 'No se pudo abrir');
    }
  }

  String _detalle(TurnoAgenda t) {
    final partes = <String>[
      '${t.turno.servicioNombre} · ${duracionTextoNs(t.turno.duracionMinutos)} · hasta las ${horaNs(t.fin)}',
      if (t.profesional != null) 'Atiende ${t.profesional}',
      if (t.turno.senaCentavos > 0) 'Dejó ${plataNs(t.turno.senaCentavos)} de seña'
      else if (t.turno.senaPedidaCentavos > 0) 'Seña pedida: ${plataNs(t.turno.senaPedidaCentavos)} (sin pagar)',
      if (t.turno.telefono != null) t.turno.telefono!,
      if (t.turno.origen == 'BOT') 'Lo dio el bot de WhatsApp',
      if (textoFaltas(t.faltas) case final f?) 'Ojo: $f',
      if (t.turno.nota != null) t.turno.nota!,
      'Estado: ${t.estado.etiqueta}',
    ];
    return partes.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final app = AppNs.maybeOf(context);
    final conPc = app?.modoUso == ModoUso.pcYCelular;
    final hoy = _soloDia(widget.hoy ?? DateTime.now());
    return PantallaEntradaNs(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado - 8),
          children: [
            Row(
              children: [
                Expanded(child: Text('Agenda', style: tituloNs(42, track: -0.055, color: ns.ink))),
                if (!conPc)
                  BotonNs(
                    key: const Key('agenda_nuevo'),
                    texto: '+ Turno',
                    onTap: () => _nuevoTurno(),
                    alto: 44,
                    tamanio: 15,
                    fondo: ns.prim,
                    color: TokensNs.blanco,
                    rellenar: false,
                    paddingH: 20,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_fechaLarga(_dia), style: estiloNs(16, color: ns.mute)),
            const SizedBox(height: 14),
            if (conPc)
              const InfoNs('Con la PC, la agenda todavía se usa solo en "Solo celular". Las pantallas de la PC llegan más adelante.', icono: IconoNs.computadora)
            else ...[
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 15,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = DateTime(hoy.year, hoy.month, hoy.day + i - 1);
                    return ChipNs(key: ValueKey('dia-$i'), texto: textoDiaNs(d, hoy: hoy), activo: d == _dia, onTap: () => _irADia(d));
                  },
                ),
              ),
              const SizedBox(height: 16),
              ..._lista(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _lista(BuildContext context) {
    final ns = context.ns;
    final turnos = _turnos;
    if (turnos == null) return const [EsqueletoListaNs()];
    final visibles = [for (final t in turnos) if (t.estado != EstadoTurno.cancelado) t];
    final cancelados = turnos.length - visibles.length;
    if (visibles.isEmpty) {
      return [
        InfoNs(cancelados > 0 ? 'No quedan turnos para este día ($cancelados cancelado${cancelados == 1 ? '' : 's'}).' : 'No hay turnos para este día. Con "+ Turno" anotás uno.'),
      ];
    }
    return [
      ListaAgrupadaNs(
        filas: [
          for (final t in visibles)
            TarjetaFilaNs(
              key: ValueKey('turno-${t.turno.id}'),
              titulo: '${horaNs(t.inicio)}  ${t.turno.nombreCliente}',
              subtitulo: [
                t.turno.servicioNombre,
                duracionTextoNs(t.turno.duracionMinutos),
                if (t.profesional != null) t.profesional!,
                if (t.turno.origen == 'BOT') 'WhatsApp',
                ?textoFaltas(t.faltas),
              ].join(' · '),
              chevron: false,
              radio: 0,
              onTap: () => _acciones(t),
              derecha: _EtiquetaEstado(t),
            ),
        ],
      ),
      if (cancelados > 0) ...[
        const SizedBox(height: 10),
        Text('$cancelados cancelado${cancelados == 1 ? '' : 's'}', style: estiloNs(13, color: ns.mute)),
      ],
    ];
  }
}

/// El link de "Agregar a Google Calendar" (§21: sin permisos extra; la sincronización automática llega como módulo).
Uri enlaceGoogleCalendar(TurnoAgenda t) {
  String utc(DateTime d) {
    final u = d.toUtc();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${dos(u.month)}${dos(u.day)}T${dos(u.hour)}${dos(u.minute)}00Z';
  }

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': '${t.turno.servicioNombre} · ${t.turno.nombreCliente}',
    'dates': '${utc(t.inicio)}/${utc(t.fin)}',
    if (t.turno.telefono != null) 'details': 'Tel: ${t.turno.telefono}',
  });
}

class _EtiquetaEstado extends StatelessWidget {
  const _EtiquetaEstado(this.t);
  final TurnoAgenda t;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final (texto, color) = switch (t.estado) {
      EstadoTurno.esperandoSena => ('Esperando seña', ns.w),
      EstadoTurno.confirmado => (t.turno.senaCentavos > 0 ? 'Con seña' : 'Confirmado', ns.g),
      EstadoTurno.atendido => ('Atendido', ns.mute),
      EstadoTurno.noVino => ('No vino', ns.b),
      EstadoTurno.cancelado => ('Cancelado', ns.mute),
    };
    return Text(texto, style: estiloNs(13, peso: FontWeight.w600, color: color));
  }
}

int? _plata(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  try {
    return parsearARS(t);
  } on FormatException {
    return null;
  }
}

// ───────────────────────── Dar o mover un turno ─────────────────────────

/// Dar un turno nuevo, o mover [existente] (solo día, hora y quién atiende).
class HojaTurnoNs extends StatefulWidget {
  const HojaTurnoNs({super.key, required this.db, required this.usuarioId, required this.dia, this.existente, this.horaElegida, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final DateTime dia;
  final TurnoAgenda? existente;
  final DateTime? horaElegida;
  final int? sesionCajaId;

  @override
  State<HojaTurnoNs> createState() => _HojaTurnoNsState();
}

class _HojaTurnoNsState extends State<HojaTurnoNs> {
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _nota = TextEditingController();
  final _otraHora = TextEditingController();
  late DateTime _dia = _soloDia(widget.dia);
  List<ServicioListado> _servicios = const [];
  List<Usuario> _profesionales = const [];
  ServicioListado? _servicio;
  int? _profesionalId;
  List<DateTime>? _libres;
  DateTime? _hora;
  bool _verTodas = false;
  int _sena = 0;
  bool _dejoSena = false;
  bool _senaEfectivo = true;
  String? _error;
  bool _guardando = false;

  bool get _moviendo => widget.existente != null;

  @override
  void initState() {
    super.initState();
    _hora = widget.horaElegida;
    _profesionalId = widget.existente?.turno.profesionalId;
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _nota.dispose();
    _otraHora.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final servicios = [
      for (final s in await listarServicios(widget.db, conManoDeObra: false))
        if ((s.producto.duracionMinutos ?? 0) > 0) s,
    ];
    final usuarios = await (widget.db.select(widget.db.usuarios)..where((u) => u.activo.equals(true))).get();
    if (!mounted) return;
    setState(() {
      _servicios = servicios;
      _profesionales = usuarios;
      final e = widget.existente;
      if (e != null) {
        _servicio = servicios.where((s) => s.producto.id == e.turno.servicioId).firstOrNull;
      } else if (servicios.length == 1) {
        _servicio = servicios.single;
      }
    });
    await _alCambiarServicio();
  }

  int get _duracion => widget.existente?.turno.duracionMinutos ?? _servicio?.producto.duracionMinutos ?? 0;

  Future<void> _alCambiarServicio() async {
    final s = _servicio;
    if (s != null && !_moviendo) {
      final sena = await senaParaServicio(widget.db, s.producto);
      if (mounted) setState(() => _sena = sena);
    }
    await _buscarLibres();
  }

  Future<void> _buscarLibres() async {
    if (_duracion <= 0) {
      setState(() => _libres = null);
      return;
    }
    final libres = await horariosLibresDelDia(
      widget.db,
      _dia,
      duracionMin: _duracion,
      profesionalId: _profesionales.length > 1 ? _profesionalId : null,
      salvoTurnoId: widget.existente?.turno.id,
      ahora: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _libres = libres;
      if (_hora != null && _soloDia(_hora!) != _dia) _hora = null;
    });
  }

  void _elegirProfesional(int? id) {
    setState(() {
      _profesionalId = id;
      _hora = null;
    });
    _buscarLibres();
  }

  DateTime? _horaFinal() {
    final escrita = _otraHora.text.trim();
    if (escrita.isNotEmpty) {
      final m = minutosDeHora(escrita);
      if (m == null) return null;
      return DateTime(_dia.year, _dia.month, _dia.day, 0, m);
    }
    return _hora;
  }

  Future<void> _guardar() async {
    final servicio = _servicio;
    final hora = _horaFinal();
    if (!_moviendo && servicio == null) return setState(() => _error = 'Elegí el servicio');
    if (hora == null) return setState(() => _error = _otraHora.text.trim().isEmpty ? 'Elegí la hora' : 'La hora va como 10:30');
    if (!_moviendo && _nombre.text.trim().isEmpty) return setState(() => _error = 'Poné el nombre de quien viene');
    final tramo = (inicio: hora, duracionMin: _duracion);
    final profesional = _profesionales.length > 1 ? _profesionalId : null;
    final pisa = await turnosQueSePisan(widget.db, tramo, profesionalId: profesional, salvoTurnoId: widget.existente?.turno.id);
    final config = await configAgendaActual(widget.db);
    final fuera = fueraDeHorario(tramo, config.horario);
    if ((pisa.isNotEmpty || fuera) && mounted) {
      final avisos = [
        if (pisa.isNotEmpty) 'Se pisa con ${pisa.map((t) => '${horaNs(t.inicio)} ${t.turno.nombreCliente}').join(', ')}.',
        if (fuera) 'Está fuera del horario de atención.',
      ];
      final seguir = await mostrarHojaNs<bool>(
        context,
        builder: (ctx) => HojaNs(
          titulo: pisa.isNotEmpty ? '¿Sobreturno?' : '¿Fuera de horario?',
          texto: '${avisos.join(' ')} ¿Lo guardo igual?',
          botones: [
            BotonNs.primario(ctx, 'Guardar igual', () => Navigator.of(ctx).pop(true)),
            BotonNs.secundario(ctx, 'Elegir otra hora', () => Navigator.of(ctx).pop(false)),
          ],
        ),
      );
      if (seguir != true) return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final e = widget.existente;
      if (e != null) {
        await moverTurno(widget.db, e.turno.id, hora, profesionalId: profesional, cambiarProfesional: _profesionales.length > 1);
        if (mounted) Navigator.of(context).pop('Turno movido a ${textoDiaNs(hora).toLowerCase()} ${horaNs(hora)}');
        return;
      }
      final dejo = _dejoSena && _sena > 0;
      await crearTurno(
        widget.db,
        servicioId: servicio!.producto.id,
        inicio: hora,
        nombreCliente: _nombre.text,
        telefono: _telefono.text,
        profesionalId: profesional,
        usuarioId: widget.usuarioId,
        nota: _nota.text,
        senaCentavos: dejo ? _sena : 0,
        senaEsEfectivo: _senaEfectivo,
        sesionCajaId: widget.sesionCajaId,
      );
      final sinCaja = dejo && widget.sesionCajaId == null;
      if (mounted) {
        Navigator.of(context).pop(
          'Turno anotado: ${textoDiaNs(hora).toLowerCase()} ${horaNs(hora)}${sinCaja ? '. La seña entra a la caja cuando la abras' : ''}',
        );
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final libres = _libres;
    final hoy = _soloDia(DateTime.now());
    final mostrar = libres == null ? const <DateTime>[] : (_verTodas ? libres : libres.take(12).toList());
    return HojaNs(
      titulo: _moviendo ? 'Mover el turno' : 'Nuevo turno',
      bloques: [
        if (!_moviendo) ...[
          if (_servicios.isEmpty)
            const InfoNs('Primero cargá un servicio con su duración en la pestaña Servicios.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _servicios)
                  ChipNs(
                    key: ValueKey('turno-servicio-${s.producto.id}'),
                    texto: s.producto.nombre,
                    activo: _servicio?.producto.id == s.producto.id,
                    onTap: () {
                      setState(() {
                        _servicio = s;
                        _hora = null;
                      });
                      _alCambiarServicio();
                    },
                  ),
              ],
            ),
        ] else
          Text('${widget.existente!.turno.servicioNombre} · ${widget.existente!.turno.nombreCliente}', style: estiloNs(16, peso: FontWeight.w600, color: ns.ink)),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 30,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = DateTime(hoy.year, hoy.month, hoy.day + i);
              return ChipNs(
                texto: textoDiaNs(d, hoy: hoy),
                activo: d == _dia,
                onTap: () {
                  setState(() {
                    _dia = d;
                    _hora = null;
                  });
                  _buscarLibres();
                },
              );
            },
          ),
        ),
        if (_profesionales.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChipNs(texto: 'Cualquiera', activo: _profesionalId == null, onTap: () => _elegirProfesional(null)),
              for (final p in _profesionales) ChipNs(texto: p.nombre, activo: _profesionalId == p.id, onTap: () => _elegirProfesional(p.id)),
            ],
          ),
        if (_duracion > 0) ...[
          SeccionNs('Horarios libres · ${duracionTextoNs(_duracion)}'),
          if (libres == null)
            const EsqueletoListaNs()
          else if (libres.isEmpty)
            const InfoNs('No quedan horarios libres ese día. Podés escribir otra hora abajo (sobreturno).')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in mostrar)
                  ChipNs(
                    key: ValueKey('hora-${horaNs(h)}'),
                    texto: horaNs(h),
                    activo: _hora == h && _otraHora.text.isEmpty,
                    onTap: () => setState(() {
                      _hora = h;
                      _otraHora.clear();
                    }),
                  ),
                if (!_verTodas && libres.length > mostrar.length) ChipNs(texto: 'Más…', activo: false, onTap: () => setState(() => _verTodas = true)),
              ],
            ),
          CampoNs(etiqueta: 'Otra hora (opcional)', controller: _otraHora, placeholder: '10:30', teclado: TextInputType.datetime, onChanged: (_) => setState(() {})),
        ],
        if (!_moviendo) ...[
          CampoNs(key: const Key('turno_nombre'), etiqueta: 'Nombre', controller: _nombre, placeholder: 'Quién viene'),
          CampoNs(etiqueta: 'Teléfono (opcional)', controller: _telefono, placeholder: '2944 123456', teclado: TextInputType.phone),
          if (_sena > 0) ...[
            InterruptorNs(
              etiqueta: 'Dejó la seña (${plataNs(_sena)})',
              descripcion: widget.sesionCajaId == null ? 'Sin caja abierta: entra cuando la abras.' : 'Entra a la caja como ingreso.',
              encendido: _dejoSena,
              onCambio: (v) => setState(() => _dejoSena = v),
            ),
            if (_dejoSena) SegmentoNs(opciones: const ['Efectivo', 'Mercado Pago'], indice: _senaEfectivo ? 0 : 1, onCambio: (i) => setState(() => _senaEfectivo = i == 0)),
          ],
          CampoNs(etiqueta: 'Nota (opcional)', controller: _nota),
        ],
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [
        BotonNs.primario(context, _moviendo ? 'Mover' : 'Guardar turno', _guardando ? null : _guardar, habilitado: !_guardando, icono: IconoNs.tilde),
      ],
    );
  }
}

// ───────────────────────── Seña y cobro ─────────────────────────

class _HojaSena extends StatefulWidget {
  const _HojaSena({required this.db, required this.usuarioId, required this.turno, required this.sesionCajaId});
  final AppDatabase db;
  final int usuarioId;
  final TurnoAgenda turno;
  final int? sesionCajaId;

  @override
  State<_HojaSena> createState() => _HojaSenaState();
}

class _HojaSenaState extends State<_HojaSena> {
  late final _monto = TextEditingController(text: '${widget.turno.turno.senaPedidaCentavos ~/ 100}');
  bool _efectivo = false;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final monto = _plata(_monto.text);
    if (monto == null || monto <= 0) return setState(() => _error = 'Poné cuánto dejó');
    try {
      await registrarSenaDeTurno(widget.db, widget.turno.turno.id, montoCentavos: monto, esEfectivo: _efectivo, usuarioId: widget.usuarioId, sesionCajaId: widget.sesionCajaId);
      if (mounted) {
        Navigator.of(context).pop(widget.sesionCajaId == null ? 'Seña anotada: entra a la caja cuando la abras' : 'Seña anotada. El turno queda confirmado');
      }
    } on ArgumentError catch (e) {
      setState(() => _error = '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Anotar la seña',
      texto: 'De ${widget.turno.turno.nombreCliente}, para ${widget.turno.turno.servicioNombre}. Entra a la caja como ingreso y se descuenta al cobrar.',
      bloques: [
        CampoNs(etiqueta: 'Cuánto dejó', controller: _monto, grande: true, teclado: TextInputType.number, formatos: soloDigitosNs),
        SegmentoNs(opciones: const ['Efectivo', 'Mercado Pago'], indice: _efectivo ? 0 : 1, onCambio: (i) => setState(() => _efectivo = i == 0)),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, 'Anotar seña', _guardar, icono: IconoNs.tilde)],
    );
  }
}

/// Cobrar el turno: el servicio al precio de hoy menos la seña, en efectivo o por Mercado Pago (a mano: una transferencia, un
/// QR que ya se pagó). Para cobrar con la terminal, el servicio se cobra desde Vender.
class _HojaCobrarTurno extends StatefulWidget {
  const _HojaCobrarTurno({required this.db, required this.usuarioId, required this.turno, required this.sesionCajaId});
  final AppDatabase db;
  final int usuarioId;
  final TurnoAgenda turno;
  final int? sesionCajaId;

  @override
  State<_HojaCobrarTurno> createState() => _HojaCobrarTurnoState();
}

class _HojaCobrarTurnoState extends State<_HojaCobrarTurno> {
  ({int total, int sena, int aCobrar, int aDevolver})? _cuenta;
  String? _error;
  bool _cobrando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final a = await cuentaDeTurno(widget.db, widget.turno.turno.id);
      if (!mounted) return;
      setState(() => _cuenta = (
            total: a.aplicadaCentavos + a.aCobrarCentavos,
            sena: a.aplicadaCentavos,
            aCobrar: a.aCobrarCentavos,
            aDevolver: a.aDevolverCentavos,
          ));
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    }
  }

  Future<void> _cobrar(ComposicionPago medio) async {
    final sesion = widget.sesionCajaId;
    if (sesion == null) return;
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final r = await registrarVentaSegunMedio(
        widget.db,
        lineas: [await lineaDeTurno(widget.db, widget.turno.turno.id)],
        medio: medio,
        canal: medio == ComposicionPago.virtual ? 'qr' : null,
        sesionCajaId: sesion,
        usuarioId: widget.usuarioId,
        turnoId: widget.turno.turno.id,
      );
      final sena = _cuenta?.sena ?? 0;
      if (mounted) Navigator.of(context).pop('Cobrado: ${plataNs(r.totalCentavos - sena)}${sena > 0 ? ' (más ${plataNs(sena)} de seña)' : ''}');
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = '${e.message}');
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cuenta;
    final sinCaja = widget.sesionCajaId == null;
    return HojaNs(
      titulo: 'Cobrar ${widget.turno.turno.servicioNombre}',
      texto: 'A ${widget.turno.turno.nombreCliente}.',
      bloques: [
        if (c != null) ...[
          FilaClaveValorNs(clave: 'Servicio (precio de hoy)', valor: plataNs(c.total)),
          if (c.sena > 0) FilaClaveValorNs(clave: 'Seña que dejó', valor: '−${plataNs(c.sena)}'),
          FilaClaveValorNs(clave: 'A cobrar', valor: plataNs(c.aCobrar), tamanioValor: 24, sinLinea: true),
          if (c.aDevolver > 0) InfoNs('La seña es más que el precio de hoy: devolvé ${plataNs(c.aDevolver)}.', tono: TonoNs.warn),
        ] else if (_error == null)
          const EsqueletoListaNs(),
        if (sinCaja) const InfoNs('Para cobrar, abrí la caja primero.', tono: TonoNs.warn, icono: IconoNs.candado),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [
        if (c != null && !sinCaja) ...[
          BotonNs.primario(context, c.aCobrar == 0 ? 'Listo (ya estaba pago)' : 'Efectivo', _cobrando ? null : () => _cobrar(ComposicionPago.efectivo), habilitado: !_cobrando, icono: IconoNs.billetes),
          if (c.aCobrar > 0) BotonNs.secundario(context, 'Mercado Pago (ya cobrado)', _cobrando ? null : () => _cobrar(ComposicionPago.virtual), icono: IconoNs.tarjeta),
        ],
      ],
    );
  }
}
