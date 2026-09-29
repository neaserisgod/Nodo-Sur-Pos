// Inicialización de Firebase para el escritorio, separada de `main.dart`
// para poder llamarla desde más de un lugar sin arriesgar una doble
// inicialización: `main.dart` la dispara en segundo plano al arrancar
// (`CLAUDE.md`, "arranque vs. operación" — nunca bloquea el primer frame de
// Venta) y `ConfiguracionControlador.cargarTodo` la vuelve a pedir antes de
// tocar `FirebaseAuth.instance`, por si la pantalla de Configuración se abre
// más rápido de lo que tardó la de arriba en terminar.
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<void> inicializarFirebaseEscritorio() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.windows);
}
