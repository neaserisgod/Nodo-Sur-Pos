// Cobro con la Point desde el celular: qué pasa DESPUÉS de que la terminal aprobó el pago (revisión de blindaje 2026-10-04).
//
// Antes, si el celular perdía la conexión justo al guardar la venta de un pago ya cobrado, el diálogo mostraba "Reintentar" (que
// creaba una SEGUNDA orden: el cliente pagaba dos veces) y "Cobrar a mano" (que podía grabar una venta repetida). Ahora reintenta
// solo, con la misma orden, y si no puede ofrece únicamente volver a guardar ESTA venta.
//
// El polling usa `Future.delayed`/`Timer` sobre el reloj falso del test: se avanza a mano con `tester.pump(duration)`, nunca con
// `pumpAndSettle()` (el indicador de progreso nunca "asienta").

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart' show ErrorCompanion;
import 'package:la_plazoleta/companion/dialogo_cobro_posnet_companion.dart';
import 'package:la_plazoleta/companion/servicio_companion.dart';
import 'package:la_plazoleta/domain/cobro_posnet.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';

class _Servicio extends Fake implements ServicioCompanion {
  _Servicio({this.fallosAlConfirmar = const []});

  /// Lo que tira cada intento de confirmar, en orden; cuando se acaba, confirma bien.
  final List<Object> fallosAlConfirmar;
  int ordenesCreadas = 0;
  int confirmaciones = 0;
  int cobrosAMano = 0;

  @override
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})> iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? montoEfectivoMixtoCentavos,
    int? turnoId,
  }) async {
    ordenesCreadas++;
    return (ordenPendienteId: 1, ordenIdMp: 'ORD1', totalCentavos: 112000);
  }

  @override
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) async => ResultadoOrdenCobro.aprobada;

  @override
  Future<({int ventaId, int totalCentavos})> confirmarCobroPosnet({
    required int ordenPendienteId,
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    int? montoEfectivoMixtoCentavos,
    int? turnoId,
  }) async {
    confirmaciones++;
    if (confirmaciones <= fallosAlConfirmar.length) throw fallosAlConfirmar[confirmaciones - 1];
    return (ventaId: 7, totalCentavos: 112000);
  }

  @override
  Future<({int ventaId, int totalCentavos})> cobrarVirtualAMano({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    String? canal,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
    int? montoEfectivoMixtoCentavos,
    int? turnoId,
  }) async {
    cobrosAMano++;
    return (ventaId: 8, totalCentavos: 112000);
  }
}

Future<void> _abrir(WidgetTester tester, _Servicio servicio) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.claro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => mostrarDialogoCobroPosnetCompanion(
            context,
            cliente: servicio,
            usuarioId: 1,
            sesionCajaId: 1,
            lineas: const [
              LineaVentaPorUnidad(
                productoId: '1',
                nombreProducto: 'Coca-Cola 500ml',
                proveedorId: null,
                cantidad: 1,
                precioUnitarioCentavos: 112000,
              ),
            ],
            canal: 'qr',
            montoCentavos: 112000,
          ),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // sube la hoja
  await tester.pump(); // resuelve iniciarCobroPosnet
}

/// Avanza el reloj falso en pasos chicos hasta que pase [total] (el polling, y las esperas entre intentos de guardado).
Future<void> _avanzar(WidgetTester tester, Duration total) async {
  var corrido = Duration.zero;
  while (corrido < total) {
    await tester.pump(const Duration(milliseconds: 500));
    corrido += const Duration(milliseconds: 500);
  }
}

void main() {
  testWidgets('pago aprobado y guardado al primer intento: "Pago aprobado" con "Listo"', (tester) async {
    final servicio = _Servicio();
    await _abrir(tester, servicio);
    await _avanzar(tester, const Duration(seconds: 3));

    expect(find.textContaining('Pago aprobado'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
    expect(servicio.ordenesCreadas, 1);
    expect(servicio.confirmaciones, 1);
  });

  testWidgets('si se corta la conexión al guardar la venta, reintenta solo con la MISMA orden y la guarda una sola vez', (tester) async {
    final servicio = _Servicio(fallosAlConfirmar: [const SocketException('sin wifi'), const SocketException('sin wifi')]);
    await _abrir(tester, servicio);
    await _avanzar(tester, const Duration(seconds: 12));

    expect(find.textContaining('Pago aprobado'), findsOneWidget);
    expect(servicio.confirmaciones, 3, reason: 'dos cortes y la tercera entra');
    expect(servicio.ordenesCreadas, 1, reason: 'nunca se crea otra orden: el cliente ya pagó');
    expect(servicio.cobrosAMano, 0);
  });

  testWidgets('si no logra guardarla, avisa que el pago YA se cobró y solo ofrece Reintentar/Cerrar (nunca "Cobrar a mano" ni otra orden)', (tester) async {
    final servicio = _Servicio(fallosAlConfirmar: List.filled(4, const SocketException('sin wifi')));
    await _abrir(tester, servicio);
    await _avanzar(tester, const Duration(seconds: 20));

    expect(find.textContaining('YA se cobró'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.text('Cobrar a mano'), findsNothing, reason: 'podría duplicar una venta que sí se guardó');
    expect(servicio.confirmaciones, 4);

    await tester.tap(find.text('Reintentar'));
    await _avanzar(tester, const Duration(seconds: 3));

    expect(find.textContaining('Pago aprobado'), findsOneWidget);
    expect(servicio.confirmaciones, 5, reason: 'volvió a pedir guardar ESTA venta');
    expect(servicio.ordenesCreadas, 1, reason: 'sin una segunda orden');
    expect(servicio.cobrosAMano, 0);
  });

  testWidgets('una respuesta definitiva del servidor (la caja ya se cerró) no se reintenta sola: se muestra de una', (tester) async {
    final servicio = _Servicio(fallosAlConfirmar: [const ErrorCompanion(409, 'La caja ya se cerró, esta venta no se guardó')]);
    await _abrir(tester, servicio);
    await _avanzar(tester, const Duration(seconds: 12));

    expect(find.textContaining('La caja ya se cerró'), findsOneWidget);
    expect(find.textContaining('YA se cobró'), findsOneWidget);
    expect(servicio.confirmaciones, 1, reason: 'no insiste con algo que el servidor ya contestó que no');
  });
}
