// El tablero de arriba de la Agenda (El dueño, 2026-10-13: "una especie de dashboard orientado a los servicios"; eligió las
// tres tarjetas y "Compartir huecos"):
//
//  * Ahora: el próximo turno (o el que está pasando) y cuántos turnos y huecos libres quedan hoy.
//  * Plata de hoy: lo cobrado (lo pone la pantalla, sale del tablero del día) y lo que falta cobrar de los turnos de hoy.
//  * Para atender: señas que no llegaron, insumos por acabarse y quien viene hoy y ya faltó otras veces.
//
// "Compartir huecos" arma un texto con los horarios libres de los próximos días para los estados de WhatsApp o Instagram: le
// llena la agenda al negocio con lo que hoy queda vacío.
//
// Funciones puras: la base las alimenta desde `data/repositorio_turnos.dart` (`tableroAgenda`).

/// Lo que el tablero necesita de un turno de hoy.
class TurnoDelTablero {
  const TurnoDelTablero({
    required this.inicio,
    required this.duracionMin,
    required this.cliente,
    required this.servicio,
    this.ocupa = true,
    this.atendido = false,
    this.esperaSena = false,
    this.precioCentavos = 0,
    this.senaCentavos = 0,
    this.faltas = 0,
  });

  final DateTime inicio;
  final int duracionMin;
  final String cliente;
  final String servicio;

  /// Ocupa el horario (no está cancelado ni es un "no vino").
  final bool ocupa;

  /// Ya se cobró.
  final bool atendido;
  final bool esperaSena;

  /// El precio de hoy del servicio y la seña ya cobrada.
  final int precioCentavos;
  final int senaCentavos;

  /// Cuántas veces no vino antes este cliente.
  final int faltas;

  DateTime get fin => inicio.add(Duration(minutes: duracionMin));
}

/// El turno que sigue: el que está pasando, o si no el próximo en empezar. Null si no queda ninguno hoy.
({TurnoDelTablero turno, bool enCurso})? proximoTurno(List<TurnoDelTablero> turnos, DateTime ahora) {
  final vigentes = [for (final t in turnos) if (t.ocupa && !t.atendido && t.fin.isAfter(ahora)) t]
    ..sort((a, b) => a.inicio.compareTo(b.inicio));
  if (vigentes.isEmpty) return null;
  final t = vigentes.first;
  return (turno: t, enCurso: !t.inicio.isAfter(ahora));
}

/// "en 20 min", "en 1 h 15 min" o "ahora".
String textoFaltaPara(DateTime inicio, DateTime ahora) {
  final min = inicio.difference(ahora).inMinutes;
  if (min <= 0) return 'ahora';
  if (min < 60) return 'en $min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? 'en $h h' : 'en $h h $m min';
}

/// Lo que falta cobrar de los turnos de hoy que siguen en pie: el precio de hoy menos la seña ya cobrada (nunca negativo).
int porCobrarCentavos(List<TurnoDelTablero> turnos) {
  var total = 0;
  for (final t in turnos) {
    if (!t.ocupa || t.atendido) continue;
    final resto = t.precioCentavos - t.senaCentavos;
    if (resto > 0) total += resto;
  }
  return total;
}

/// Turnos de hoy que siguen en pie (sin cobrar todavía): los que el tablero cuenta como "faltan".
int turnosQueFaltan(List<TurnoDelTablero> turnos) => turnos.where((t) => t.ocupa && !t.atendido).length;

/// Quienes vienen hoy, todavía no vinieron y ya faltaron antes: para confirmarles el turno.
List<TurnoDelTablero> conFaltasPrevias(List<TurnoDelTablero> turnos, DateTime ahora) => [
      for (final t in turnos)
        if (t.ocupa && !t.atendido && t.faltas > 0 && t.fin.isAfter(ahora)) t,
    ];

/// De los horarios libres de un día (los inicios posibles, de a [pasoMin]), el comienzo de cada tramo seguido: "10:00, 10:15,
/// 10:30, 15:00" → [10:00, 15:00]. Así se ofrecen huecos, no cada cuarto de hora.
List<DateTime> comienzosDeHuecos(List<DateTime> libres, {required int pasoMin}) {
  final ordenados = [...libres]..sort();
  final comienzos = <DateTime>[];
  DateTime? anterior;
  for (final h in ordenados) {
    if (anterior == null || h.difference(anterior).inMinutes > pasoMin) comienzos.add(h);
    anterior = h;
  }
  return comienzos;
}

/// El emoji de cada rubro de servicios para el texto de los huecos.
String emojiDeRubro(String rubro) => switch (rubro) {
      'barberia' => '💈',
      'unas' => '💅',
      'peluqueria' => '💇',
      'estetica' => '🌸',
      _ => '📅',
    };

const _diasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

String _hora(DateTime d) => d.minute == 0 ? '${d.hour}' : '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// El texto para compartir: "¡Me quedan lugares! 💈\nHoy: 15, 17:30\nMañana: 10\n…". Hasta [maxPorDia] horarios por día.
/// Null si no hay ningún hueco (no se comparte una agenda llena).
String? textoCompartirHuecos({
  required String negocio,
  required String emoji,
  required List<({DateTime dia, List<DateTime> comienzos})> dias,
  required DateTime hoy,
  int maxPorDia = 4,
}) {
  final h = DateTime(hoy.year, hoy.month, hoy.day);
  final lineas = <String>[];
  for (final d in dias) {
    if (d.comienzos.isEmpty) continue;
    final dia = DateTime(d.dia.year, d.dia.month, d.dia.day);
    final dif = dia.difference(h).inDays;
    final nombre = dif == 0 ? 'Hoy' : dif == 1 ? 'Mañana' : '${_diasSemana[dia.weekday - 1][0].toUpperCase()}${_diasSemana[dia.weekday - 1].substring(1)} ${dia.day}';
    final horas = d.comienzos.take(maxPorDia).map(_hora).join(', ');
    lineas.add('$nombre: $horas h');
  }
  if (lineas.isEmpty) return null;
  final quien = negocio.trim().isEmpty ? '' : ' en ${negocio.trim()}';
  return '¡Me quedan lugares$quien! $emoji\n\n${lineas.join('\n')}\n\nEscribime por WhatsApp y te lo reservo 🙌';
}
