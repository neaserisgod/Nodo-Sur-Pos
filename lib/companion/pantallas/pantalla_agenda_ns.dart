// La Agenda (`docs/PLAN-SERVICIOS.md`, etapa 4; `REGLAS-NEGOCIO.md` §21): en un negocio de servicios reemplaza al Inicio y es
// donde abre la app. Diseño del mock (`docs/mock-servicios/NodoSurServicios.html`, vAgenda; El dueño, 2026-10-11: "agenda está
// muy vacío"): la semana con puntitos, las cifras de hoy y la línea del día con los huecos libres. Un día por vez: los turnos por hora, dar uno nuevo con los horarios libres a mano, y en cada turno
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
import '../../servicios/calendario.dart';
import '../../servicios/sena_mp_nube.dart';
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

  /// Turnos que ocupan, por día, en la semana que se ve (los puntitos de la tira).
  Map<DateTime, int> _porDia = const {};
  HorarioAtencion _horario = HorarioAtencion.porDefecto;
  List<Usuario> _profesionales = const [];

  /// Agenda de quién se mira, con varios profesionales (null = todos).
  int? _profesionalId;
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
    final lunes = _lunesDe(_dia);
    final dia = _dia;
    final turnos = await turnosDelDia(_db, dia);
    final semana = await turnosEntre(_db, desde: lunes, hasta: DateTime(lunes.year, lunes.month, lunes.day + 7), incluirLiberados: false);
    final config = await configAgendaActual(_db);
    final profesionales = await (_db.select(_db.usuarios)..where((u) => u.activo.equals(true))).get();
    if (!mounted || dia != _dia) return;
    final porDia = <DateTime, int>{};
    for (final t in semana) {
      if (!t.estado.ocupa) continue;
      final d = _soloDia(t.inicio);
      porDia[d] = (porDia[d] ?? 0) + 1;
    }
    setState(() {
      _turnos = turnos;
      _porDia = porDia;
      _horario = config.horario;
      _profesionales = profesionales;
    });
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
              BotonNs.secundario(ctx, 'Agendar en el calendario', () => Navigator.of(ctx).pop('calendar'), icono: IconoNs.calendario),
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
              if (!await agendarEnCalendario(
                titulo: '${t.turno.servicioNombre} · ${t.turno.nombreCliente}',
                inicio: t.inicio,
                fin: t.fin,
                detalle: t.turno.telefono == null ? null : 'Tel: ${t.turno.telefono}',
              )) {
                aviso = 'No se pudo abrir el calendario';
              }
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
    // Una seña del bot que entró por Mercado Pago (el link, Nodo Sur Servicios): se le devuelve a la clienta por Mercado Pago, con
    // un toque, si la dueña lo confirma (El dueño, 2026-10-10).
    final porLink = devuelve && !t.turno.senaEsEfectivo && t.turno.origen == 'BOT' && t.turno.idRemoto != null;
    final ok = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Cancelar el turno?',
        texto: sena == 0
            ? 'Se libera el horario de las ${horaNs(t.inicio)}.'
            : porLink
                ? '¿Devolver ${plataNs(sena)} a ${t.turno.nombreCliente}? Se libera el horario y la seña le vuelve por Mercado Pago.'
                : devuelve
                    ? 'Se libera el horario y se devuelve la seña de ${plataNs(sena)} por la caja por la que entró.'
                    : 'Se libera el horario. La seña de ${plataNs(sena)} queda en la caja (así está configurado: si cancelan, se pierde).',
        botones: [
          BotonNs.peligroSuave(ctx, porLink ? 'Devolver y cancelar' : 'Cancelar el turno', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (ok != true) return null;
    var porMercadoPago = false;
    if (porLink) {
      final r = await devolverSenaMpDelCelular(t.turno.idRemoto!);
      switch (r.resultado) {
        case ResultadoDevolucionSena.devuelta:
          porMercadoPago = true;
        case ResultadoDevolucionSena.noEsDelLink:
          break; // se anotó a mano: se devuelve como siempre
        case ResultadoDevolucionSena.error:
          // Sin devolver no se cancela: la clienta se quedaría sin su plata y sin turno.
          return 'No se canceló: ${r.mensaje ?? 'no se pudo devolver la seña'}';
      }
    }
    final devuelto = await cancelarTurno(_db, t.turno.id, usuarioId: usuarioId, sesionCajaId: sesion);
    if (porMercadoPago) return 'Turno cancelado. Le devolvimos ${plataNs(devuelto > 0 ? devuelto : sena)} por Mercado Pago.';
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
    final titulo = textoDiaNs(_dia, hoy: hoy);
    return PantallaEntradaNs(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado - 8),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Agenda', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
                      const SizedBox(height: 2),
                      Text('${titulo[0].toUpperCase()}${titulo.substring(1)}', style: tituloNs(40, track: -0.055, color: ns.ink)),
                    ],
                  ),
                ),
                if (!conPc)
                  BotonCircularNs(
                    key: const Key('agenda_nuevo'),
                    icono: IconoNs.masMas,
                    etiqueta: 'Nuevo turno',
                    onTap: () => _nuevoTurno(),
                    tamanio: 52,
                    fondo: ns.prim,
                    colorIcono: TokensNs.blanco,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (conPc)
              const InfoNs('Con la PC, la agenda todavía se usa solo en "Solo celular". Las pantallas de la PC llegan más adelante.', icono: IconoNs.computadora)
            else ...[
              _TiraSemana(
                dia: _dia,
                hoy: hoy,
                porDia: _porDia,
                onDia: _irADia,
              ),
              if (_dia == hoy) ...[
                const SizedBox(height: 16),
                _ResumenHoy(turnos: _turnos ?? const [], app: app),
              ],
              if (_profesionales.length > 1) ...[
                const SizedBox(height: 14),
                FilaChipsNs(
                  chips: [
                    ChipNs(texto: 'Todos', activo: _profesionalId == null, onTap: () => setState(() => _profesionalId = null)),
                    for (final p in _profesionales)
                      ChipNs(texto: p.nombre, activo: _profesionalId == p.id, onTap: () => setState(() => _profesionalId = p.id)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              ..._lista(context, hoy),
            ],
          ],
        ),
      ),
    );
  }

  /// Color de la barrita de cada turno: el de quien atiende si hay varios (como en el mock), el de la marca si no.
  Color _colorDe(BuildContext context, TurnoAgenda t) {
    final ns = context.ns;
    if (_profesionales.length < 2) return TokensNs.marca;
    final i = _profesionales.indexWhere((p) => p.id == t.turno.profesionalId);
    if (i < 0) return ns.line;
    return [TokensNs.marca, ns.g, ns.w, ns.i, ns.b][i % 5];
  }

  List<Widget> _lista(BuildContext context, DateTime hoy) {
    final ns = context.ns;
    final turnos = _turnos;
    if (turnos == null) return const [EsqueletoListaNs()];
    final delDia = [
      for (final t in turnos)
        if (_profesionalId == null || t.turno.profesionalId == _profesionalId) t,
    ];
    final visibles = [for (final t in delDia) if (t.estado != EstadoTurno.cancelado) t];
    final cancelados = delDia.length - visibles.length;
    final ahora = DateTime.now();
    final esHoy = _dia == _soloDia(ahora);
    final franja = _horario.delDia(_dia);
    // Un día que ya pasó no tiene huecos para ofrecer.
    final pasado = _dia.isBefore(_soloDia(ahora));
    final filas = filasDeAgenda<TurnoAgenda>(
      turnos: visibles,
      inicioMin: (t) => t.inicio.hour * 60 + t.inicio.minute,
      duracionMin: (t) => t.turno.duracionMinutos,
      ocupa: (t) => t.estado.ocupa,
      franja: pasado ? null : franja,
      ahoraMin: esHoy ? ahora.hour * 60 + ahora.minute : null,
      // Con varios profesionales mirados todos juntos, un hueco de una no es de las otras.
      conHuecos: _profesionales.length < 2 || _profesionalId != null,
    );
    final vacio = visibles.isEmpty;
    return [
      if (vacio)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InfoNs(
            cancelados > 0
                ? 'No quedan turnos para este día ($cancelados cancelado${cancelados == 1 ? '' : 's'}).'
                : franja == null
                    ? 'No hay turnos para este día. Está cerrado según el horario de atención.'
                    : 'No hay turnos para este día. Los que pidan por WhatsApp aparecen acá solos.',
            icono: IconoNs.calendario,
          ),
        ),
      if (!vacio || filas.any((f) => f is FilaLibre))
        for (final f in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: switch (f) {
              FilaTurno(:final turno) => _FilaTurno(
                  key: ValueKey('turno-${turno.turno.id}'),
                  t: turno,
                  color: _colorDe(context, turno),
                  profesional: _profesionales.length > 1 ? turno.profesional : null,
                  onTap: () => _acciones(turno),
                ),
              FilaLibre(:final desdeMin, :final hastaMin) => _FilaLibre(
                  desdeMin: desdeMin,
                  hastaMin: hastaMin,
                  onTap: () => _nuevoTurno(hora: DateTime(_dia.year, _dia.month, _dia.day, 0, desdeMin)),
                ),
              FilaAhora() => _MarcaAhora(ahora),
            },
          ),
      if (cancelados > 0 && !vacio) ...[
        const SizedBox(height: 2),
        Text('$cancelados cancelado${cancelados == 1 ? '' : 's'}', style: estiloNs(13, color: ns.mute)),
      ],
    ];
  }
}

DateTime _lunesDe(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// La semana del día elegido (lunes a domingo), con puntitos por cuántos turnos tiene cada día, y flechas para ir y volver.
class _TiraSemana extends StatelessWidget {
  const _TiraSemana({required this.dia, required this.hoy, required this.porDia, required this.onDia});
  final DateTime dia;
  final DateTime hoy;
  final Map<DateTime, int> porDia;
  final ValueChanged<DateTime> onDia;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final lunes = _lunesDe(dia);
    final domingo = DateTime(lunes.year, lunes.month, lunes.day + 6);
    final mes = lunes.month == domingo.month ? _meses[lunes.month - 1] : '${_meses[lunes.month - 1]} – ${_meses[domingo.month - 1]}';
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('${mes[0].toUpperCase()}${mes.substring(1)}', style: estiloNs(15, peso: FontWeight.w600, color: ns.ink))),
            if (dia != hoy)
              PresionNs(
                key: const Key('agenda_hoy'),
                onTap: () => onDia(hoy),
                etiqueta: 'Ir a hoy',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Hoy', style: estiloNs(15, peso: FontWeight.w600, color: ns.prim)),
                ),
              ),
            BotonCircularNs(
              key: const Key('agenda_semana_anterior'),
              icono: IconoNs.volver,
              etiqueta: 'Semana anterior',
              tamanio: 36,
              tamanioIcono: 18,
              onTap: () => onDia(DateTime(dia.year, dia.month, dia.day - 7)),
            ),
            const SizedBox(width: 8),
            BotonCircularNs(
              key: const Key('agenda_semana_siguiente'),
              icono: IconoNs.chevron,
              etiqueta: 'Semana siguiente',
              tamanio: 36,
              tamanioIcono: 18,
              onTap: () => onDia(DateTime(dia.year, dia.month, dia.day + 7)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 2, right: i == 6 ? 0 : 2),
                  child: _Dia(
                    dia: DateTime(lunes.year, lunes.month, lunes.day + i),
                    hoy: hoy,
                    elegido: dia,
                    turnos: porDia[DateTime(lunes.year, lunes.month, lunes.day + i)] ?? 0,
                    onTap: onDia,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({required this.dia, required this.hoy, required this.elegido, required this.turnos, required this.onTap});
  final DateTime dia;
  final DateTime hoy;
  final DateTime elegido;
  final int turnos;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final on = dia == elegido;
    final esHoy = dia == hoy;
    final colorNombre = on ? TokensNs.blanco.withValues(alpha: 0.8) : (esHoy ? ns.prim : ns.mute);
    final colorNumero = on ? TokensNs.blanco : (esHoy ? ns.prim : ns.ink);
    // Uno, dos o tres puntitos: alcanza para ver de un vistazo qué día está cargado.
    final puntos = turnos > 4 ? 3 : (turnos > 1 ? 2 : turnos);
    final clave = '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
    return PresionNs(
      key: ValueKey('dia-$clave'),
      onTap: () => onTap(dia),
      etiqueta: '${_dias[dia.weekday - 1]} ${dia.day}${turnos > 0 ? ', $turnos turno${turnos == 1 ? '' : 's'}' : ''}',
      child: AnimatedContainer(
        duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 160),
        curve: curvaNs,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
        decoration: BoxDecoration(color: on ? ns.prim : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Text(_diasCortos[dia.weekday - 1], style: estiloNs(12, peso: FontWeight.w600, color: colorNombre)),
            const SizedBox(height: 4),
            Text('${dia.day}', style: estiloNs(20, peso: FontWeight.w500, track: -0.03, color: colorNumero, tabular: true)),
            const SizedBox(height: 4),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < puntos; i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                      decoration: BoxDecoration(color: (on ? TokensNs.blanco : colorNumero).withValues(alpha: 0.7), shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las tres cifras de hoy: turnos, cuánto entró y cuántos esperan la seña.
class _ResumenHoy extends StatelessWidget {
  const _ResumenHoy({required this.turnos, required this.app});
  final List<TurnoAgenda> turnos;
  final ControladorAppNs? app;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final cuantos = turnos.where((t) => t.estado != EstadoTurno.cancelado && t.estado != EstadoTurno.noVino).length;
    final esperan = turnos.where((t) => t.estado == EstadoTurno.esperandoSena).length;
    Widget mini(String n, String etiqueta, {Color? fondo, Color? color, double tamanio = 28}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(color: fondo ?? ns.s, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(child: Text(n, style: tituloNs(tamanio, track: -0.05, color: color ?? ns.ink))),
                  ),
                ),
                const SizedBox(height: 6),
                Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(13, peso: FontWeight.w500, color: color ?? ns.mute)),
              ],
            ),
          ),
        );
    final datos = app?.datosDia;
    return Row(
      children: [
        mini('$cuantos', cuantos == 1 ? 'turno' : 'turnos'),
        const SizedBox(width: 8),
        if (datos == null)
          mini(plataNs(0), 'cobrado', tamanio: 22)
        else
          ValueListenableBuilder<DatosDiaNs>(
            valueListenable: datos,
            builder: (_, d, _) => mini(plataNs(d.vendidoCentavos), 'cobrado', tamanio: 22),
          ),
        const SizedBox(width: 8),
        mini('$esperan', esperan == 1 ? 'espera seña' : 'esperan seña', fondo: esperan > 0 ? ns.wbg : null, color: esperan > 0 ? ns.w : null),
      ],
    );
  }
}

/// Un turno en la línea del día: la hora y la duración a la izquierda, la tarjeta con quién viene, qué se hace y sus etiquetas.
class _FilaTurno extends StatelessWidget {
  const _FilaTurno({super.key, required this.t, required this.color, required this.onTap, this.profesional});
  final TurnoAgenda t;
  final Color color;
  final String? profesional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final hecho = t.estado == EstadoTurno.atendido || t.estado == EstadoTurno.noVino;
    final (estado, fondoEstado, colorEstado) = switch (t.estado) {
      EstadoTurno.esperandoSena => ('Esperando seña', ns.wbg, ns.w),
      EstadoTurno.confirmado => ('Confirmado', ns.ibg, ns.i),
      EstadoTurno.atendido => ('Atendido', ns.s2, ns.mute),
      EstadoTurno.noVino => ('No vino', ns.bbg, ns.b),
      EstadoTurno.cancelado => ('Cancelado', ns.s2, ns.mute),
    };
    final faltas = textoFaltas(t.faltas);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(horaNs(t.inicio), style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, tabular: true)),
                const SizedBox(height: 2),
                Text('${t.turno.duracionMinutos} min', style: estiloNs(12, peso: FontWeight.w500, color: ns.mute)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Opacity(
            opacity: hecho ? 0.6 : 1,
            child: PresionNs(
              onTap: onTap,
              etiqueta: '${horaNs(t.inicio)} ${t.turno.nombreCliente}',
              child: Container(
                decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 14,
                      bottom: 14,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.turno.nombreCliente, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w600, track: -0.02, color: ns.ink)),
                          const SizedBox(height: 2),
                          Text(
                            [t.turno.servicioNombre, ?profesional].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: estiloNs(14, color: ns.mute),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Etiqueta(estado, fondo: fondoEstado, color: colorEstado),
                              if (t.turno.origen == 'BOT') _Etiqueta('WhatsApp', fondo: ns.gbg, color: ns.g, icono: IconoNs.celular),
                              if (t.turno.senaCentavos > 0)
                                _Etiqueta('Seña ${plataNs(t.turno.senaCentavos)}', fondo: ns.s2, color: ns.mute)
                              else if (t.turno.senaPedidaCentavos > 0 && t.estado.abierto)
                                _Etiqueta('Seña ${plataNs(t.turno.senaPedidaCentavos)} sin pagar', fondo: ns.s2, color: ns.mute),
                              if (faltas != null) _Etiqueta(faltas[0].toUpperCase() + faltas.substring(1), fondo: ns.bbg, color: ns.b, icono: IconoNs.alerta),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, {required this.fondo, required this.color, this.icono});
  final String texto;
  final Color fondo;
  final Color color;
  final IconoNs? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[IconoNsWidget(icono!, tamanio: 12, color: color, grosor: 2.2), const SizedBox(width: 4)],
          Text(texto, style: estiloNs(12, peso: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Un hueco libre de media hora o más: con un toque se da un turno ahí.
class _FilaLibre extends StatelessWidget {
  const _FilaLibre({required this.desdeMin, required this.hastaMin, required this.onTap});
  final int desdeMin;
  final int hastaMin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(horaDeMinutos(desdeMin), style: estiloNs(15, peso: FontWeight.w600, color: ns.mute, tabular: true)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PresionNs(
            key: ValueKey('libre-${horaDeMinutos(desdeMin)}'),
            onTap: onTap,
            etiqueta: 'Dar un turno a las ${horaDeMinutos(desdeMin)}',
            child: CustomPaint(
              painter: _BordePunteado(ns.line),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Libre hasta las ${horaDeMinutos(hastaMin)}', style: estiloNs(14.5, peso: FontWeight.w500, color: ns.mute))),
                    Text('+ Turno', style: estiloNs(14.5, peso: FontWeight.w600, color: ns.i)),
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

class _BordePunteado extends CustomPainter {
  _BordePunteado(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final camino = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)).deflate(0.75));
    for (final m in camino.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), pintura);
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteado old) => old.color != color;
}

/// La línea roja de "Ahora" entre los turnos de hoy.
class _MarcaAhora extends StatelessWidget {
  const _MarcaAhora(this.ahora);
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Ahora · ${horaNs(ahora)}', style: estiloNs(12, peso: FontWeight.w700, color: TokensNs.globo)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 2, decoration: BoxDecoration(color: TokensNs.globo, borderRadius: BorderRadius.circular(2)))),
      ],
    );
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
