// Las guías de accesibilidad de Flutter sobre las pantallas principales del celular (390×844): tamaño táctil,
// etiquetas y contraste, en claro y oscuro. Mide; un fallo dice qué pantalla debe corregirse.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/navbar_companion.dart';
import 'package:la_plazoleta/companion/pantalla_gestion_companion.dart';
import 'package:la_plazoleta/companion/pantalla_historial_ventas.dart';
import 'package:la_plazoleta/companion/pantalla_inicio_companion.dart';
import 'package:la_plazoleta/companion/pantalla_precios.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

SesionCompanion _sesion() => SesionCompanion(abierta: true, id: 1, fechaApertura: DateTime.now());

final _pantallas = <String, Widget Function()>{
  'Inicio': () => Scaffold(
        body: PantallaInicioCompanion(
          nombreUsuario: 'Bruno',
          usuarioId: 1,
          sesion: _sesion(),
          estadoCaja: null,
          arqueoIntermedioVencido: false,
          onHacerArqueoIntermedio: () {},
          navegando: false,
          irA: (_) async {},
          onAbrirMovimientoCaja: (_) {},
          onSincronizar: () async {},
          carrito: const [],
          onVender: () {},
          servicio: null,
          pcEmparejada: true,
          actualizacionSinConexion: false,
        ),
        bottomNavigationBar: NavbarCompanion(indice: 0, onSeleccionar: (_) {}),
      ),
  'Productos': () => const Scaffold(body: PantallaPrecios()),
  'Historial': () => const Scaffold(body: PantallaHistorialVentas()),
  'Gestión': () => Scaffold(
        body: PantallaGestionCompanion(
          navegando: false,
          irA: (_) async {},
          sesion: _sesion(),
          onAbrirArqueo: () {},
          onCerrarCaja: () {},
          onCambiarModo: () {},
          modoUso: null,
        ),
        bottomNavigationBar: NavbarCompanion(indice: 3, onSeleccionar: (_) {}),
      ),
};

Future<void> _mostrar(WidgetTester tester, Brightness brillo, Widget Function() pantalla) async {
  SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Dueño'});
  // Sin la fuente real todo se dibuja con Ahem y desborda por culpa del test.
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
  final db = await tester.runAsync(() async => baseDeTest());
  usarBaseLocalDeTest(db!);
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: brillo == Brightness.dark ? TemaCompanion.oscuro : TemaCompanion.claro,
    home: pantalla(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final entrada in _pantallas.entries) {
    for (final brillo in [Brightness.light, Brightness.dark]) {
      group('Celular, ${entrada.key}, tema ${brillo == Brightness.light ? 'claro' : 'oscuro'}', () {
        testWidgets('objetivos táctiles de 48 dp', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          h.dispose();
        });
        testWidgets('todo lo que se toca tiene etiqueta', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });
        testWidgets('contraste del texto', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      });
    }
  }
}
