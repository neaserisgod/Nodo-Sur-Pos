import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/cobro_posnet.dart';

void main() {
  group('clasificarEstadoOrden — Fase 12, tabla real de estados de MP', () {
    test('"processed" es aprobada', () {
      expect(clasificarEstadoOrden('processed'), ResultadoOrdenCobro.aprobada);
    });

    test('"failed" es rechazada', () {
      expect(clasificarEstadoOrden('failed'), ResultadoOrdenCobro.rechazada);
    });

    test('"canceled" es rechazada', () {
      expect(clasificarEstadoOrden('canceled'), ResultadoOrdenCobro.rechazada);
    });

    test('"expired" es rechazada', () {
      expect(clasificarEstadoOrden('expired'), ResultadoOrdenCobro.rechazada);
    });

    test('"created" es pendiente (recién creada, seguir consultando)', () {
      expect(clasificarEstadoOrden('created'), ResultadoOrdenCobro.pendiente);
    });

    test('"processing" es pendiente', () {
      expect(clasificarEstadoOrden('processing'), ResultadoOrdenCobro.pendiente);
    });

    test('"action_required" es pendiente', () {
      expect(clasificarEstadoOrden('action_required'), ResultadoOrdenCobro.pendiente);
    });

    test('un estado desconocido nunca se inventa como rechazo — pendiente por defecto', () {
      expect(clasificarEstadoOrden('algo_que_mp_agregue_despues'), ResultadoOrdenCobro.pendiente);
    });
  });
}
