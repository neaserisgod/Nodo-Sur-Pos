// Comportamiento de arranque (main.dart). El dueño, 2026-09-06: "que no salga
// obligatoriamente al abrir la app" y, acto seguido, "pasa lo mismo con el
// cierre de caja, bloquea al abrir" — antes, tanto sin sesión de caja
// abierta como con una sesión abierta de un día anterior sin cerrar (Regla
// 5), un widget raíz (`_Raiz`, ya eliminado) reemplazaba toda la app por una
// pantalla sin salida (un `Dialog` modal en el primer caso, `PantallaCierre`
// como pantalla completa en el segundo) antes de dejar ver nada más.
//
// Desde que Dashboard reemplazó a `PantallaVenta` como `home` de la app
// (El dueño, 2026-09-14: "dashboard es la pantalla principal, totalmente
// aparte"), lo único que este archivo prueba es la garantía a nivel de
// arranque: nunca un diálogo sin salida tapando todo, la barra lateral
// siempre navegable sin importar el estado de la sesión. El bloqueo real de
// VENDER bajo una sesión de otro día (Regla 5) es responsabilidad de
// `PantallaVenta` — ya probado en `pantalla_venta_turno_test.dart` y
// `pantalla_venta_test.dart`, sin cambios acá, porque Venta sigue resolviendo
// sola sus propios tres estados apenas se entra a ella (un clic desde
// Dashboard).

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/navbar_superior.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/main.dart';
import 'helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(LaPlazoletaApp(db: db));
  // No `pumpAndSettle()`: el `Timer.periodic` de un minuto del tema
  // automático (main.dart, `_tickHorario`) reprograma un frame en cada
  // vuelta, así que nunca hay "cero frames pendientes" — pumpAndSettle
  // agota su propio timeout de 10 minutos en vez de asentarse. Bombear un
  // puñado de frames alcanza para que se resuelvan las consultas a la base
  // (`_verificar()`, `cargarTodo()`), que no dependen de ningún timer real.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// El tema automático corre un `Timer.periodic` mientras `LaPlazoletaApp`
/// esté montado (main.dart) — hay que desmontarlo explícitamente al final
/// de cada test, dentro del propio cuerpo del test: `addTearDown` corre
/// demasiado tarde, después de que el framework ya revisó que no queden
/// timers pendientes.
///
/// El segundo `pump()` no es cosmético: al cancelar el `StreamBuilder` que
/// mira `configuracionTabla`, drift agenda un timer de limpieza propio
/// (`StreamQueryStore.markAsClosed`) que solo corre en el frame siguiente —
/// sin ese segundo pump, el framework lo ve como "timer pendiente" y hace
/// fallar el test aunque la app ya esté completamente desmontada.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  testWidgets(
    'sin sesión abierta: arranca directo en Venta con "Abrir caja", sin diálogo forzado, con el resto navegable',
    (tester) async {
      await _pump(tester, db);

      // Nada de diálogo modal sin salida tapando la pantalla.
      expect(find.byType(Dialog), findsNothing);
      // Venta es la raíz (El dueño, 2026-10-03): sin sesión muestra su propio estado, con el botón para abrir.
      expect(find.text('Caja cerrada.'), findsOneWidget);
      expect(find.text('Abrir caja'), findsOneWidget);
      // El resto de la navegación (el dropdown de secciones de la navbar)
      // sigue disponible: se puede ir a Configuración sin haber abierto
      // caja. La navbar pasó a ser un solo botón que abre un menú (El dueño,
      // rediseño 2026-09-25) — ya no hay un ícono con tooltip propio por
      // sección, alcanza con que el botón que abre ese menú exista.
      expect(find.byType(NavbarSuperior), findsOneWidget);

      await _desmontar(tester);
    },
  );

  testWidgets(
    'sesión abierta hoy: arranca directo en Venta lista para vender, sin pasar por "Caja cerrada"',
    (tester) async {
      await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db);

      expect(find.text('Caja cerrada.'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Vender'), findsOneWidget);

      await _desmontar(tester);
    },
  );

  testWidgets(
    'sesión abierta de un día anterior: arranca igual, sin diálogo forzado — el bloqueo de vender es cosa de Venta',
    (tester) async {
      await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
              fechaApertura: Value(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
            ),
          );

      await _pump(tester, db);

      // Nada de pantalla completa sin salida — Dashboard no sabe (ni le
      // importa) si la sesión es "vencida" (Regla 5): eso lo resuelve Venta
      // sola en cuanto se entra a vender, no bloquea llegar hasta acá.
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.text('Caja cerrada. Todavía no hay nada del día que resumir.'),
        findsNothing,
      );
      // El resto de la navegación sigue disponible (ver el comentario del
      // primer test — la navbar es un dropdown de un solo botón).
      expect(find.byType(NavbarSuperior), findsOneWidget);

      await _desmontar(tester);
    },
  );
}
