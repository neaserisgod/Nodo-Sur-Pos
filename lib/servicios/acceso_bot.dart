// El bot de WhatsApp visto desde las pantallas (`docs/PLAN-BOT.md`): estado, configuración y pedidos, con el token de la cuenta
// vinculada. Una interfaz para que Encargues y la pantalla del bot se prueben sin red, y para que un equipo que no está
// vinculado (o se desvinculó con la app abierta) simplemente no vea nada del bot en vez de romper.

import '../domain/bot_whatsapp.dart';
import 'cuenta_nube.dart';

abstract class AccesoBot {
  /// Null si este equipo no está vinculado a una cuenta (no hay a quién preguntarle).
  Future<EstadoBot?> estado();

  Future<({int version, Map<String, dynamic>? config})> config();

  Future<int> guardarConfig(Map<String, dynamic> config);

  /// Los pedidos que siguen por confirmar, del más viejo al más nuevo. Vacío si el equipo no está vinculado.
  Future<List<PedidoBot>> porConfirmar();

  /// Tira [ErrorNube] `ya_resuelto` si otro equipo lo resolvió antes.
  Future<void> resolver(int id, {required bool aceptado});

  /// El token del bot que corre adentro de este celular (Nodo Sur Servicios), con la dirección del sitio para el bot.
  Future<({String sitio, String token, String email, int expiresAt})> tokenDelBot(String deviceId);
}

class AccesoBotNube implements AccesoBot {
  /// [cuenta] se pide en cada uso, como la IA (`ia_nube.dart`): un equipo se puede vincular o desvincular con la app abierta.
  AccesoBotNube(this.cuenta);

  final Future<({AlmacenCuenta almacen, ClienteNube cliente})?> Function() cuenta;

  /// Tope de páginas al pedir la lista: los pedidos se borran a los 30 días, así que con esto entra cualquier almacén.
  static const _maxPaginas = 20;

  Future<({String token, ClienteNube cliente})?> _vinculada() async {
    final c = await cuenta();
    final vinculada = await c?.almacen.leer();
    if (c == null || vinculada == null) return null;
    return (token: vinculada.token, cliente: c.cliente);
  }

  Future<({String token, ClienteNube cliente})> _exigir() async {
    final v = await _vinculada();
    if (v == null) throw const ErrorNube('no_device', 'Este equipo no está vinculado a la cuenta.');
    return v;
  }

  @override
  Future<({String sitio, String token, String email, int expiresAt})> tokenDelBot(String deviceId) async {
    final v = await _exigir();
    final r = await v.cliente.tokenBot(v.token, deviceId);
    final c = v.cliente;
    final sitio = Uri(scheme: c.esquema, host: c.host, port: c.puerto).toString();
    return (sitio: sitio, token: r.token, email: r.email, expiresAt: r.expiresAt);
  }

  @override
  Future<EstadoBot?> estado() async {
    final v = await _vinculada();
    if (v == null) return null;
    return v.cliente.estadoBot(v.token);
  }

  @override
  Future<({int version, Map<String, dynamic>? config})> config() async {
    final v = await _exigir();
    return v.cliente.configBot(v.token);
  }

  @override
  Future<int> guardarConfig(Map<String, dynamic> config) async {
    final v = await _exigir();
    return v.cliente.guardarConfigBot(v.token, config);
  }

  @override
  Future<List<PedidoBot>> porConfirmar() async {
    final v = await _vinculada();
    if (v == null) return const [];
    // El sitio devuelve lo que cambió desde el cursor: desde 0 es todo lo de los últimos 30 días, y el último estado de cada
    // pedido es el que vale.
    final ultimos = <int, PedidoBot>{};
    var desde = 0;
    for (var i = 0; i < _maxPaginas; i++) {
      final r = await v.cliente.pedidosBot(v.token, desde: desde);
      for (final p in r.pedidos) {
        ultimos[p.id] = p;
      }
      if (!r.mas || r.hasta == desde) break;
      desde = r.hasta;
    }
    return [for (final p in ultimos.values) if (p.estado == EstadoPedidoBot.porConfirmar) p]..sort((a, b) => a.creado.compareTo(b.creado));
  }

  @override
  Future<void> resolver(int id, {required bool aceptado}) async {
    final v = await _exigir();
    await v.cliente.resolverPedidoBot(v.token, id, aceptado: aceptado);
  }
}
