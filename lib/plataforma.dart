// En qué clase de equipo corre la app. En el navegador (Nodo Sur Servicios web) `Platform` de dart:io no existe y preguntarle
// algo tira un error, así que nadie lo consulta directo: se pregunta acá.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'edicion.dart';

/// La base y la app se comportan como las del celular (base propia que se sincroniza, sin sembrar lo de la PC): en Android, en
/// el navegador y en una edición aparte de Windows (que es la app del celular con ventana de PC, no la PC del almacén).
bool get esEquipoCelular => kIsWeb || Platform.isAndroid || esEdicionAparte;

/// Android de verdad: lo que necesita el sistema del celular (el bot de WhatsApp con Node, las notificaciones). En el navegador no.
bool get esAndroid => !kIsWeb && Platform.isAndroid;

/// El nombre del sistema que se le avisa al sitio ("android", "windows"… o "web").
String get nombreDelSistema => kIsWeb ? 'web' : Platform.operatingSystem;
