// Turnos, agenda y seña (`REGLAS-NEGOCIO.md` §21, `docs/PLAN-SERVICIOS.md` etapa 4). Funciones puras: sin base ni pantalla.
//
// Un turno ocupa su horario desde que se anota hasta que se cobra; cancelado o "no vino" lo deja libre. Un profesional no
// puede tener dos que se pisan (El dueño, 2026-10-10): es lo que va a necesitar el bot para no dar dos veces el mismo horario.
// Las horas se comparan como `DateTime` locales del negocio: un turno no cruza la medianoche.

import 'dart:convert';

import 'dinero.dart';

/// Las claves se guardan en la base y viajan por la sync: no se renombran nunca.
enum EstadoTurno {
  /// Lo pidió un cliente (por WhatsApp) y falta que el negocio lo confirme.
  sinConfirmar('pendiente'),
  confirmado('confirmado'),
  llego('llego'),
  cobrado('cobrado'),
  noVino('novino'),
  cancelado('cancelado');

  const EstadoTurno(this.clave);

  final String clave;

  String get nombre => switch (this) {
        sinConfirmar => 'Sin confirmar',
        confirmado => 'Confirmado',
        llego => 'Llegó',
        cobrado => 'Cobrado',
        noVino => 'No vino',
        cancelado => 'Cancelado',
      };

  /// Cancelado y "no vino" dejan libre el horario.
  bool get ocupaHorario => this != noVino && this != cancelado;

  /// Ya no cambia más.
  bool get terminado => this == cobrado || this == noVino || this == cancelado;

  static EstadoTurno? desdeClave(String? clave) {
    for (final e in values) {
      if (e.clave == clave) return e;
    }
    return null;
  }
}

/// De un estado a otro se va siempre para adelante: sin confirmar → confirmado → llegó → cobrado, o a "no vino" / cancelado
/// desde cualquiera que no haya terminado. Cobrar se puede sin pasar por "llegó" (llegó y se cobró en el momento).
bool puedePasar(EstadoTurno de, EstadoTurno a) {
  if (de.terminado || de == a) return false;
  const orden = [EstadoTurno.sinConfirmar, EstadoTurno.confirmado, EstadoTurno.llego, EstadoTurno.cobrado];
  if (a == EstadoTurno.noVino || a == EstadoTurno.cancelado) return true;
  return orden.indexOf(a) > orden.indexOf(de);
}

/// De dónde vino un turno. Claves de la base.
enum OrigenTurno {
  app('app'),
  whatsapp('whatsapp');

  const OrigenTurno(this.clave);
  final String clave;

  static OrigenTurno desdeClave(String? clave) => clave == whatsapp.clave ? whatsapp : app;
}

/// Lo que la agenda necesita de un turno para las cuentas.
class TurnoParaAgenda {
  const TurnoParaAgenda({
    required this.id,
    required this.profesionalId,
    required this.inicio,
    required this.duracionMinutos,
    required this.estado,
  });

  final int id;
  final int? profesionalId;
  final DateTime inicio;
  final int duracionMinutos;
  final EstadoTurno estado;

  DateTime get fin => inicio.add(Duration(minutes: duracionMinutos));
}

bool _sePisan(DateTime aDesde, DateTime aHasta, DateTime bDesde, DateTime bHasta) => aDesde.isBefore(bHasta) && bDesde.isBefore(aHasta);

/// El turno con que chocaría uno nuevo (o uno que se mueve, [excepto] su propio id), o null si el horario está libre. Con
/// [variosProfesionales] solo cuentan los del mismo profesional; sin, la agenda es una sola. Pegados no se pisan.
TurnoParaAgenda? conQuienChoca({
  required DateTime inicio,
  required int duracionMinutos,
  required int? profesionalId,
  required List<TurnoParaAgenda> otros,
  required bool variosProfesionales,
  int? excepto,
}) {
  final fin = inicio.add(Duration(minutes: duracionMinutos));
  for (final t in otros) {
    if (t.id == excepto || !t.estado.ocupaHorario) continue;
    if (variosProfesionales && t.profesionalId != profesionalId) continue;
    if (_sePisan(inicio, fin, t.inicio, t.fin)) return t;
  }
  return null;
}

/// Una franja de atención de un día, en minutos desde la medianoche (9:00 = 540).
class FranjaHoraria {
  const FranjaHoraria({required this.desdeMinutos, required this.hastaMinutos});

  final int desdeMinutos;
  final int hastaMinutos;

  void validar() {
    if (desdeMinutos < 0 || hastaMinutos > 24 * 60 || desdeMinutos >= hastaMinutos) {
      throw ArgumentError('El horario tiene que empezar antes de terminar');
    }
  }

  @override
  bool operator ==(Object other) => other is FranjaHoraria && other.desdeMinutos == desdeMinutos && other.hastaMinutos == hastaMinutos;

  @override
  int get hashCode => Object.hash(desdeMinutos, hastaMinutos);
}

/// El horario de atención: una franja por día de la semana (El dueño, 2026-10-10), o cerrado. [dias] va de lunes (0) a
/// domingo (6).
class HorarioSemana {
  const HorarioSemana(this.dias);

  final List<FranjaHoraria?> dias;

  /// Lunes a viernes de 9 a 20, sábado de 9 a 14, domingo cerrado.
  static const porDefecto = HorarioSemana([
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200),
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200),
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200),
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200),
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 1200),
    FranjaHoraria(desdeMinutos: 540, hastaMinutos: 840),
    null,
  ]);

  /// La franja del día de [fecha], o null si ese día está cerrado.
  FranjaHoraria? franjaDe(DateTime fecha) => dias[fecha.weekday - 1];

  /// Copia con [diaDeLaSemana] (`DateTime.monday`…`DateTime.sunday`) en [franja] (null = cerrado).
  HorarioSemana conDia(int diaDeLaSemana, FranjaHoraria? franja) {
    franja?.validar();
    return HorarioSemana([for (var k = 0; k < 7; k++) k == diaDeLaSemana - 1 ? franja : dias[k]]);
  }

  /// Como se guarda en la configuración: `[[540,1200], …, null]`.
  String aTexto() => jsonEncode([for (final d in dias) d == null ? null : [d.desdeMinutos, d.hastaMinutos]]);

  /// Un texto vacío o que no se entiende es el horario de fábrica: la agenda nunca se rompe por esto.
  static HorarioSemana desdeTexto(String? texto) {
    if (texto == null || texto.isEmpty) return porDefecto;
    try {
      final lista = jsonDecode(texto) as List;
      if (lista.length != 7) return porDefecto;
      final dias = <FranjaHoraria?>[];
      for (final d in lista) {
        if (d == null) {
          dias.add(null);
        } else {
          final par = d as List;
          final f = FranjaHoraria(desdeMinutos: par[0] as int, hastaMinutos: par[1] as int)..validar();
          dias.add(f);
        }
      }
      return HorarioSemana(dias);
    } catch (_) {
      return porDefecto;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! HorarioSemana) return false;
    for (var k = 0; k < 7; k++) {
      if (other.dias[k] != dias[k]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(dias);
}

DateTime _alMinuto(DateTime dia, int minutos) => DateTime(dia.year, dia.month, dia.day).add(Duration(minutes: minutos));

/// El turno entero entra en el horario de su día. Uno fuera de horario se puede anotar igual (se avisa, Regla 21).
bool dentroDeHorario(HorarioSemana horario, {required DateTime inicio, required int duracionMinutos}) {
  final franja = horario.franjaDe(inicio);
  if (franja == null) return false;
  final fin = inicio.add(Duration(minutes: duracionMinutos));
  return !inicio.isBefore(_alMinuto(inicio, franja.desdeMinutos)) && !fin.isAfter(_alMinuto(inicio, franja.hastaMinutos));
}

/// Los huecos libres de [dia] dentro de su franja, de al menos [minimoMinutos], con [turnos] de UNA agenda (un profesional,
/// o el negocio si no hay varios). Los que no ocupan horario no tapan nada.
List<({DateTime desde, DateTime hasta})> huecosLibres({
  required DateTime dia,
  required HorarioSemana horario,
  required List<TurnoParaAgenda> turnos,
  int minimoMinutos = 30,
}) {
  final franja = horario.franjaDe(dia);
  if (franja == null) return const [];
  final apertura = _alMinuto(dia, franja.desdeMinutos);
  final cierre = _alMinuto(dia, franja.hastaMinutos);
  final ocupados = [for (final t in turnos) if (t.estado.ocupaHorario) t]..sort((a, b) => a.inicio.compareTo(b.inicio));
  final huecos = <({DateTime desde, DateTime hasta})>[];
  var cursor = apertura;
  void agregar(DateTime hasta) {
    if (hasta.difference(cursor).inMinutes >= minimoMinutos) huecos.add((desde: cursor, hasta: hasta));
  }

  for (final t in ocupados) {
    if (!t.fin.isAfter(cursor)) continue;
    agregar(t.inicio.isBefore(cierre) ? t.inicio : cierre);
    if (t.fin.isAfter(cursor)) cursor = t.fin;
  }
  if (cursor.isBefore(cierre)) agregar(cierre);
  return huecos;
}

/// Si el negocio pide seña: nunca, en algunos servicios (se marca en cada uno) o en todos. Claves de la base.
enum ModoSena {
  nunca('no'),
  algunos('algunos'),
  todos('todos');

  const ModoSena(this.clave);
  final String clave;
}

/// Qué pasa con la seña si el cliente no viene.
enum SiNoViene { pierde, devuelve }

/// La seña que pide el negocio (Regla 21).
class ConfigSena {
  const ConfigSena({required this.modo, required this.esPorcentaje, required this.valor, required this.siNoViene});

  final ModoSena modo;
  final bool esPorcentaje;

  /// Puntos básicos si [esPorcentaje] (30 % = 3000), centavos si es un monto fijo.
  final int valor;
  final SiNoViene siNoViene;

  /// De fábrica (El dueño, 2026-10-09): algunos servicios, 30 %, si no viene se pierde.
  static const porDefecto = ConfigSena(modo: ModoSena.algunos, esPorcentaje: true, valor: 3000, siNoViene: SiNoViene.pierde);

  String aTexto() => jsonEncode({'modo': modo.clave, 'tipo': esPorcentaje ? '%' : r'$', 'valor': valor, 'noVino': siNoViene.name});

  static ConfigSena desdeTexto(String? texto) {
    if (texto == null || texto.isEmpty) return porDefecto;
    try {
      final j = jsonDecode(texto) as Map;
      final modo = ModoSena.values.firstWhere((m) => m.clave == j['modo']);
      final valor = j['valor'] as int;
      if (valor < 0) return porDefecto;
      return ConfigSena(
        modo: modo,
        esPorcentaje: j['tipo'] != r'$',
        valor: valor,
        siNoViene: j['noVino'] == SiNoViene.devuelve.name ? SiNoViene.devuelve : SiNoViene.pierde,
      );
    } catch (_) {
      return porDefecto;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ConfigSena && other.modo == modo && other.esPorcentaje == esPorcentaje && other.valor == valor && other.siNoViene == siNoViene;

  @override
  int get hashCode => Object.hash(modo, esPorcentaje, valor, siNoViene);
}

/// La seña que corresponde a un servicio de [precioCentavos]: 0 si no se pide. Un porcentaje redondea hacia arriba a la
/// centena (como el precio sugerido, Regla 14); un monto fijo nunca pasa del precio.
int senaSugerida({required int precioCentavos, required ConfigSena config, required bool servicioPideSena}) {
  if (config.modo == ModoSena.nunca || (config.modo == ModoSena.algunos && !servicioPideSena)) return 0;
  if (precioCentavos <= 0) return 0;
  if (!config.esPorcentaje) return config.valor < precioCentavos ? config.valor : precioCentavos;
  final sena = redondearFraccionHaciaArriba(precioCentavos * config.valor, 10000, 100 * centavosPorPeso);
  return sena < precioCentavos ? sena : precioCentavos;
}

/// Cuánto de la seña vuelve al cliente cuando el turno termina sin cobrarse: al cancelar, toda (avisó, El dueño
/// 2026-10-10); si no vino, según la configuración.
int senaADevolver({required int senaCentavos, required EstadoTurno estadoFinal, required SiNoViene siNoViene}) {
  if (senaCentavos <= 0) return 0;
  return switch (estadoFinal) {
    EstadoTurno.cancelado => senaCentavos,
    EstadoTurno.noVino => siNoViene == SiNoViene.devuelve ? senaCentavos : 0,
    _ => 0,
  };
}
