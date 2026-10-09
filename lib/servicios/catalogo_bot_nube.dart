// Publica el catálogo corto del bot de WhatsApp en el sitio (`docs/PLAN-BOT.md`). Lo hace el equipo que sube la sync a la nube
// (la PC si hay; si no, el celular: uno solo a la vez, `conmutador_sync.dart`), al terminar cada vuelta: así el stock que ve el
// bot es el mismo que ve la caja.
//
// Economía (El dueño, 2026-10-01: "economizar lo más posible el uso de Cloudflare"): se manda solo si el catálogo cambió desde
// la última vez, y si el negocio tiene el bot; si tiene o no se pregunta una vez por hora.

import 'dart:convert';

import '../data/database.dart';
import '../data/repositorio_bot.dart';
import '../domain/bot_whatsapp.dart';
import 'cuenta_nube.dart';

class PublicadorCatalogoBot {
  PublicadorCatalogoBot({required this.db, required this.cliente, DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  final AppDatabase db;
  final ClienteNube cliente;
  final DateTime Function() _ahora;

  static const revisarPlanCada = Duration(hours: 1);

  bool? _tieneBot;
  DateTime? _planRevisado;
  String? _ultimo;

  /// Publica si hace falta. Nunca tira: un error se ve en la próxima vuelta, y vender o sincronizar no dependen de esto.
  Future<bool> publicarSiHaceFalta(String token) async {
    try {
      final ahora = _ahora();
      if (_tieneBot == null || _planRevisado == null || ahora.difference(_planRevisado!) >= revisarPlanCada) {
        _tieneBot = (await cliente.estadoBot(token)).tieneBot;
        _planRevisado = ahora;
      }
      if (_tieneBot != true) return false;
      final items = catalogoParaBot(await productosParaBot(db));
      final huella = jsonEncode([for (final x in items) x.toJson()]);
      if (huella == _ultimo) return false;
      await cliente.publicarCatalogoBot(token, items);
      _ultimo = huella;
      return true;
    } catch (_) {
      return false;
    }
  }
}
