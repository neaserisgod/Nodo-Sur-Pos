// Imprimir el ticket de la app en la terminal Point apenas se aprueba un cobro con ella (etapa C, el dueño 2026-10-04: con un
// interruptor en Configuración → Impresión, apagado de entrada). Es el ticket de la APP (el mismo de "Imprimir ticket"), no
// el comprobante de Mercado Pago: la orden de cobro sigue yendo con `print_on_terminal: no_ticket`.
//
// El interruptor es de ESTE equipo, como "Cobrar e imprimir por Nodo Sur": no viaja con las copias ni con la sync.

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_ticket.dart';
import 'impresion_posnet_nube.dart';
import 'marca_actual.dart';
import 'nube.dart' show nubeApp;
import 'preferencia_cobro_nube.dart';

const _clave = 'ticket_en_point_al_cobrar';

abstract final class PreferenciaTicketPoint {
  // Se lee una vez al arrancar (`cargar`) y después va en memoria: el cobro no espera a disco.
  static bool _valor = false;

  /// Apagado hasta que se cargue, o si la lectura falla.
  static bool get activo => _valor;

  static Future<void> cargar() async {
    try {
      _valor = (await SharedPreferences.getInstance()).getBool(_clave) ?? false;
    } catch (_) {
      _valor = false;
    }
  }

  static Future<void> guardar(bool valor) async {
    _valor = valor;
    try {
      await (await SharedPreferences.getInstance()).setBool(_clave, valor);
    } catch (_) {
      // Sin almacenamiento vale hasta cerrar la app.
    }
  }

  /// Solo para tests.
  static void fijarParaTest(bool valor) => _valor = valor;
}

/// Con el interruptor prendido, manda el ticket de [ventaId] a la terminal. Devuelve null si salió (o si el interruptor está
/// apagado) y el motivo si no. NUNCA lanza: la venta ya está cobrada y grabada, imprimir no la puede romper.
Future<String?> imprimirTicketAlCobrar(AppDatabase db, int ventaId, {http.Client? client}) async {
  if (!PreferenciaTicketPoint.activo) return null;
  try {
    final config = await db.select(db.configuracionTabla).getSingle();
    await imprimirTicketPosnet(
      accessToken: config.mpAccessToken,
      terminalId: config.mpTerminalId,
      terminalCobroId: config.mpTerminalCobroId,
      forzarNube: PreferenciaCobroNube.activo,
      almacen: nubeApp?.almacen,
      cliente: nubeApp?.cliente,
      ticket: await ticketDeVenta(db, ventaId),
      encabezadoNegocio: (await marcaDeBase(db)).encabezadoTicketEfectivo,
      client: client,
    );
    return null;
  } catch (e) {
    return '$e';
  }
}
