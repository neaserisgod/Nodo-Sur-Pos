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

    test('"action_required" es confirmar en la terminal: sigue esperando, pero se avisa en pantalla', () {
      expect(clasificarEstadoOrden('action_required'), ResultadoOrdenCobro.confirmarEnTerminal);
      expect(sigueEsperando(ResultadoOrdenCobro.confirmarEnTerminal), isTrue);
    });

    test('un estado desconocido nunca se inventa como rechazo — pendiente por defecto', () {
      expect(clasificarEstadoOrden('algo_que_mp_agregue_despues'), ResultadoOrdenCobro.pendiente);
    });
  });

  group('vencimiento de la orden (etapa A, 2026-10-04)', () {
    test('la orden vence a los 2 minutos y se manda en ISO 8601, como pide Mercado Pago', () {
      expect(vencimientoOrdenCobroPosnet, const Duration(minutes: 2));
      expect(duracionIso8601(vencimientoOrdenCobroPosnet), 'PT2M');
      expect(duracionIso8601(const Duration(minutes: 1, seconds: 30)), 'PT1M30S');
      expect(duracionIso8601(const Duration(hours: 1, minutes: 15)), 'PT1H15M');
    });

    test('se consulta un rato más de lo que dura la orden: siempre se llega a ver "expired" (no cobrada)', () {
      expect(timeoutPollingCobroPosnet > vencimientoOrdenCobroPosnet, isTrue);
    });

    test('solo aprobada y rechazada terminan la espera', () {
      expect(sigueEsperando(ResultadoOrdenCobro.pendiente), isTrue);
      expect(sigueEsperando(ResultadoOrdenCobro.aprobada), isFalse);
      expect(sigueEsperando(ResultadoOrdenCobro.rechazada), isFalse);
    });
  });

  group('resultadoDesdeRespuesta — lo que el celular lee de la PC, sin romperse con una versión distinta', () {
    test('lee los tres de siempre', () {
      expect(resultadoDesdeRespuesta('aprobada'), ResultadoOrdenCobro.aprobada);
      expect(resultadoDesdeRespuesta('rechazada'), ResultadoOrdenCobro.rechazada);
      expect(resultadoDesdeRespuesta('pendiente'), ResultadoOrdenCobro.pendiente);
    });

    test('pendiente con enTerminal es confirmar en la terminal', () {
      expect(resultadoDesdeRespuesta('pendiente', enTerminal: true), ResultadoOrdenCobro.confirmarEnTerminal);
    });

    test('algo desconocido o vacío es pendiente: nunca se inventa un cobro ni un rechazo', () {
      expect(resultadoDesdeRespuesta('algo_nuevo'), ResultadoOrdenCobro.pendiente);
      expect(resultadoDesdeRespuesta(null), ResultadoOrdenCobro.pendiente);
    });
  });

  group('canales y crédito en 1 pago (etapa C)', () {
    test('crédito va siempre en 1 pago: la terminal no muestra cuotas', () {
      expect(medioDePagoOrden(canalCredito), {'default_type': 'credit_card', 'default_installments': 1});
      expect(medioDePagoOrden(canalDebito), {'default_type': 'debit_card'});
      expect(medioDePagoOrden(canalQr), {'default_type': 'qr'});
    });

    test('débito y crédito son "tarjeta"; QR no', () {
      expect(esCanalTarjeta(canalDebito), isTrue);
      expect(esCanalTarjeta(canalCredito), isTrue);
      expect(esCanalTarjeta(canalQr), isFalse);
      expect(esCanalTarjeta(null), isFalse);
    });

    test('nombres para mostrar', () {
      expect(nombreCanal(canalCredito), 'Crédito');
      expect(nombreCanal(canalDebito), 'Débito');
      expect(nombreCanal(canalQr), 'QR');
      expect(nombreCanal(null), 'Mercado Pago');
    });
  });
}
