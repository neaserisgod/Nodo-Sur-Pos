// La demo de Nodo Sur Servicios (horsepos.com/demo/, `docs/PLAN-DEMO-SERVICIOS.md`): la misma app del navegador, sin entrar con
// Google y con un negocio de ejemplo ya cargado. Todo vive en memoria: la base y las preferencias. Al cerrar o recargar la
// pestaña se pierde, a propósito (El dueño, 2026-10-12: "siempre de cero"), y nunca pisa lo guardado de horsepos.com/app/,
// que está en el mismo sitio.

import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../data/database.dart';
import '../base_local.dart';
import 'base_demo.dart';

/// true en horsepos.com/demo/. Se fija una sola vez, al arrancar (`main_web.dart`).
bool modoDemo = false;

/// ¿Esta dirección es la de la demo? `/demo` y lo que cuelgue de ahí.
bool esDireccionDeDemo(Uri direccion) => direccion.path == '/demo' || direccion.path.startsWith('/demo/');

/// A dónde lleva "Probar gratis": la prueba de 7 días del plan que incluye Servicios.
const rutaProbarGratis = '/pagar/?plan=emprendedor';

/// Deja la app sin nada guardado en el navegador: preferencias y base en memoria. Va antes de que nada lea o escriba.
Future<void> prepararDemo() async {
  SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final AppDatabase db = await abrirBaseDemo();
  usarBaseLocal(db);
  modoDemo = true;
}
