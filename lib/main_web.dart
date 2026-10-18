// Nodo Sur Servicios en el navegador (El dueño, 2026-10-12: "la quería funcional desde la web igual que la móvil";
// `docs/PLAN-WEB-SERVICIOS.md`). Es la misma app del celular, edición servicios, siempre en "Solo celular": la base vive en el
// navegador y se sincroniza por la nube con los demás equipos del negocio. El bot de WhatsApp no corre acá (necesita un Android).
// Se compila con `flutter build web -t lib/main_web.dart --base-href /app/` y se sirve en horsepos.com/app/.

import 'dart:async';

import 'package:flutter/material.dart';

import 'companion/companion_app.dart';
import 'companion/demo/demo.dart';
import 'companion/emparejamiento.dart';
import 'companion/modo_uso.dart';
import 'edicion.dart';
import 'servicios/registro_errores.dart';
import 'servicios/sonidos.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    instalarRegistroDeErrores();
    edicionActual = Edicion.servicios;
    // horsepos.com/demo/: la misma app, sin cuenta y con todo en memoria (`companion/demo/demo.dart`).
    if (esDireccionDeDemo(Uri.base)) await prepararDemo();
    // En el navegador no hay PC con la que emparejarse por wifi: siempre "Solo celular", sin preguntar.
    if (await leerModoUso() == null) await guardarModoUso(ModoUso.soloCelular);
    unawaited(sonidos.cargar()); // después de la demo: en la demo las preferencias viven en memoria
    runApp(const CompanionApp());
  }, (error, pila) => registrarError('Error sin capturar (web)', error, pila));
}
