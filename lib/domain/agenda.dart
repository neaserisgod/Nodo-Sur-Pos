// Agenda de un negocio de servicios (`REGLAS-NEGOCIO.md` §21, etapa 4 de `docs/PLAN-SERVICIOS.md`): el horario de
// atención (uno solo, que usan la agenda y el bot), los horarios que se ofrecen para un turno, cuándo dos turnos se pisan
// y el enlace "Agregar a Google Calendar". Funciones puras: sin base ni pantalla.

import 'dart:convert';

/// Un tramo de atención de un día, en minutos desde la medianoche (9:00 = 540).
typedef Franja = ({int desde, int hasta});

/// Un turno ocupando la agenda.
typedef Ocupado = ({DateTime inicio, DateTime fin});

/// En qué anda un turno. Las claves se guardan en la base (`turnos.estado`): no se renombran nunca.
enum EstadoTurno {
  /// Pidió turno por WhatsApp y falta la seña: ya ocupa el horario hasta que pague o venza (§21).
  esperandoSena('esperando_sena', 'Esperando seña'),
  confirmado('confirmado', 'Confirmado'),
  llego('llego', 'Llegó'),
  cobrado('cobrado', 'Cobrado'),
  noVino('no_vino', 'No vino'),
  cancelado('cancelado', 'Cancelado');

  const EstadoTurno(this.clave, this.nombre);

  final String clave;
  final String nombre;

  /// Si el horario queda tomado: lo cancelado y lo que no vino lo liberan.
  bool get ocupaHorario => this != cancelado && this != noVino;

  /// Una clave desconocida (de una versión más nueva) se lee como confirmado: el turno sigue ocupando su lugar.
  static EstadoTurno desdeClave(String? clave) {
    for (final e in values) {
      if (e.clave == clave) return e;
    }
    return confirmado;
  }
}

/// El horario de atención por día de la semana (`DateTime.monday` = 1 … `DateTime.sunday` = 7). Un día sin franjas está
/// cerrado.
class HorarioAtencion {
  const HorarioAtencion(this._porDia);

  final Map<int, List<Franja>> _porDia;

  /// Con lo que arranca un negocio (§21: valores por defecto, se cambian en Configuración).
  static const porDefecto = HorarioAtencion({
    DateTime.monday: [(desde: 540, hasta: 1140)],
    DateTime.tuesday: [(desde: 540, hasta: 1140)],
    DateTime.wednesday: [(desde: 540, hasta: 1140)],
    DateTime.thursday: [(desde: 540, hasta: 1140)],
    DateTime.friday: [(desde: 540, hasta: 1140)],
    DateTime.saturday: [(desde: 540, hasta: 1140)],
  });

  List<Franja> franjasDe(int diaDeLaSemana) => _porDia[diaDeLaSemana] ?? const [];

  String aJson() => jsonEncode({
        for (final MapEntry(key: dia, value: franjas) in _porDia.entries) '$dia': [for (final f in franjas) [f.desde, f.hasta]],
      });

  /// Lo guardado en la configuración. Null, vacío o roto es [porDefecto]: la agenda nunca se queda sin horarios.
  factory HorarioAtencion.desdeJson(String? json) {
    if (json == null || json.trim().isEmpty) return porDefecto;
    try {
      final mapa = jsonDecode(json) as Map<String, dynamic>;
      return HorarioAtencion({
        for (final MapEntry(key: dia, value: franjas) in mapa.entries)
          int.parse(dia): [for (final f in franjas as List) (desde: (f as List)[0] as int, hasta: f[1] as int)],
      });
    } catch (_) {
      return porDefecto;
    }
  }
}

DateTime _alMinuto(DateTime dia, int minutos) => DateTime(dia.year, dia.month, dia.day).add(Duration(minutes: minutos));

/// Dos turnos se pisan si se cruzan: uno que termina justo cuando empieza el otro no se pisa.
bool seSuperponen(Ocupado a, Ocupado b) => a.inicio.isBefore(b.fin) && b.inicio.isBefore(a.fin);

/// Las horas en que puede empezar un turno de [duracionMinutos] el [dia]: cada [intervaloMinutos] desde que abre cada
/// franja, que terminen antes del cierre, que no pisen nada de [ocupados] y, si se pasa [ahora], que no hayan pasado.
List<DateTime> horariosLibres({
  required HorarioAtencion horario,
  required DateTime dia,
  required int duracionMinutos,
  required int intervaloMinutos,
  required List<Ocupado> ocupados,
  DateTime? ahora,
}) {
  if (intervaloMinutos <= 0 || duracionMinutos <= 0) return const [];
  final libres = <DateTime>[];
  for (final f in horario.franjasDe(dia.weekday)) {
    for (var m = f.desde; m + duracionMinutos <= f.hasta; m += intervaloMinutos) {
      final inicio = _alMinuto(dia, m);
      if (ahora != null && inicio.isBefore(ahora)) continue;
      final candidato = (inicio: inicio, fin: inicio.add(Duration(minutes: duracionMinutos)));
      if (ocupados.any((o) => seSuperponen(o, candidato))) continue;
      libres.add(inicio);
    }
  }
  return libres;
}

String _dosCifras(int n) => n.toString().padLeft(2, '0');
String _fechaCalendario(DateTime d) =>
    '${d.year}${_dosCifras(d.month)}${_dosCifras(d.day)}T${_dosCifras(d.hour)}${_dosCifras(d.minute)}${_dosCifras(d.second)}';

/// "Agregar a Google Calendar" sin pedirle permisos a Google (§21): abre el calendario con el evento cargado y la persona
/// toca Guardar. La hora va como hora local de Argentina.
String urlGoogleCalendar({required String titulo, required DateTime inicio, required DateTime fin, String? detalle}) => Uri.https(
      'calendar.google.com',
      '/calendar/render',
      {
        'action': 'TEMPLATE',
        'text': titulo,
        'dates': '${_fechaCalendario(inicio)}/${_fechaCalendario(fin)}',
        'ctz': 'America/Argentina/Buenos_Aires',
        'details': ?detalle,
      },
    ).toString();
