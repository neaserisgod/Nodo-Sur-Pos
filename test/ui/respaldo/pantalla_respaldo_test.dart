// testWidgets() acá se limita a estados que no tocan disco real: en este
// entorno, cualquier operación de dart:io dentro de la zona de testWidgets
// se cuelga indefinidamente (verificado a mano, ver
// respaldo_controlador_test.dart para la cobertura con carpeta configurada,
// hecha con test() plano).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/repositorio_respaldo.dart';
import 'package:la_plazoleta/ui/respaldo/dialogo_confirmar_restaurar.dart';
import 'package:la_plazoleta/ui/respaldo/pantalla_respaldo.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  group('sin carpeta configurada', () {
    testWidgets('avisa que falta configurar y el botón de respaldar está deshabilitado', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);

      await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: Scaffold(body: ContenidoRespaldo(db: db, usuarioId: 1))));
      await tester.pumpAndSettle();

      expect(find.text('Sin carpeta configurada'), findsOneWidget);
      final boton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Respaldar ahora'));
      expect(boton.onPressed, isNull);
    });
  });

  group('importar una base', () {
    testWidgets('se ofrece en la pantalla de respaldo', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: Scaffold(body: ContenidoRespaldo(db: db, usuarioId: 1))));
      await tester.pumpAndSettle();
      expect(find.text('Importar una base'), findsOneWidget);
      final boton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Importar desde un archivo…'));
      expect(boton.onPressed, isNotNull);
    });
  });

  group('mostrarDialogoConfirmarRestaurar — con datos y funciones inyectadas, sin tocar disco', () {
    final archivoFalso = ArchivoRespaldo(
      ruta: 'no-se-usa-porque-se-cancela',
      nombre: 'la_plazoleta_2026-08-30_120000.sqlite',
      fecha: DateTime(2026, 8, 30, 12, 0),
      tamanioBytes: 1024,
    );

    testWidgets('muestra la confirmación fuerte, y cancelar no llama a nada', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      var resolverLlamado = false;
      var reinicioLlamado = false;

      await tester.pumpWidget(MaterialApp(
        theme: TemaPlazoleta.oscuro,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => mostrarDialogoConfirmarRestaurar(
              context,
              db: db,
              archivo: archivoFalso,
              fechaFormateada: '30/08/2026',
              reiniciarApp: () => reinicioLlamado = true,
              resolverRutaDestino: () async {
                resolverLlamado = true;
                return 'no-se-usa';
              },
            ),
            child: const Text('Abrir'),
          ),
        ),
      ));

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('¿Restaurar este respaldo?'), findsOneWidget);
      expect(find.textContaining('30/08/2026'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Restaurar este respaldo?'), findsNothing);
      expect(resolverLlamado, isFalse);
      expect(reinicioLlamado, isFalse);
    });

    testWidgets('confirmar cierra la base, resuelve el destino, copia (inyectado) y reinicia, en orden',
        (tester) async {
      final db = baseDeTest();
      final pasos = <String>[];

      await tester.pumpWidget(MaterialApp(
        theme: TemaPlazoleta.oscuro,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => mostrarDialogoConfirmarRestaurar(
              context,
              db: db,
              archivo: archivoFalso,
              fechaFormateada: '30/08/2026',
              resolverRutaDestino: () async {
                pasos.add('resolver');
                return 'no-se-usa';
              },
              copiarArchivo: ({required rutaRespaldo, required rutaDestino}) async {
                pasos.add('copiar');
              },
              reiniciarApp: () => pasos.add('reiniciar'),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ));

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restaurar y reiniciar'));
      await tester.pumpAndSettle();

      expect(pasos, ['resolver', 'copiar', 'reiniciar']);
    });
  });
}
