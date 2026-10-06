// Logo del ticket (rediseño v4, etapa 8.3): se guarda en la base local, se ve en Configuración › Comercio y sale en el PDF.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/pdf_ticket.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart';
import 'package:la_plazoleta/domain/ticket.dart';
import 'package:la_plazoleta/ui/configuracion/configuracion_controlador.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Uint8List _png() {
  final imagen = img.Image(width: 80, height: 40, numChannels: 3);
  img.fill(imagen, color: img.ColorRgb8(10, 10, 10));
  return Uint8List.fromList(img.encodePng(imagen));
}

/// Una imagen incrustada en el PDF aparece como objeto `/Subtype /Image` (`/ImageB` solo está en la lista de procedimientos).
bool _tieneImagen(Uint8List bytes) => RegExp(r'/Subtype\s*/Image\b').hasMatch(String.fromCharCodes(bytes));

void main() {
  test('guardar un logo lo deja en la base, uno que no es imagen se rechaza y quitar lo borra', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final c = ConfiguracionControlador(db);
    await c.cargarTodo();
    expect(c.configuracion!.logoTicket, isNull);

    expect(await c.guardarLogoTicket(Uint8List.fromList([1, 2, 3])), isFalse);
    expect(await logoTicketGuardado(db), isNull);

    expect(await c.guardarLogoTicket(_png()), isTrue);
    expect(await logoTicketGuardado(db), isNotNull);
    expect(c.configuracion!.logoTicket, isNotNull);

    await c.quitarLogoTicket();
    expect(await logoTicketGuardado(db), isNull);
  });

  test('el PDF lleva la imagen solo si hay logo', () async {
    final ticket = construirTicket(
      fecha: DateTime(2026, 10, 6, 15),
      vendedor: 'Dueño',
      lineas: const [LineaTicket(nombreProducto: 'Coca', cantidad: 1, subtotalCentavos: 100000)],
      desglose: const DesgloseTicket(),
    );
    final sin = await generarPdfTicket(ticket, encabezadoNegocio: 'La Plazoleta');
    final con = await generarPdfTicket(ticket, encabezadoNegocio: 'La Plazoleta', logo: _png());
    expect(_tieneImagen(sin), isFalse);
    expect(_tieneImagen(con), isTrue);
  });

  test('guardarTicketPdf toma el logo de la base', () async {
    final db = baseDeTest();
    addTearDown(db.close);
    final carpeta = await Directory.systemTemp.createTemp('logo_ticket_');
    addTearDown(() => carpeta.delete(recursive: true));
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await db.into(db.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0));
    final ventaId = await db.into(db.ventas).insert(
      VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, fecha: Value(DateTime(2026, 10, 6, 15)), subtotalCentavos: 100000, totalCentavos: 100000),
    );
    await configurarLogoTicket(db, _png());
    final ruta = await guardarTicketPdf(db, ventaId: ventaId, carpetaDestino: carpeta.path, encabezadoNegocio: 'La Plazoleta');
    expect(_tieneImagen(await File(ruta).readAsBytes()), isTrue);
  });

  testWidgets('Configuración › Comercio: sin logo ofrece elegir; con logo lo muestra y permite quitarlo', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    await configurarLogoTicket(db, _png());
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaConfiguracion(db: db, usuarioId: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grupo_negocio')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vista_logo_ticket')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('boton_quitar_logo')));
    await tester.tap(find.byKey(const Key('boton_quitar_logo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vista_logo_ticket')), findsNothing);
    expect(find.byKey(const Key('boton_elegir_logo')), findsOneWidget);
    expect(await logoTicketGuardado(db), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
