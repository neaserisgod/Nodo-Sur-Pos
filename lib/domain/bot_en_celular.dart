// El bot de WhatsApp adentro de Nodo Sur Servicios (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`): qué dice el bot de sí
// mismo (`estado.json`, lo escribe `botdemo/src/estado_app.js`) y cómo se le muestra a la dueña. Sin Flutter ni archivos.

/// Lo que el bot anotó en `estado.json`. Tiempos en milisegundos.
class EstadoBotLocal {
  const EstadoBotLocal({
    this.conectado = false,
    this.codigo,
    this.codigoPara,
    this.deslogueado = false,
    this.desde,
    this.ultimoMensaje,
    this.actualizado,
    this.motivo,
  });

  final bool conectado;

  /// El código de vinculación mientras WhatsApp no lo aceptó (se escribe en Dispositivos vinculados).
  final String? codigo;
  final String? codigoPara;

  /// WhatsApp cerró la sesión (la desvincularon desde el teléfono): hay que vincular de nuevo.
  final bool deslogueado;
  final DateTime? desde;
  final DateTime? ultimoMensaje;
  final DateTime? actualizado;
  final String? motivo;

  /// Tolera un archivo a medio escribir o de otra versión: lo que no entiende queda vacío.
  factory EstadoBotLocal.desdeJson(Object? j) {
    if (j is! Map) return const EstadoBotLocal();
    DateTime? fecha(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    String? texto(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    return EstadoBotLocal(
      conectado: j['conectado'] == true,
      codigo: texto(j['codigo']),
      codigoPara: texto(j['codigoPara']),
      deslogueado: j['deslogueado'] == true,
      desde: fecha(j['desde']),
      ultimoMensaje: fecha(j['ultimoMensaje']),
      actualizado: fecha(j['actualizado']),
      motivo: texto(j['motivo']),
    );
  }
}

enum FaseBot {
  /// Apagado a propósito (o nunca se encendió).
  apagado,

  /// Encendido, Node todavía no dijo nada o se está conectando.
  conectando,

  /// Falta vincular: hay un código para escribir en WhatsApp.
  vincular,

  /// Conectado y atendiendo.
  conectado,

  /// La sesión se cerró desde el teléfono: hay que vincular de nuevo.
  desvinculado,
}

FaseBot faseDelBot({required bool encendido, EstadoBotLocal? estado}) {
  if (!encendido) return FaseBot.apagado;
  if (estado == null) return FaseBot.conectando;
  if (estado.deslogueado) return FaseBot.desvinculado;
  if (estado.conectado) return FaseBot.conectado;
  if (estado.codigo != null) return FaseBot.vincular;
  return FaseBot.conectando;
}

/// "ABCD1234" → "ABCD-1234", como lo muestra WhatsApp.
String codigoLegible(String codigo) {
  final c = codigo.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  return c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
}

String _hace(Duration d) {
  if (d.inMinutes < 1) return 'recién';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
}

/// Una línea para la fila de Más y la cabecera de la pantalla del bot.
String textoDelBot(FaseBot fase, EstadoBotLocal? estado, DateTime ahora) => switch (fase) {
  FaseBot.apagado => 'Apagado',
  FaseBot.conectando => 'Conectando con WhatsApp…',
  FaseBot.vincular => 'Falta vincularlo con WhatsApp',
  FaseBot.desvinculado => 'Se desvinculó de WhatsApp: hay que vincularlo de nuevo',
  FaseBot.conectado => estado?.ultimoMensaje != null
      ? 'Conectado · último mensaje ${_hace(ahora.difference(estado!.ultimoMensaje!))}'
      : 'Conectado y atendiendo',
};

/// Si el token del bot hay que pedirlo de nuevo: no hay, o vence en menos de 30 días (dura un año; el bot también lo renueva).
bool tokenBotPorVencer({required int? venceSegundos, required DateTime ahora}) =>
    venceSegundos == null || venceSegundos * 1000 - ahora.millisecondsSinceEpoch < const Duration(days: 30).inMilliseconds;
