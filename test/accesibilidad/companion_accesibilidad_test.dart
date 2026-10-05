// Las guías de accesibilidad de Flutter sobre las pantallas principales del celular (390×844): tamaño táctil
// (44 px, el mínimo que fija el mock),
// etiquetas y contraste, en claro y oscuro. Mide; un fallo dice qué pantalla debe corregirse.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_caja_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_inicio_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_mas_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_productos_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

/// Las cinco pestañas del mock, dentro de su marco (con la barra inferior).
Widget _pestania(Widget pantalla, PestaniaNs activa, ControladorAppNs c, bool barra) => AppNs(
      controlador: c,
      version: 0,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.ns.paper,
          extendBody: true,
          body: pantalla,
          bottomNavigationBar: barra ? BarraInferiorNs(activa: activa, onSeleccionar: (_) {}, hayActualizacion: true) : null,
        ),
      ),
    );

final _pantallas = <String, Widget Function(bool barra)>{
  'Inicio': (b) => _pestania(const PantallaInicioNs(), PestaniaNs.inicio, ControladorFalsoNs(), b),
  'Caja': (b) => _pestania(const PantallaCajaNs(), PestaniaNs.caja, ControladorFalsoNs(), b),
  'Más': (b) => _pestania(const PantallaMasNs(), PestaniaNs.mas, ControladorFalsoNs(), b),
  'Productos': (b) => _pestania(const PantallaProductosNs(), PestaniaNs.productos, ControladorFalsoNs(), b),
  'Vender': (b) => _pestania(
        PantallaCarritoVenta(
          cliente: null,
          servicio: PuertoLocal(baseLocalCompanion()),
          usuarioId: 1,
          carrito: [
            const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata 473 ml', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
            const LineaVentaPesable(productoId: 'b', nombreProducto: 'Jamón cocido', proveedorId: null, gramos: 250, precioPorKiloCentavos: 1460000),
          ],
        ),
        PestaniaNs.vender,
        ControladorFalsoNs(),
        b,
      ),
};

Future<void> _mostrar(WidgetTester tester, Brightness brillo, Widget Function(bool barra) pantalla, {bool barra = true}) async {
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
    home: pantalla(barra),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final entrada in _pantallas.entries) {
    for (final brillo in [Brightness.light, Brightness.dark]) {
      group('Celular, ${entrada.key}, tema ${brillo == Brightness.light ? 'claro' : 'oscuro'}', () {
        testWidgets('objetivos táctiles de 44 px (mínimo del mock)', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          h.dispose();
        });
        testWidgets('todo lo que se toca tiene etiqueta', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });
        // La barra inferior se deja afuera: su texto chico ya está medido con los tokens del mock
        // (>= 4,8:1) y el verificador de pixeles confunde la burbuja del icono con el fondo del rótulo.
        testWidgets('contraste del texto', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value, barra: false);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      });
    }
  }
}
