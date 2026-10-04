// Avisos en vivo de Mercado Pago sobre una orden de cobro de la Point (etapa A, 2026-10-04). Mercado Pago le avisa al sitio
// (`/api/mp/webhook`) y el sitio lo reenvía por la misma conexión de la sync (`ClienteNube.escuchar`) a los equipos de la
// sucursal. El aviso trae solo el id de la orden: NO dice si se cobró. Solo despierta al diálogo de cobro para que consulte en
// ese momento en vez de esperar su próximo turno; el resultado sale siempre de consultar la orden.

import 'dart:async';

import '../domain/avisos_mp.dart';

final StreamController<String> _avisos = StreamController<String>.broadcast();

/// Ids de las órdenes de las que Mercado Pago avisó algo.
Stream<String> get avisosOrdenMp => _avisos.stream;

/// Lo llama la conexión en vivo de la sync al recibir `{"mp":{"orden":…}}`.
void avisarOrdenMp(String ordenId) {
  if (ordenId.isNotEmpty) _avisos.add(ordenId);
}

/// Espera [maximo] o hasta que llegue un aviso de [ordenId], lo que pase primero. Reemplaza la pausa fija entre consultas: con
/// aviso se consulta al instante; sin aviso (sin internet, aviso perdido, sitio sin configurar) es la misma pausa de siempre.
Future<void> esperarAvisoOrden(String ordenId, Duration maximo) {
  final listo = Completer<void>();
  late final StreamSubscription<String> sub;
  final reloj = Timer(maximo, () {
    if (!listo.isCompleted) listo.complete();
  });
  sub = avisosOrdenMp.listen((id) {
    if (id == ordenId && !listo.isCompleted) listo.complete();
  });
  return listo.future.whenComplete(() {
    reloj.cancel();
    unawaited(sub.cancel());
  });
}

// --- Avisos de cobros, contracargos y reclamos (etapa D) -------------------------------------------------------------------
// Llegan por la misma conexión, con `{"mp":{"aviso":{…}}}`. A diferencia del aviso de una orden, ESTOS sí traen datos (lo que el
// sitio consultó con su token); el servicio de avisos (`avisos_mp_servicio.dart`) los guarda y la campanita los cruza con las
// ventas. Solo se muestran en la PC.

final StreamController<AvisoMp> _avisosMp = StreamController<AvisoMp>.broadcast();
final StreamController<void> _conexionAbierta = StreamController<void>.broadcast();

Stream<AvisoMp> get avisosMpEnVivo => _avisosMp.stream;

void avisarAvisoMp(AvisoMp aviso) => _avisosMp.add(aviso);

/// Se abrió la conexión en vivo: lo que pasó con la PC apagada no tuvo aviso, hay que pedirlo.
Stream<void> get conexionEnVivoAbierta => _conexionAbierta.stream;

void avisarConexionEnVivoAbierta() => _conexionAbierta.add(null);
