// Prueba real de punta a punta del motor de sync por Firestore (fase 2,
// "cómo hacemos con las sync" — Bruno, 2026-09-18): dos bases SQLite
// independientes (simulan escritorio y celular), cada una con su propia
// `SincronizacionFirestore`, sincronizando de verdad contra el Firestore
// Emulator Suite (nunca contra el proyecto real — `useFirestoreEmulator`/
// `useAuthEmulator`, ver `firebase.json`/`firestore.rules` en la raíz del
// proyecto). Es un `integration_test` (no un test de widget común) porque
// necesita el plugin real de `cloud_firestore`/`firebase_auth`, que no
// existe en el entorno de `flutter test` normal.
//
// Cómo correrla: con los emuladores levantados
// (`firebase emulators:start --only firestore,auth --project demo-la-plazoleta`),
// `flutter test integration_test/sincronizacion_firestore_test.dart -d windows`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/sincronizacion_firestore.dart';
import 'package:la_plazoleta/firebase_options.dart';
import '../test/helpers/base_para_tests.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Este test crea dos `AppDatabase` a propósito (simulan escritorio y
    // celular) — el warning de drift sobre "múltiples bases" no aplica acá,
    // son dos `NativeDatabase.memory()` totalmente independientes.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.windows);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);

    // El emulador de Auth acepta crear cualquier cuenta nueva sin
    // verificación real — nunca toca la cuenta de Google real de Bruno.
    // Tiene que ser este email exacto: es el único que autoriza
    // `firestore.rules`.
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'gtalovergamer@gmail.com',
        password: 'clave-de-prueba-123',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code != 'email-already-in-use') rethrow;
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'gtalovergamer@gmail.com',
        password: 'clave-de-prueba-123',
      );
    }
  });

  testWidgets('una fila creada en una base aparece en la otra, vía Firestore', (tester) async {
    final dbEscritorio = baseDeTest();
    final dbCelular = baseDeTest();
    addTearDown(dbEscritorio.close);
    addTearDown(dbCelular.close);

    final syncEscritorio = SincronizacionFirestore(dbEscritorio, intervaloEmpuje: const Duration(seconds: 1));
    final syncCelular = SincronizacionFirestore(dbCelular, intervaloEmpuje: const Duration(seconds: 1));
    addTearDown(syncEscritorio.detener);
    addTearDown(syncCelular.detener);

    await syncEscritorio.iniciar();
    await syncCelular.iniciar();

    // Nombre único por corrida — el emulador puede acumular datos de una
    // corrida anterior si no se reinició entre medio.
    final nombre = 'Categoría de prueba ${DateTime.now().microsecondsSinceEpoch}';
    await dbEscritorio.into(dbEscritorio.categorias).insert(
      CategoriasCompanion.insert(
        nombre: nombre,
        globalId: Value(generarGlobalId()),
        origenDispositivo: const Value('desktop'),
        actualizadoEn: Value(DateTime.now()),
      ),
    );

    // Push (escritorio → Firestore) y pull (Firestore → celular) son los
    // dos pasos reales que hay que esperar — nada de `pump` alcanza acá,
    // son ciclos de red de verdad contra el emulador.
    final encontrada = await _esperarHasta(() async {
      final filas = await (dbCelular.select(
        dbCelular.categorias,
      )..where((c) => c.nombre.equals(nombre))).get();
      return filas.isEmpty ? null : filas.single;
    });

    expect(encontrada, isNotNull);
    expect(encontrada!.origenDispositivo, 'desktop');
  });
}

Future<T?> _esperarHasta<T>(
  Future<T?> Function() intentar, {
  Duration timeout = const Duration(seconds: 15),
  Duration entre = const Duration(milliseconds: 300),
}) async {
  final limite = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(limite)) {
    final resultado = await intentar();
    if (resultado != null) return resultado;
    await Future<void>.delayed(entre);
  }
  return null;
}
