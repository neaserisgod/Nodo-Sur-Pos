// Bot de WhatsApp del negocio (El dueño, 2026-10-09; plan en `docs/PLAN-BOT.md`). Funciones puras: sin base, sin red, sin
// pantalla. El bot corre en un celular con Termux (`neaserisgod/botdemo`); el sitio guarda su configuración, el catálogo que la
// app publica y los pedidos que toma (`NodoSurPage`, `/api/bot/*`).

import 'pesables.dart';
import 'turnos.dart';

/// Un producto tal como lo ve el bot: lo justo para contestar "¿cuánto sale?" y "¿hay?". Nada de costos, proveedores ni stock
/// exacto (el catálogo sale de la base del negocio hacia un servidor; lo que no hace falta no viaja).
class ItemCatalogoBot {
  const ItemCatalogoBot({required this.gid, required this.nombre, required this.precioCentavos, required this.hay});
  final String gid;
  final String nombre;
  final int precioCentavos;
  final bool hay;

  Map<String, dynamic> toJson() => {'gid': gid, 'nombre': nombre, 'precioCentavos': precioCentavos, 'hay': hay};
}

/// Lo que hace falta de un producto para armar el catálogo del bot.
class ProductoParaBot {
  const ProductoParaBot({
    required this.globalId,
    required this.nombre,
    required this.activo,
    required this.esPesable,
    required this.esPromo,
    this.precioCentavos,
    this.precioPorKiloCentavos,
    this.stock = 0,
    this.stockGramos,
  });
  final String? globalId;
  final String nombre;
  final bool activo;
  final bool esPesable;
  final bool esPromo;
  final int? precioCentavos;
  final int? precioPorKiloCentavos;
  final int stock;
  final int? stockGramos;
}

/// Los productos que el bot puede ofrecer. Quedan afuera: los inactivos, los que no tienen identidad de sincronización (el
/// pedido vuelve por `global_id`), los que no tienen precio y las promos (su stock sale de sus artículos y no se venden desde el
/// celular, Regla 14). Un pesable va con su precio por kilo y lo dice en el nombre. "Hay" = stock mayor a cero (Regla 8: sin
/// stock no se vende), ordenado por nombre para que el catálogo sea el mismo si nada cambió.
List<ItemCatalogoBot> catalogoParaBot(Iterable<ProductoParaBot> productos) {
  final items = <ItemCatalogoBot>[];
  for (final p in productos) {
    final gid = p.globalId;
    if (!p.activo || p.esPromo || gid == null || gid.isEmpty) continue;
    final nombre = p.nombre.trim();
    if (nombre.isEmpty) continue;
    if (p.esPesable) {
      final precio = p.precioPorKiloCentavos;
      if (precio == null || precio <= 0) continue;
      items.add(ItemCatalogoBot(gid: gid, nombre: '$nombre (por kg)', precioCentavos: precio, hay: (p.stockGramos ?? 0) > 0));
    } else {
      final precio = p.precioCentavos;
      if (precio == null || precio <= 0) continue;
      items.add(ItemCatalogoBot(gid: gid, nombre: nombre, precioCentavos: precio, hay: p.stock > 0));
    }
  }
  items.sort((a, b) => a.nombre.compareTo(b.nombre) != 0 ? a.nombre.compareTo(b.nombre) : a.gid.compareTo(b.gid));
  return items;
}

// ─── Pedidos ────────────────────────────────────────────────────────────────────────────────────────────────────────────────

/// Una línea del pedido: [cantidad] (unidades, o kilos enteros de un pesable) o [gramos] (lo que se pesa: "1/4 de jamón" son
/// 250), nunca las dos.
class ItemPedidoBot {
  const ItemPedidoBot({this.gid, required this.nombre, this.cantidad, this.gramos, this.precioCentavos})
    : assert((cantidad == null) != (gramos == null), 'cantidad o gramos, uno solo');
  final String? gid;
  final String nombre;
  final int? cantidad;
  final int? gramos;

  /// El precio que le dijo el bot en ese momento: solo orienta (vale el del día que se entrega, Regla 4). Por kilo si se pesa.
  final int? precioCentavos;

  /// Lo que salía según el bot: por kilo × gramos por el helper de pesables (Regla 7), o precio × cantidad.
  int get subtotalOrientativoCentavos {
    final precio = precioCentavos;
    if (precio == null) return 0;
    final g = gramos;
    return g != null ? subtotalPesable(montoPorKiloCentavos: precio, gramos: g) : precio * cantidad!;
  }
}

/// La línea como se lee en el mostrador: "2 × Yerba" o "250 g de Jamón cocido" (sin el "(por kg)" con que el bot lo ofrece).
String textoLineaPedido(ItemPedidoBot x) {
  final g = x.gramos;
  if (g == null) return '${x.cantidad} × ${x.nombre}';
  return '${_gramos(g)} de ${x.nombre.replaceFirst(RegExp(r'\s*\(por kg\)\s*$', caseSensitive: false), '').trim()}';
}

enum EstadoPedidoBot { porConfirmar, aceptado, rechazado }

class PedidoBot {
  const PedidoBot({
    required this.id,
    required this.estado,
    required this.clienteNombre,
    required this.clienteTelefono,
    required this.items,
    this.nota,
    required this.creado,
    required this.actualizado,
  });
  final int id;
  final EstadoPedidoBot estado;
  final String clienteNombre;
  final String clienteTelefono;
  final List<ItemPedidoBot> items;
  final String? nota;
  final DateTime creado;

  /// Cursor del sitio (milisegundos): se pide "lo que cambió después de esto".
  final int actualizado;

  /// Lo que dijo el bot que salía todo (orientativo).
  int get totalOrientativoCentavos => items.fold(0, (s, x) => s + x.subtotalOrientativoCentavos);
}

EstadoPedidoBot? _estadoPedido(Object? e) => switch (e) {
  'por_confirmar' => EstadoPedidoBot.porConfirmar,
  'aceptado' => EstadoPedidoBot.aceptado,
  'rechazado' => EstadoPedidoBot.rechazado,
  _ => null,
};

/// Lo que devuelve `/api/bot/pedidos`, o null si no tiene la forma esperada (se descarta en vez de romper la pantalla).
PedidoBot? pedidoBotDesdeJson(Map<String, dynamic> j) {
  final estado = _estadoPedido(j['estado']);
  final cliente = j['cliente'];
  final items = j['items'];
  if (j['id'] is! int || estado == null || cliente is! Map || items is! List) return null;
  final nombre = cliente['nombre'], telefono = cliente['telefono'];
  if (nombre is! String || telefono is! String) return null;
  final lineas = <ItemPedidoBot>[];
  for (final x in items) {
    if (x is! Map || x['nombre'] is! String) return null;
    final cantidad = x['cantidad'], gramos = x['gramos'];
    // Una cosa o la otra: con las dos (o ninguna) no se sabe qué apartar.
    if ((cantidad == null) == (gramos == null)) return null;
    if (cantidad != null && cantidad is! int) return null;
    if (gramos != null && (gramos is! int || gramos <= 0)) return null;
    lineas.add(ItemPedidoBot(
      gid: x['gid'] as String?,
      nombre: x['nombre'] as String,
      cantidad: cantidad as int?,
      gramos: gramos as int?,
      precioCentavos: x['precioCentavos'] as int?,
    ));
  }
  return PedidoBot(
    id: j['id'] as int,
    estado: estado,
    clienteNombre: nombre,
    clienteTelefono: telefono,
    items: lineas,
    nota: j['nota'] as String?,
    creado: DateTime.fromMillisecondsSinceEpoch((j['creado'] as num?)?.toInt() ?? 0),
    actualizado: (j['actualizado'] as num?)?.toInt() ?? 0,
  );
}

/// El nombre del encargue que se crea al aceptar: se ve en Encargues y en el ticket que vino por WhatsApp.
String nombreEncargueDePedido(PedidoBot p) => '${p.clienteNombre.trim()} (WhatsApp)';

/// Lo que hace falta de un producto de la base para convertir un pedido del bot en un encargue.
class ProductoDelPedido {
  const ProductoDelPedido({
    required this.id,
    required this.globalId,
    required this.nombre,
    required this.esPesable,
    required this.activo,
    required this.stock,
    this.stockGramos,
  });
  final int id;
  final String? globalId;
  final String nombre;
  final bool esPesable;
  final bool activo;
  final int stock;
  final int? stockGramos;
}

/// Una línea a apartar: [cantidad] por unidad o [gramos] si se pesa (la forma de `ApartadoCompanion`).
typedef ApartadoDePedido = ({int productoId, int? cantidad, int? gramos});

/// Lo que se aparta al aceptar [pedido], o lo que falta. Todo o nada, como apartar (`repositorio_encargues.dart`): si falta
/// algo, [lineas] va vacía y [faltan] dice qué, en palabras del mostrador, para que quien acepta sepa qué contestarle al
/// cliente. Revisarlo antes de crear el encargue evita un rechazo a medias y nombra TODO lo que falta, no solo lo primero.
///
/// * El producto vuelve por su `global_id` (el que se publicó en el catálogo del bot): el id local cambia entre equipos.
/// * Un pesable el bot lo ofrece "por kg" con el precio por kilo: viene en gramos, o en kilos enteros como cantidad (el bot
///   antes de que el sitio aceptara gramos).
/// * Algo pedido en gramos que ya no se pesa no se convierte a unidades: no se sabe cuántas son.
/// * Sin stock no se aparta (Regla 8): el catálogo dice "hay" con lo de hace un rato, y en el medio se pudo vender.
({List<ApartadoDePedido> lineas, List<String> faltan}) apartadosDePedido(PedidoBot pedido, Iterable<ProductoDelPedido> productos) {
  final porGid = {for (final p in productos) if (p.globalId != null && p.globalId!.isNotEmpty) p.globalId!: p};
  final pedidoPorProducto = <int, int>{}; // id → unidades, o gramos si se pesa, en el orden en que se pidió
  final elegidos = <int, ProductoDelPedido>{};
  final faltan = <String>[];
  for (final item in pedido.items) {
    final p = item.gid == null ? null : porGid[item.gid];
    if (p == null || !p.activo) {
      faltan.add('${item.nombre}: ya no está en el catálogo');
      continue;
    }
    final g = item.gramos;
    if (g != null && !p.esPesable) {
      faltan.add('${p.nombre}: se pidió por peso y ya no se vende suelto');
      continue;
    }
    elegidos[p.id] = p;
    final pedido = p.esPesable ? (g ?? item.cantidad! * 1000) : item.cantidad!;
    pedidoPorProducto[p.id] = (pedidoPorProducto[p.id] ?? 0) + pedido;
  }
  final lineas = <ApartadoDePedido>[];
  for (final MapEntry(key: id, value: cantidad) in pedidoPorProducto.entries) {
    final p = elegidos[id]!;
    if (p.esPesable) {
      final gramos = cantidad, hay = p.stockGramos ?? 0;
      if (hay < gramos) {
        faltan.add('${p.nombre}: piden ${_gramos(gramos)}, ${hay <= 0 ? 'no queda' : 'quedan ${_gramos(hay)}'}');
      } else {
        lineas.add((productoId: id, cantidad: null, gramos: gramos));
      }
    } else if (p.stock < cantidad) {
      faltan.add('${p.nombre}: piden $cantidad, ${p.stock <= 0 ? 'no queda' : 'quedan ${p.stock}'}');
    } else {
      lineas.add((productoId: id, cantidad: cantidad, gramos: null));
    }
  }
  return faltan.isEmpty ? (lineas: lineas, faltan: const []) : (lineas: const [], faltan: faltan);
}

String _gramos(int g) => g < 1000 ? '$g g' : '${(g / 1000).toStringAsFixed(g % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} kg';

// ─── Estado y configuración ────────────────────────────────────────────────────────────────────────────────────────────────

class BotVinculado {
  const BotVinculado({required this.nombre, required this.ultimaSenal});
  final String nombre;
  final DateTime? ultimaSenal;
}

class EstadoBot {
  const EstadoBot({required this.tieneBot, this.puedeConfigurar = false, this.version = 0, this.bots = const []});
  final bool tieneBot;
  final bool puedeConfigurar;

  /// Versión de la configuración en el sitio (0 = nunca se guardó).
  final int version;
  final List<BotVinculado> bots;

  static const sinBot = EstadoBot(tieneBot: false);
}

EstadoBot estadoBotDesdeJson(Map<String, dynamic> j) {
  if (j['tieneBot'] != true) return EstadoBot.sinBot;
  return EstadoBot(
    tieneBot: true,
    puedeConfigurar: j['puedeConfigurar'] == true,
    version: (j['version'] as num?)?.toInt() ?? 0,
    bots: [
      for (final b in (j['bots'] as List? ?? const []))
        if (b is Map)
          BotVinculado(
            nombre: (b['nombre'] as String?) ?? 'Bot de WhatsApp',
            ultimaSenal: b['ultimaSenal'] is num ? DateTime.fromMillisecondsSinceEpoch((b['ultimaSenal'] as num).toInt() * 1000) : null,
          ),
    ],
  );
}

/// Cómo se ve el bot desde la app: el ping es cada hora, así que más de dos horas sin señal es que algo pasa (celular apagado,
/// sin internet, Termux cerrado).
enum SaludBot { sinBot, anda, sinSenal }

SaludBot saludDelBot(EstadoBot e, DateTime ahora) {
  final senales = e.bots.map((b) => b.ultimaSenal).whereType<DateTime>();
  if (senales.isEmpty) return SaludBot.sinBot;
  final ultima = senales.reduce((a, b) => a.isAfter(b) ? a : b);
  return ahora.difference(ultima) <= const Duration(hours: 2) ? SaludBot.anda : SaludBot.sinSenal;
}

/// Un celular argentino como lo escribe cualquiera ("2944 111111", "02944-111111", "+54 9 2944 111111") al formato de WhatsApp:
/// 549 + característica sin el 0 + número sin el 15. La misma regla que el bot (`botdemo/scripts/config-de-rubro.js`). Null si
/// no queda un número válido.
String? numeroWhatsApp(String texto) {
  var d = texto.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('549')) {
    // ya está
  } else if (d.startsWith('54')) {
    d = '549${d.substring(2)}';
  } else {
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length == 10) d = '549$d';
  }
  return RegExp(r'^549\d{10}$').hasMatch(d) ? d : null;
}

const diasBot = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];

/// Horario de un día: null = cerrado.
typedef FranjaBot = ({String desde, String hasta});

/// Lo que se configura del bot desde la app. El nombre del negocio y el rubro no se cargan acá: salen de la configuración de
/// Nodo Sur (Configuración › Tu negocio), así hay un solo lugar para cada dato (Regla 3).
class ConfigBotEditable {
  const ConfigBotEditable({
    required this.numeroBot,
    required this.numeroAvisos,
    required this.direccion,
    required this.horarios,
    required this.pausaMinutos,
  });
  final String numeroBot;
  final String numeroAvisos;
  final String direccion;
  final Map<String, FranjaBot?> horarios;
  final int pausaMinutos;

  static const porDefecto = ConfigBotEditable(
    numeroBot: '',
    numeroAvisos: '',
    direccion: '',
    horarios: {
      'lunes': (desde: '09:00', hasta: '20:00'),
      'martes': (desde: '09:00', hasta: '20:00'),
      'miercoles': (desde: '09:00', hasta: '20:00'),
      'jueves': (desde: '09:00', hasta: '20:00'),
      'viernes': (desde: '09:00', hasta: '20:00'),
      'sabado': (desde: '09:00', hasta: '13:00'),
      'domingo': null,
    },
    pausaMinutos: 60,
  );

  ConfigBotEditable copiar({String? numeroBot, String? numeroAvisos, String? direccion, Map<String, FranjaBot?>? horarios, int? pausaMinutos}) =>
      ConfigBotEditable(
        numeroBot: numeroBot ?? this.numeroBot,
        numeroAvisos: numeroAvisos ?? this.numeroAvisos,
        direccion: direccion ?? this.direccion,
        horarios: horarios ?? this.horarios,
        pausaMinutos: pausaMinutos ?? this.pausaMinutos,
      );
}

/// Lee lo que la app sabe editar de una configuración guardada (la que bajó del sitio). Lo que falta o no se entiende queda como
/// [ConfigBotEditable.porDefecto].
ConfigBotEditable configBotDesdeJson(Map<String, dynamic>? c) {
  if (c == null) return ConfigBotEditable.porDefecto;
  final base = ConfigBotEditable.porDefecto;
  final h = c['horarios'];
  final horarios = <String, FranjaBot?>{};
  for (final d in diasBot) {
    final x = h is Map ? h[d] : null;
    horarios[d] = h is Map && h.containsKey(d)
        ? (x is Map && x['desde'] is String && x['hasta'] is String ? (desde: x['desde'] as String, hasta: x['hasta'] as String) : null)
        : base.horarios[d];
  }
  final negocio = c['negocio'];
  return ConfigBotEditable(
    numeroBot: c['numero_actual'] is String ? c['numero_actual'] as String : '',
    numeroAvisos: c['numero_duena'] is String ? c['numero_duena'] as String : '',
    direccion: negocio is Map && negocio['direccion'] is String ? negocio['direccion'] as String : '',
    horarios: horarios,
    pausaMinutos: c['pausa_minutos'] is int ? c['pausa_minutos'] as int : base.pausaMinutos,
  );
}

final _hora = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Lo que está mal, en palabras del dueño; vacío si se puede guardar. Las mismas reglas que valida el bot al arrancar
/// (`botdemo/src/config.js`): si el bot la rechazara, seguiría con la anterior y el cambio no se vería nunca.
List<String> problemasConfigBot(ConfigBotEditable c, {required String nombreNegocio, required String? rubro}) {
  final malos = <String>[];
  if (rubro == null || rubro.isEmpty) malos.add('Elegí el rubro del negocio en Configuración › Tu negocio.');
  if (nombreNegocio.trim().isEmpty) malos.add('Falta el nombre del comercio: cargalo en Configuración › Tu negocio.');
  final bot = numeroWhatsApp(c.numeroBot), avisos = numeroWhatsApp(c.numeroAvisos);
  if (bot == null) malos.add('El número del bot no se entiende: escribilo como siempre, por ejemplo 2944 123456.');
  if (avisos == null) malos.add('El número para los avisos no se entiende: escribilo como siempre, por ejemplo 2944 123456.');
  if (bot != null && bot == avisos) malos.add('El número para los avisos tiene que ser otro que el del bot: WhatsApp no se escribe a sí mismo.');
  var abierto = false;
  for (final d in diasBot) {
    final f = c.horarios[d];
    if (f == null) continue;
    if (!_hora.hasMatch(f.desde) || !_hora.hasMatch(f.hasta)) {
      malos.add('El horario del $d va como 09:00.');
    } else if (f.desde.compareTo(f.hasta) >= 0) {
      malos.add('El $d cierra antes de abrir.');
    } else {
      abierto = true;
    }
  }
  if (!abierto) malos.add('Tiene que haber al menos un día abierto.');
  if (c.pausaMinutos < 5 || c.pausaMinutos > 24 * 60) malos.add('La pausa va de 5 minutos a 24 horas.');
  return malos;
}

/// La configuración que se guarda en el sitio y baja al bot: la misma forma que el `config.json` del bot, con los datos de
/// Nodo Sur (nombre y rubro) y lo que se cargó acá. Lo que el bot ya tenía y la app no edita (servicios, seña, textos, FAQ) se
/// conserva tal cual de [anterior].
Map<String, dynamic> configBotParaGuardar(
  ConfigBotEditable c, {
  required String nombreNegocio,
  required String rubro,
  Map<String, dynamic>? anterior,
}) {
  final previo = Map<String, dynamic>.from(anterior ?? const {});
  final negocio = Map<String, dynamic>.from((previo['negocio'] as Map?) ?? const {});
  return {
    ...previo,
    'negocio': {...negocio, 'nombre': nombreNegocio.trim(), 'rubro': rubro, 'direccion': c.direccion.trim()},
    // A quién le llega el latido de salud del bot: si no hay uno, el soporte de Nodo Sur.
    'numero_soporte': previo['numero_soporte'] ?? numeroSoporteNodoSur,
    'numero_actual': numeroWhatsApp(c.numeroBot),
    'numero_duena': numeroWhatsApp(c.numeroAvisos),
    'horarios': {for (final d in diasBot) d: c.horarios[d] == null ? null : {'desde': c.horarios[d]!.desde, 'hasta': c.horarios[d]!.hasta}},
    'pausa_minutos': c.pausaMinutos,
  };
}

/// Un servicio tal como lo ofrece el bot (negocios de servicios): sale de los datos del negocio, no de una configuración aparte
/// (El dueño, 2026-10-10: "no tiene que haber una sección específica para bot").
class ServicioParaBot {
  const ServicioParaBot({required this.gid, required this.nombre, required this.duracionMinutos, required this.precioCentavos, required this.senaCentavos});
  final String gid;
  final String nombre;
  final int duracionMinutos;
  final int precioCentavos;
  final int senaCentavos;
}

int _pesosHaciaArriba(int centavos) => (centavos + 99) ~/ 100;

/// La configuración del bot con los servicios, el horario de atención y la seña del negocio, encima de [anterior] (lo que ya
/// tenía: números, textos, pausa). El bot habla en pesos enteros y usa números chicos para su menú ("*1* — Semipermanente"):
/// cada servicio conserva el número que ya tenía (por su `gid`), así un turno o un menú abierto no cambia de servicio; uno nuevo
/// toma el siguiente.
///
/// La seña viaja solo si el negocio cargó a dónde se transfiere (alias y titular): sin eso el bot no puede pedirla y rechazaría
/// la configuración entera (`botdemo/src/config.js`). Sin servicios devuelve [anterior] tal cual (el bot necesita al menos uno).
///
/// [cobroConLink] (Nodo Sur Servicios, El dueño, 2026-10-10: "todo Mercado Pago"): la seña se cobra con el link de Mercado Pago que
/// crea Nodo Sur, con media hora para pagar; el alias pasa a ser el plan B (si el negocio todavía no conectó Mercado Pago), así que
/// la seña viaja aunque no haya alias.
Map<String, dynamic> configBotConServicios(
  Map<String, dynamic> anterior, {
  required List<ServicioParaBot> servicios,
  required HorarioAtencion horario,
  required int pasoMinutos,
  required String aliasSena,
  required String titularSena,
  bool cobroConLink = false,
}) {
  if (servicios.isEmpty) return anterior;
  final idsPrevios = <String, int>{};
  var maximo = 0;
  for (final x in (anterior['servicios'] is List ? anterior['servicios'] as List : const [])) {
    if (x is! Map || x['id'] is! int) continue;
    final id = x['id'] as int;
    if (id > maximo) maximo = id;
    if (x['catalogo_id'] is String && (x['catalogo_id'] as String).isNotEmpty) idsPrevios[x['catalogo_id'] as String] = id;
  }
  final conSena = cobroConLink || (aliasSena.trim().isNotEmpty && titularSena.trim().isNotEmpty);
  final lista = <Map<String, dynamic>>[];
  for (final s in servicios) {
    final id = idsPrevios[s.gid] ?? ++maximo;
    final precio = _pesosHaciaArriba(s.precioCentavos);
    final sena = conSena ? _pesosHaciaArriba(s.senaCentavos).clamp(0, precio) : 0;
    lista.add({'id': id, 'nombre': s.nombre, 'duracion_min': s.duracionMinutos, 'precio': precio, 'sena': sena, 'catalogo_id': s.gid});
  }
  final senasPrevias = anterior['senas'] is Map ? Map<String, dynamic>.from(anterior['senas'] as Map) : <String, dynamic>{};
  final turnosPrevios = anterior['turnos'] is Map ? Map<String, dynamic>.from(anterior['turnos'] as Map) : <String, dynamic>{};
  return {
    ...anterior,
    'servicios': lista,
    'horarios': horario.toJson(),
    'turnos': {...turnosPrevios, 'intervalo_slot_min': pasoMinutos},
    'senas': {
      ...senasPrevias,
      'habilitadas': conSena && lista.any((s) => (s['sena'] as int) > 0),
      'alias_mp': aliasSena.trim(),
      'titular': titularSena.trim(),
      'vencimiento_horas': cobroConLink ? 0.5 : (senasPrevias['vencimiento_horas'] is int ? senasPrevias['vencimiento_horas'] : 2),
      'cobro': cobroConLink ? 'mp' : 'alias',
    },
  };
}

/// El WhatsApp de contacto de Nodo Sur (horsepos.com): recibe solo el latido de salud de los bots.
const numeroSoporteNodoSur = '5492944796044';

/// El comando que se pega en Termux para instalar el bot (`botdemo/instalar.sh`). Empieza instalando curl: un Termux recién
/// instalado no lo trae (primera instalación real, 2026-10-09, `TRAMPAS.md`).
const comandoInstalarBot =
    'pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/neaserisgod/botdemo/main/instalar.sh | bash';
