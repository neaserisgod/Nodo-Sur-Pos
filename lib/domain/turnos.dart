// Turnos de un negocio de servicios (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4). Funciones puras: sin base ni
// pantalla. Las usan la Agenda del celular y, por el sitio, el bot de WhatsApp: un horario que la Agenda da por libre es el
// mismo que el bot ofrece (Regla 3: una sola cuenta de "qué está libre").

import 'dinero.dart';

/// Estado de un turno. Las claves se guardan en la base y viajan por la sync: no se renombran nunca.
enum EstadoTurno {
  /// Lo pidió el bot y el servicio pide seña: ocupa el horario hasta que pague o venza (§21).
  esperandoSena('ESPERANDO_SENA'),
  confirmado('CONFIRMADO'),

  /// Se cobró: tiene su venta.
  atendido('ATENDIDO'),
  noVino('NO_VINO'),
  cancelado('CANCELADO');

  const EstadoTurno(this.clave);
  final String clave;

  static EstadoTurno desdeClave(String clave) =>
      EstadoTurno.values.firstWhere((e) => e.clave == clave, orElse: () => EstadoTurno.confirmado);

  /// Si ocupa su horario. Un turno que se canceló o al que no vinieron deja el lugar libre; uno atendido lo ocupó de verdad.
  bool get ocupa => this == esperandoSena || this == confirmado || this == atendido;

  /// Todavía se puede cobrar, cancelar o marcar "no vino".
  bool get abierto => this == esperandoSena || this == confirmado;

  String get etiqueta => switch (this) {
        esperandoSena => 'Esperando seña',
        confirmado => 'Confirmado',
        atendido => 'Atendido',
        noVino => 'No vino',
        cancelado => 'Cancelado',
      };
}

/// Un día de atención, en minutos desde la medianoche. Hasta es exclusivo: un turno puede terminar justo a esa hora.
typedef FranjaAtencion = ({int desdeMin, int hastaMin});

/// Los días como los escriben la app y el bot (`botdemo/config.json`, `domain/bot_whatsapp.dart`), lunes primero: el índice
/// + 1 es el `DateTime.weekday`.
const diasDeAtencion = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];

/// "09:30" → 570. Null si no es una hora válida.
int? minutosDeHora(String texto) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(texto.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 24 || min > 59 || (h == 24 && min > 0)) return null;
  return h * 60 + min;
}

/// 570 → "09:30".
String horaDeMinutos(int minutos) => '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';

/// El horario de atención del negocio: uno solo, en Configuración, que usan la Agenda y el bot (§21). Una franja por día
/// (igual que el bot); null = cerrado.
class HorarioAtencion {
  const HorarioAtencion(this.dias);

  /// Por `DateTime.weekday` (1 = lunes).
  final Map<int, FranjaAtencion?> dias;

  /// Lunes a viernes de 9 a 20, sábado de 9 a 13: el mismo arranque que la configuración del bot.
  static const porDefecto = HorarioAtencion({
    1: (desdeMin: 540, hastaMin: 1200),
    2: (desdeMin: 540, hastaMin: 1200),
    3: (desdeMin: 540, hastaMin: 1200),
    4: (desdeMin: 540, hastaMin: 1200),
    5: (desdeMin: 540, hastaMin: 1200),
    6: (desdeMin: 540, hastaMin: 780),
    7: null,
  });

  FranjaAtencion? delDia(DateTime dia) => dias[dia.weekday];

  /// Lee el JSON que se guarda (`{"lunes": {"desde": "09:00", "hasta": "18:00"}, "domingo": null}`), que es el mismo formato
  /// del bot. Un día que falta o no se entiende queda cerrado; un texto roto o vacío da [porDefecto].
  factory HorarioAtencion.desdeJson(Object? crudo) {
    if (crudo is! Map) return porDefecto;
    final dias = <int, FranjaAtencion?>{};
    for (var i = 0; i < diasDeAtencion.length; i++) {
      final f = crudo[diasDeAtencion[i]];
      FranjaAtencion? franja;
      if (f is Map) {
        final desde = minutosDeHora('${f['desde']}'), hasta = minutosDeHora('${f['hasta']}');
        if (desde != null && hasta != null && desde < hasta) franja = (desdeMin: desde, hastaMin: hasta);
      }
      dias[i + 1] = franja;
    }
    return HorarioAtencion(dias);
  }

  Map<String, Object?> toJson() => {
        for (var i = 0; i < diasDeAtencion.length; i++)
          diasDeAtencion[i]: switch (dias[i + 1]) {
            null => null,
            final f => {'desde': horaDeMinutos(f.desdeMin), 'hasta': horaDeMinutos(f.hastaMin)},
          },
      };
}

/// Un turno visto como un tramo de tiempo.
typedef TramoOcupado = ({DateTime inicio, int duracionMin});

DateTime finDe(TramoOcupado t) => t.inicio.add(Duration(minutes: t.duracionMin));

/// Si dos tramos se pisan. Uno que termina justo cuando empieza el otro no se pisa.
bool seSolapan(TramoOcupado a, TramoOcupado b) => a.inicio.isBefore(finDe(b)) && b.inicio.isBefore(finDe(a));

/// Los horarios en que puede empezar un turno de [duracionMin] el [dia]: dentro del horario de atención, cada [pasoMin] desde
/// que abre (15 por defecto, §21), que terminen antes de cerrar, que no pisen ninguno de [ocupados] y que no empiecen antes de
/// [ahora] más [anticipacionMin] (el bot no ofrece un turno para dentro de 5 minutos).
///
/// La app deja guardar un sobreturno a mano (avisa y deja); el bot solo ofrece lo que devuelve esto (§21).
List<DateTime> horariosLibres({
  required DateTime dia,
  required HorarioAtencion horario,
  required int duracionMin,
  required List<TramoOcupado> ocupados,
  int pasoMin = 15,
  DateTime? ahora,
  int anticipacionMin = 0,
}) {
  if (duracionMin <= 0) throw ArgumentError('La duración del turno tiene que ser mayor a cero');
  if (pasoMin <= 0) throw ArgumentError('El paso entre horarios tiene que ser mayor a cero');
  final franja = horario.delDia(dia);
  if (franja == null) return const [];
  final base = DateTime(dia.year, dia.month, dia.day);
  final desdeAhora = ahora?.add(Duration(minutes: anticipacionMin));
  final libres = <DateTime>[];
  for (var m = franja.desdeMin; m + duracionMin <= franja.hastaMin; m += pasoMin) {
    // Sumando minutos a la medianoche y no `Duration`: un día con cambio de hora no corre todos los turnos una hora.
    final inicio = DateTime(base.year, base.month, base.day, 0, m);
    if (desdeAhora != null && inicio.isBefore(desdeAhora)) continue;
    final tramo = (inicio: inicio, duracionMin: duracionMin);
    if (ocupados.any((o) => seSolapan(tramo, o))) continue;
    libres.add(inicio);
  }
  return libres;
}

/// Si el turno cae fuera del horario de atención (la app avisa y deja, como el sobreturno).
bool fueraDeHorario(TramoOcupado t, HorarioAtencion horario) {
  final franja = horario.delDia(t.inicio);
  if (franja == null) return true;
  final desde = t.inicio.hour * 60 + t.inicio.minute;
  return desde < franja.desdeMin || desde + t.duracionMin > franja.hastaMin;
}

/// Para qué servicios se pide seña (§21). Las claves se guardan en la base: no se renombran.
enum ModoSena {
  nunca('NUNCA'),

  /// Solo los servicios marcados "pide seña". El arranque.
  algunos('ALGUNOS'),
  todos('TODOS');

  const ModoSena(this.clave);
  final String clave;

  static ModoSena desdeClave(String? clave) =>
      ModoSena.values.firstWhere((m) => m.clave == clave, orElse: () => ModoSena.algunos);
}

/// Cómo pide seña el negocio. Por defecto: algunos servicios, 30 %, y si cancelan se pierde (§21).
class ConfigSena {
  const ConfigSena({this.modo = ModoSena.algunos, this.porcentaje = 30, this.montoFijoCentavos, this.devolverAlCancelar = false});

  final ModoSena modo;

  /// Porcentaje del precio del servicio. Se ignora si hay [montoFijoCentavos].
  final int porcentaje;

  /// Un monto fijo para todos los servicios que piden seña, en vez del porcentaje.
  final int? montoFijoCentavos;

  /// Si cancelan, la seña se devuelve (true) o se pierde (false, el arranque).
  final bool devolverAlCancelar;
}

/// La seña que pide un servicio de [precioCentavos]. Redondeada hacia arriba al peso entero (convención 5) y nunca más que el
/// precio (sería devolver plata por adelantado, igual que en un encargue).
int senaDeServicio({required int precioCentavos, required bool pideSena, required ConfigSena config}) {
  if (precioCentavos <= 0) return 0;
  final aplica = switch (config.modo) {
    ModoSena.nunca => false,
    ModoSena.algunos => pideSena,
    ModoSena.todos => true,
  };
  if (!aplica) return 0;
  final fijo = config.montoFijoCentavos;
  final sena = fijo != null && fijo > 0
      ? fijo
      : redondearFraccionHaciaArriba(precioCentavos * config.porcentaje.clamp(0, 100), 100, centavosPorPeso);
  return sena > precioCentavos ? precioCentavos : sena;
}

/// Lo que se le devuelve al cliente si se cancela un turno con [senaCobradaCentavos] de seña ya cobrada.
int senaADevolverAlCancelar({required int senaCobradaCentavos, required ConfigSena config}) =>
    config.devolverAlCancelar ? senaCobradaCentavos : 0;

/// "faltó 2 veces": cuántas veces no vino un cliente, para mostrarlo sin bloquear nada (§21).
String? textoFaltas(int veces) => switch (veces) {
      <= 0 => null,
      1 => 'faltó 1 vez',
      _ => 'faltó $veces veces',
    };

/// Una fila de la línea del día en la Agenda: un turno, un hueco libre o la marca de "Ahora".
sealed class FilaAgenda<T> {
  const FilaAgenda();
}

class FilaTurno<T> extends FilaAgenda<T> {
  const FilaTurno(this.turno);
  final T turno;
}

/// Libre de [desdeMin] a [hastaMin] (minutos desde la medianoche).
class FilaLibre<T> extends FilaAgenda<T> {
  const FilaLibre(this.desdeMin, this.hastaMin);
  final int desdeMin;
  final int hastaMin;
}

class FilaAhora<T> extends FilaAgenda<T> {
  const FilaAhora();
}

/// Arma la línea del día: los [turnos] (ya ordenados por hora, sin los cancelados) con los huecos libres de [huecoMinimoMin] o
/// más entre ellos dentro de [franja] (para dar un turno ahí con un toque), y la marca de [ahoraMin] si es hoy (null si no).
///
/// Un hueco que ya pasó no se muestra, y uno que está pasando arranca en el próximo cuarto de hora: un horario libre a las
/// 10 cuando son las 12 no sirve para nada. Un turno que no ocupa (no vino) no tapa el hueco. Con [conHuecos] en false (varios
/// profesionales a la vez: un hueco de uno no es de los otros), solo turnos y la marca.
List<FilaAgenda<T>> filasDeAgenda<T>({
  required List<T> turnos,
  required int Function(T) inicioMin,
  required int Function(T) duracionMin,
  required bool Function(T) ocupa,
  FranjaAtencion? franja,
  int? ahoraMin,
  bool conHuecos = true,
  int huecoMinimoMin = 30,
}) {
  final filas = <FilaAgenda<T>>[];
  var ahoraPuesta = ahoraMin == null;
  void marcarAhoraAntesDe(int min) {
    if (!ahoraPuesta && min > ahoraMin!) {
      filas.add(FilaAhora<T>());
      ahoraPuesta = true;
    }
  }

  void hueco(int desde, int hasta) {
    if (!conHuecos) return;
    if (ahoraMin != null) {
      if (hasta <= ahoraMin) return;
      if (desde < ahoraMin) desde = (ahoraMin + 14) ~/ 15 * 15;
    }
    if (hasta - desde < huecoMinimoMin) return;
    marcarAhoraAntesDe(desde);
    filas.add(FilaLibre<T>(desde, hasta));
  }

  var fin = franja?.desdeMin;
  for (final t in turnos) {
    final ini = inicioMin(t);
    if (fin != null) hueco(fin, ini);
    marcarAhoraAntesDe(ini);
    filas.add(FilaTurno<T>(t));
    if (fin != null && ocupa(t) && ini + duracionMin(t) > fin) fin = ini + duracionMin(t);
  }
  if (fin != null) hueco(fin, franja!.hastaMin);
  if (!ahoraPuesta) filas.add(FilaAhora<T>());
  return filas;
}
