import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/pdf_ticket.dart';
import 'package:la_plazoleta/domain/ticket.dart';
import '../helpers/base_para_tests.dart';

void main() {
  group('nombreArchivoTicket', () {
    test('fecha y número de venta, para poder reimprimir después', () {
      final nombre = nombreArchivoTicket(ventaId: 42, fecha: DateTime(2026, 8, 30));
      expect(nombre, '2026-08-30_venta-00042.pdf');
    });
  });

  group('generarPdfTicket', () {
    test('produce bytes de un PDF real', () async {
      final ticket = construirTicket(
        fecha: DateTime(2026, 8, 30, 15, 0),
        vendedor: 'Dueño',
        lineas: const [
          LineaTicket(nombreProducto: 'Coca-Cola 500ml', cantidad: 2, subtotalCentavos: 224000),
        ],
        desglose: const DesgloseTicket(),
      );

      final bytes = await generarPdfTicket(ticket, encabezadoNegocio: 'La Plazoleta');

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('guardarTicketPdf', () {
    late AppDatabase db;
    late Directory carpetaTemp;
    late int usuarioId;
    late int sesionId;

    setUp(() async {
      db = baseDeTest();
      usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      sesionId = await db.into(db.sesionesDeCaja).insert(
            SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
          );
      carpetaTemp = await Directory.systemTemp.createTemp('ticket_test_');
    });
    tearDown(() async {
      await db.close();
      await carpetaTemp.delete(recursive: true);
    });

    test('escribe el PDF en la carpeta indicada con el nombre esperado', () async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: Value(DateTime(2026, 8, 30, 15, 0)),
              subtotalCentavos: 100000,
              totalCentavos: 100000,
            ),
          );

      final ruta = await guardarTicketPdf(
        db,
        ventaId: ventaId,
        carpetaDestino: carpetaTemp.path,
        encabezadoNegocio: 'La Plazoleta',
      );

      expect(File(ruta).existsSync(), isTrue);
      expect(ruta, endsWith('2026-08-30_venta-${ventaId.toString().padLeft(5, '0')}.pdf'));
    });
  });
}
