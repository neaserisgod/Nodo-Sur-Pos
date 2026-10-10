// El sitio de Nodo Sur, de mentira, para lo del bot de WhatsApp (`servicios/acceso_bot.dart`).
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/servicios/acceso_bot.dart';

/// El sitio, de mentira: lo que se resolvió y, si hace falta, cómo falla el próximo aviso.
class SitioBotFalso implements AccesoBot {
  SitioBotFalso([List<PedidoBot>? pedidos]) : pedidos = pedidos ?? [];
  final List<PedidoBot> pedidos;
  final List<({int id, bool aceptado})> resueltos = [];
  Object? fallaAlResolver;

  EstadoBot? estadoBot = const EstadoBot(tieneBot: true, puedeConfigurar: true);
  Map<String, dynamic>? configGuardada;
  int version = 0;

  final List<String> tokensPedidos = [];
  @override
  Future<({String sitio, String token, String email, int expiresAt})> tokenDelBot(String deviceId) async {
    tokensPedidos.add(deviceId);
    return (sitio: 'https://sitio.prueba', token: 'token-bot-${tokensPedidos.length}', email: 'duena@x.com', expiresAt: DateTime(2027, 10, 10).millisecondsSinceEpoch ~/ 1000);
  }
  @override
  Future<EstadoBot?> estado() async => estadoBot;
  @override
  Future<({int version, Map<String, dynamic>? config})> config() async => (version: version, config: configGuardada);
  @override
  Future<int> guardarConfig(Map<String, dynamic> config) async {
    configGuardada = config;
    return ++version;
  }
  @override
  Future<List<PedidoBot>> porConfirmar() async => [for (final p in pedidos) if (!resueltos.any((r) => r.id == p.id)) p];
  @override
  Future<void> resolver(int id, {required bool aceptado}) async {
    final f = fallaAlResolver;
    if (f != null) {
      fallaAlResolver = null;
      throw f;
    }
    resueltos.add((id: id, aceptado: aceptado));
  }
}

