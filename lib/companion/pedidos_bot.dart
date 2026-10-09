// Aceptar o rechazar un pedido del bot de WhatsApp (`docs/PLAN-BOT.md`, El dueño, 2026-10-09). Cualquiera que use la app lo
// puede hacer. Aceptar crea el encargue apartado de siempre (descuenta stock ya, como cualquier encargue) y recién después le
// avisa al sitio, que le avisa al bot y el bot al cliente. Rechazar no toca nada de la base.
//
// El orden importa: si se avisara primero, un "no alcanza el stock" al apartar dejaría al cliente con un "confirmado" que no
// es. Y como son dos pasos en dos lugares (la base y el sitio), el pedido convertido queda anotado en el celular entre uno y
// otro: si avisar falla (sin internet), al reintentar no se aparta dos veces.

import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositorio_encargues.dart' show EncargueSinStock;
import '../domain/bot_whatsapp.dart';
import '../servicios/acceso_bot.dart';
import '../servicios/cuenta_nube.dart' show ErrorNube;
import 'cliente_companion.dart' show ApartadoCompanion, ErrorCompanion;
import 'servicio_companion.dart';

/// Qué pedidos del bot ya se convirtieron en encargue y todavía no se pudieron avisar al sitio: pedido → encargue.
abstract class RegistroPedidosBot {
  Future<int?> encargueDe(int pedidoId);
  Future<void> anotar(int pedidoId, int encargueId);
  Future<void> olvidar(int pedidoId);
}

class RegistroPedidosBotEnMemoria implements RegistroPedidosBot {
  final Map<int, int> anotados = {};

  @override
  Future<int?> encargueDe(int pedidoId) async => anotados[pedidoId];

  @override
  Future<void> anotar(int pedidoId, int encargueId) async => anotados[pedidoId] = encargueId;

  @override
  Future<void> olvidar(int pedidoId) async => anotados.remove(pedidoId);
}

/// En las preferencias del celular: sobrevive a cerrar la app entre crear el encargue y poder avisar.
class RegistroPedidosBotPrefs implements RegistroPedidosBot {
  static const _clave = 'bot_pedidos_convertidos';

  Future<Map<int, int>> _leer() async {
    final prefs = await SharedPreferences.getInstance();
    final m = <int, int>{};
    for (final x in prefs.getStringList(_clave) ?? const <String>[]) {
      final partes = x.split(':');
      final p = int.tryParse(partes.first), e = partes.length == 2 ? int.tryParse(partes.last) : null;
      if (p != null && e != null) m[p] = e;
    }
    return m;
  }

  Future<void> _guardar(Map<int, int> m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_clave, [for (final x in m.entries) '${x.key}:${x.value}']);
  }

  @override
  Future<int?> encargueDe(int pedidoId) async => (await _leer())[pedidoId];

  @override
  Future<void> anotar(int pedidoId, int encargueId) async => _guardar((await _leer())..[pedidoId] = encargueId);

  @override
  Future<void> olvidar(int pedidoId) async => _guardar((await _leer())..remove(pedidoId));
}

sealed class ResultadoAceptarPedido {
  const ResultadoAceptarPedido();
}

/// Encargue creado y el cliente se entera.
class PedidoAceptado extends ResultadoAceptarPedido {
  const PedidoAceptado();
}

/// No se apartó nada: falta stock o un producto ya no está. No se avisó al cliente.
class PedidoConFaltantes extends ResultadoAceptarPedido {
  const PedidoConFaltantes(this.faltan);
  final List<String> faltan;
}

/// La PC conectada no manda la identidad de los productos (versión vieja): no se puede saber qué producto es cada línea.
class PedidoPcVieja extends ResultadoAceptarPedido {
  const PedidoPcVieja();
}

/// El sitio dice que el pedido ya estaba resuelto, con el encargue ya creado acá. Puede ser otro equipo (y el encargue quedó
/// repetido) o el aviso de ESTE equipo que llegó y cuya respuesta se perdió (y el encargue es el bueno): no se puede saber,
/// así que se avisa en vez de cancelarlo solo.
class PedidoYaResuelto extends ResultadoAceptarPedido {
  const PedidoYaResuelto();
}

/// El encargue quedó creado pero no se pudo avisar (sin internet): al reintentar solo se avisa.
class PedidoSinAvisar extends ResultadoAceptarPedido {
  const PedidoSinAvisar(this.error);
  final Object error;
}

Future<ResultadoAceptarPedido> aceptarPedidoBot({
  required PedidoBot pedido,
  required ServicioCompanion servicio,
  required AccesoBot acceso,
  required RegistroPedidosBot registro,
  required int usuarioId,
}) async {
  var encargueId = await registro.encargueDe(pedido.id);
  if (encargueId == null) {
    final productos = await servicio.productos();
    if (productos.isNotEmpty && productos.every((p) => p.globalId == null)) return const PedidoPcVieja();
    final r = apartadosDePedido(pedido, [
      for (final p in productos)
        ProductoDelPedido(id: p.id, globalId: p.globalId, nombre: p.nombre, esPesable: p.esPesable, activo: p.activo, stock: p.stock, stockGramos: p.stockGramos),
    ]);
    if (r.faltan.isNotEmpty) return PedidoConFaltantes(r.faltan);
    try {
      encargueId = await servicio.crearEncargue(
        nombreCliente: nombreEncargueDePedido(pedido),
        lineas: [for (final l in r.lineas) ApartadoCompanion(productoId: l.productoId, cantidad: l.cantidad, gramos: l.gramos)],
        usuarioId: usuarioId,
      );
    } on EncargueSinStock catch (e) {
      // Se vendió entre leer el stock y apartar.
      return PedidoConFaltantes(['No alcanza el stock de ${e.nombreProducto}.']);
    } on ErrorCompanion catch (e) {
      if (e.statusCode == 409) return PedidoConFaltantes([e.mensaje]);
      rethrow;
    }
    await registro.anotar(pedido.id, encargueId);
  }
  try {
    await acceso.resolver(pedido.id, aceptado: true);
  } on ErrorNube catch (e) {
    if (e.codigo == 'ya_resuelto' || e.codigo == 'no_existe') {
      await registro.olvidar(pedido.id);
      return const PedidoYaResuelto();
    }
    return PedidoSinAvisar(e);
  } catch (e) {
    return PedidoSinAvisar(e);
  }
  await registro.olvidar(pedido.id);
  return const PedidoAceptado();
}

/// Rechazar no toca la base. Un pedido que ya se convirtió en encargue no se rechaza (el cliente quedaría con un "no" y la
/// mercadería apartada): primero se cancela el encargue desde la lista.
Future<void> rechazarPedidoBot({required PedidoBot pedido, required AccesoBot acceso, required RegistroPedidosBot registro}) async {
  if (await registro.encargueDe(pedido.id) != null) {
    throw StateError('Este pedido ya está apartado como encargue: tocá Aceptar para avisarle al cliente.');
  }
  await acceso.resolver(pedido.id, aceptado: false);
}
