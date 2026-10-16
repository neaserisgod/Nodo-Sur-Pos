// Asistente con IA de Nodo Sur Servicios (El dueño, 2026-10-16: "responde y actúa"). Se le pregunta en palabras ("¿qué huecos
// tengo mañana?", "dale un turno a Juana el viernes a las 10 para corte") y contesta con los datos del negocio; si hace falta
// hacer algo, PROPONE acciones que la persona confirma una por una. La IA nunca escribe en la base: lo que devuelve se valida
// acá contra los datos que se le mandaron (un id que no existe, una hora pasada o un servicio inventado se descartan) y el
// equipo lo vuelve a validar contra la base justo antes de hacerlo (`data/repositorio_asistente_ia.dart`).
//
// Privacidad: van nombres de clientas (sin eso no se puede mover ni cancelar "el turno de Juana"), nunca teléfonos.
//
// Lógica pura: sin Flutter, sin base, sin red.

import 'dinero.dart' show formatearARS;
import 'turnos.dart';

/// Un servicio que se ofrece, tal como lo ve la IA.
class ServicioIa {
  const ServicioIa({required this.id, required this.nombre, required this.precioCentavos, required this.duracionMin});
  final int id;
  final String nombre;
  final int precioCentavos;

  /// 0 = sin duración cargada: no se puede dar turno con él.
  final int duracionMin;
}

/// Un turno de la agenda, tal como lo ve la IA.
class TurnoIa {
  const TurnoIa({
    required this.id,
    required this.inicio,
    required this.duracionMin,
    required this.servicio,
    required this.cliente,
    required this.estado,
    this.senaCentavos = 0,
  });
  final int id;
  final DateTime inicio;
  final int duracionMin;
  final String servicio;
  final String cliente;
  final EstadoTurno estado;

  /// La seña que ya dejó (en la caja o por entrar).
  final int senaCentavos;
}

/// Lo cobrado en un período: cuánto y en cuántos cobros.
typedef CobrosIa = ({int centavos, int cobros});

/// Todo lo que la IA sabe del negocio para contestar. Lo arma `datosParaAsistenteIa`.
class DatosIa {
  const DatosIa({
    required this.negocio,
    required this.ahora,
    required this.horario,
    required this.servicios,
    required this.turnos,
    required this.libres,
    required this.cajaAbierta,
    required this.hoy,
    required this.mes,
    required this.mesAnterior,
    this.serviciosDelMes = const {},
    this.pasoMin = 15,
  });

  final String negocio;
  final DateTime ahora;
  final HorarioAtencion horario;
  final List<ServicioIa> servicios;

  /// Los de la semana pasada a dos semanas adelante, sin los cancelados.
  final List<TurnoIa> turnos;

  /// Por día (a las 0 h), los horarios en que puede empezar el servicio más corto.
  final Map<DateTime, List<DateTime>> libres;
  final bool cajaAbierta;
  final CobrosIa hoy;
  final CobrosIa mes;
  final CobrosIa mesAnterior;

  /// Cuántas veces se cobró cada servicio este mes.
  final Map<String, int> serviciosDelMes;

  /// Cada cuánto arrancan los turnos: con esto los horarios libres se juntan en tramos.
  final int pasoMin;
}

/// Una pantalla a la que la IA puede mandar.
enum PantallaIa {
  agenda('agenda', 'Ir a la agenda'),
  cobrar('cobrar', 'Ir a cobrar'),
  caja('caja', 'Ir a la caja');

  const PantallaIa(this.clave, this.boton);
  final String clave;
  final String boton;
}

/// Lo que la IA propone. Nada se hace sin que la persona lo confirme.
sealed class AccionIa {
  const AccionIa();
}

class DarTurnoIa extends AccionIa {
  const DarTurnoIa({required this.servicio, required this.inicio, required this.cliente});
  final ServicioIa servicio;
  final DateTime inicio;
  final String cliente;
}

class MoverTurnoIa extends AccionIa {
  const MoverTurnoIa({required this.turno, required this.inicio});
  final TurnoIa turno;
  final DateTime inicio;
}

class CancelarTurnoIa extends AccionIa {
  const CancelarTurnoIa({required this.turno});
  final TurnoIa turno;
}

class GastoIa extends AccionIa {
  const GastoIa({required this.montoCentavos, required this.motivo, required this.porMercadoPago});
  final int montoCentavos;
  final String motivo;
  final bool porMercadoPago;
}

class IrAIa extends AccionIa {
  const IrAIa(this.pantalla);
  final PantallaIa pantalla;
}

class RespuestaIa {
  const RespuestaIa({required this.texto, this.acciones = const [], this.descartadas = 0});
  final String texto;
  final List<AccionIa> acciones;

  /// Cuántas acciones propuso la IA que no pasaron la validación (se avisa, no se muestran).
  final int descartadas;
}

/// Un gasto anotado por la IA no pasa de esto: un número desproporcionado es casi seguro un error de lectura.
const maximoGastoIaCentavos = 10000000 * 100;

/// Hasta cuántas preguntas anteriores viajan con la nueva (para entender "¿y el jueves?").
const maximoHistorialIa = 3;

const instruccionesAsistenteIa =
    'Sos el asistente de un negocio de servicios con turnos (peluquería, barbería, uñas, estética) en Argentina. Te paso los '
    'datos del negocio y una pregunta de quien lo atiende. Contestá corto, claro y en español rioplatense, usando SOLO los datos '
    'que te paso: no inventes turnos, clientas, precios ni números. Si no está en los datos, decí que no lo sabés. '
    'Si la persona pide hacer algo, proponelo como acción (ella confirma antes de que se haga); nunca digas que ya lo hiciste. '
    'Acciones posibles: '
    '{"tipo":"dar_turno","servicio_id":N,"inicio":"AAAA-MM-DDTHH:MM","cliente":"nombre"} (solo en un horario libre de la '
    'lista y con un servicio de la lista; si falta el nombre, el servicio o la hora, preguntalo en vez de proponer); '
    '{"tipo":"mover_turno","turno_id":N,"inicio":"AAAA-MM-DDTHH:MM"}; {"tipo":"cancelar_turno","turno_id":N}; '
    '{"tipo":"gasto","pesos":N,"motivo":"texto","medio":"efectivo" o "mercadopago"} (solo con la caja abierta); '
    '{"tipo":"ir_a","pantalla":"agenda" o "cobrar" o "caja"}. '
    'Solo se pueden mover o cancelar turnos pendientes (confirmados o esperando seña) y que no hayan pasado. '
    'Respondé únicamente JSON: {"respuesta":"texto para la persona","acciones":[...]}. Sin acciones, "acciones":[].';

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _dos(int n) => n.toString().padLeft(2, '0');
String _fecha(DateTime d) => '${_dias[d.weekday - 1]} ${_dos(d.day)}/${_dos(d.month)}';
String _hora(DateTime d) => '${_dos(d.hour)}:${_dos(d.minute)}';
String _iso(DateTime d) => '${d.year}-${_dos(d.month)}-${_dos(d.day)}T${_hora(d)}';
String _plata(int centavos) => formatearARS(centavos);
String _cobros(CobrosIa c) => '${_plata(c.centavos)} en ${c.cobros} ${c.cobros == 1 ? 'cobro' : 'cobros'}';

/// "lun 12/10 09:30": como se muestra una fecha con hora en lo que la persona confirma.
String fechaHoraIa(DateTime d) => '${_fecha(d)} ${_hora(d)}';

const _nombreEstado = {
  EstadoTurno.esperandoSena: 'esperando seña',
  EstadoTurno.confirmado: 'confirmado',
  EstadoTurno.atendido: 'atendido',
  EstadoTurno.noVino: 'no vino',
  EstadoTurno.cancelado: 'cancelado',
};

/// Los horarios libres de un día como tramos: "09:00 a 11:30" es que se puede empezar en cualquiera de ese tramo. Un salto más
/// grande que [pasoMin] corta el tramo.
List<({DateTime desde, DateTime hasta})> tramosLibres(List<DateTime> libres, {required int pasoMin}) {
  final ordenados = [...libres]..sort();
  final tramos = <({DateTime desde, DateTime hasta})>[];
  for (final h in ordenados) {
    if (tramos.isNotEmpty && h.difference(tramos.last.hasta).inMinutes <= pasoMin) {
      tramos[tramos.length - 1] = (desde: tramos.last.desde, hasta: h);
    } else {
      tramos.add((desde: h, hasta: h));
    }
  }
  return tramos;
}

/// Los datos del negocio en texto, para el pedido a la IA.
String textoDatosIa(DatosIa d) {
  final b = StringBuffer()
    ..writeln('Negocio: ${d.negocio.trim().isEmpty ? 'sin nombre' : d.negocio.trim()}')
    ..writeln('Ahora: ${fechaHoraIa(d.ahora)} (${_iso(d.ahora)})')
    ..writeln('Caja: ${d.cajaAbierta ? 'abierta' : 'cerrada'}')
    ..writeln()
    ..writeln('Horario de atención:');
  for (var dia = 1; dia <= 7; dia++) {
    final f = d.horario.dias[dia];
    String m(int min) => '${_dos(min ~/ 60)}:${_dos(min % 60)}';
    b.writeln('- ${_dias[dia - 1]}: ${f == null ? 'cerrado' : '${m(f.desdeMin)} a ${m(f.hastaMin)}'}');
  }
  b
    ..writeln()
    ..writeln('Servicios (id: nombre, precio, duración):');
  for (final s in d.servicios) {
    b.writeln('- ${s.id}: ${s.nombre}, ${_plata(s.precioCentavos)}, ${s.duracionMin > 0 ? '${s.duracionMin} min' : 'sin duración'}');
  }
  b
    ..writeln()
    ..writeln('Turnos (id: fecha hora, servicio, clienta, estado):');
  if (d.turnos.isEmpty) b.writeln('- ninguno');
  for (final t in d.turnos) {
    final sena = t.senaCentavos > 0 ? ', dejó seña de ${_plata(t.senaCentavos)}' : '';
    b.writeln('- ${t.id}: ${fechaHoraIa(t.inicio)} (${t.duracionMin} min), ${t.servicio}, ${t.cliente}, ${_nombreEstado[t.estado]}$sena');
  }
  b
    ..writeln()
    ..writeln('Horarios libres para empezar un turno (según el servicio más corto; uno más largo tiene que entrar antes del próximo turno):');
  final dias = d.libres.keys.toList()..sort();
  for (final dia in dias) {
    final tramos = tramosLibres(d.libres[dia]!, pasoMin: d.pasoMin);
    b.writeln('- ${_fecha(dia)}: ${tramos.isEmpty ? 'sin lugar' : tramos.map((t) => t.desde == t.hasta ? _hora(t.desde) : '${_hora(t.desde)} a ${_hora(t.hasta)}').join(', ')}');
  }
  b
    ..writeln()
    ..writeln('Cobrado hoy: ${_cobros(d.hoy)}')
    ..writeln('Cobrado este mes: ${_cobros(d.mes)}')
    ..writeln('Cobrado el mes pasado (completo): ${_cobros(d.mesAnterior)}');
  if (d.serviciosDelMes.isNotEmpty) {
    final orden = d.serviciosDelMes.entries.toList()..sort((a, c) => c.value.compareTo(a.value));
    b.writeln('Servicios cobrados este mes: ${orden.map((e) => '${e.key} (${e.value})').join(', ')}');
  }
  return b.toString();
}

/// El pedido entero: los datos, lo que se habló antes y la pregunta.
String armarPedidoIa(String pregunta, DatosIa datos, {List<({String pregunta, String respuesta})> antes = const []}) {
  final b = StringBuffer(textoDatosIa(datos));
  final previas = antes.length > maximoHistorialIa ? antes.sublist(antes.length - maximoHistorialIa) : antes;
  if (previas.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Lo que se habló recién:');
    for (final p in previas) {
      b
        ..writeln('Persona: ${p.pregunta}')
        ..writeln('Vos: ${p.respuesta}');
    }
  }
  b
    ..writeln()
    ..writeln('Pregunta: ${pregunta.trim()}');
  return b.toString();
}

DateTime? _leerFecha(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})').firstMatch(v.trim());
  if (m == null) return null;
  final p = [for (var i = 1; i <= 5; i++) int.parse(m.group(i)!)];
  final d = DateTime(p[0], p[1], p[2], p[3], p[4]);
  // `DateTime` acomoda un 31/02 al 3/03: una fecha así es un error de la IA, no otra fecha.
  if (d.month != p[1] || d.day != p[2] || d.hour != p[3] || d.minute != p[4]) return null;
  return d;
}

int? _leerEntero(Object? v) => v is int ? v : (v is double && v == v.roundToDouble() ? v.toInt() : null);

/// Una acción de la IA, validada contra [d]. Null si no se puede hacer.
AccionIa? _leerAccion(Map<dynamic, dynamic> a, DatosIa d) {
  TurnoIa? pendiente(Object? id) {
    final n = _leerEntero(id);
    for (final t in d.turnos) {
      if (t.id == n) return t.estado.abierto && !t.inicio.isBefore(d.ahora) ? t : null;
    }
    return null;
  }

  DateTime? futura(Object? v) {
    final f = _leerFecha(v);
    return f == null || f.isBefore(d.ahora) ? null : f;
  }

  switch (a['tipo']) {
    case 'dar_turno':
      final id = _leerEntero(a['servicio_id']);
      final servicio = d.servicios.where((s) => s.id == id && s.duracionMin > 0).firstOrNull;
      final inicio = futura(a['inicio']);
      final cliente = a['cliente'] is String ? (a['cliente'] as String).trim() : '';
      if (servicio == null || inicio == null || cliente.isEmpty || cliente.length > 60) return null;
      return DarTurnoIa(servicio: servicio, inicio: inicio, cliente: cliente);
    case 'mover_turno':
      final turno = pendiente(a['turno_id']);
      final inicio = futura(a['inicio']);
      if (turno == null || inicio == null || inicio == turno.inicio) return null;
      return MoverTurnoIa(turno: turno, inicio: inicio);
    case 'cancelar_turno':
      final turno = pendiente(a['turno_id']);
      return turno == null ? null : CancelarTurnoIa(turno: turno);
    case 'gasto':
      final pesos = _leerEntero(a['pesos']);
      final motivo = a['motivo'] is String ? (a['motivo'] as String).trim() : '';
      if (!d.cajaAbierta || pesos == null || pesos <= 0 || pesos * 100 > maximoGastoIaCentavos || motivo.isEmpty) return null;
      return GastoIa(montoCentavos: pesos * 100, motivo: motivo.length > 80 ? motivo.substring(0, 80) : motivo, porMercadoPago: a['medio'] == 'mercadopago');
    case 'ir_a':
      final p = PantallaIa.values.where((p) => p.clave == a['pantalla']).firstOrNull;
      return p == null ? null : IrAIa(p);
  }
  return null;
}

/// Lo que contestó la IA, validado. Una respuesta sin texto se toma como que no contestó.
RespuestaIa leerRespuestaIa(Object? json, DatosIa datos) {
  final texto = json is Map && json['respuesta'] is String ? (json['respuesta'] as String).trim() : '';
  final crudas = json is Map && json['acciones'] is List ? json['acciones'] as List : const [];
  final acciones = <AccionIa>[];
  var descartadas = 0;
  for (final c in crudas) {
    final a = c is Map ? _leerAccion(c, datos) : null;
    if (a == null) {
      descartadas++;
    } else if (acciones.length < 5) {
      acciones.add(a);
    }
  }
  if (texto.isEmpty && acciones.isEmpty) return const RespuestaIa(texto: 'La IA no contestó nada. Probá preguntarlo de otra forma.');
  return RespuestaIa(texto: texto, acciones: acciones, descartadas: descartadas);
}

/// Cómo se le muestra a la persona lo que va a pasar, armado por la app (no por la IA): es lo que confirma.
String describirAccionIa(AccionIa a) => switch (a) {
      DarTurnoIa() => 'Turno para ${a.cliente}: ${a.servicio.nombre}, ${fechaHoraIa(a.inicio)}',
      MoverTurnoIa() => 'Mover el turno de ${a.turno.cliente} (${a.turno.servicio}) de ${fechaHoraIa(a.turno.inicio)} a ${fechaHoraIa(a.inicio)}',
      CancelarTurnoIa() => 'Cancelar el turno de ${a.turno.cliente}: ${a.turno.servicio}, ${fechaHoraIa(a.turno.inicio)}',
      GastoIa() => 'Gasto de ${_plata(a.montoCentavos)} por ${a.porMercadoPago ? 'Mercado Pago' : 'efectivo'}: ${a.motivo}',
      IrAIa() => a.pantalla.boton,
    };
