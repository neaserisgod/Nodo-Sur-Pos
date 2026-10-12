// Dónde guarda este equipo su cuenta de Nodo Sur y el registro de la sync. En la PC y el celular, archivos JSON en la carpeta de
// datos de la app (como siempre). En el navegador (Nodo Sur Servicios web, `docs/PLAN-WEB-SERVICIOS.md`) no hay archivos: van al
// almacenamiento del navegador (`shared_preferences`, que en web es `localStorage`). Un solo lugar decide, así ninguna pantalla
// arma su propio almacén con una carpeta que en el navegador no existe.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cuenta_nube.dart';
import '../data/registro_sync_nube.dart' show EstadoSyncNube;
import 'sync_nube.dart';

Future<AlmacenCuenta> almacenCuentaDelEquipo() async =>
    kIsWeb ? AlmacenCuentaEnPreferencias() : AlmacenCuentaEnArchivo((await getApplicationSupportDirectory()).path);

Future<AlmacenEstadoSync> almacenEstadoSyncDelEquipo() async =>
    kIsWeb ? AlmacenEstadoSyncEnPreferencias() : AlmacenEstadoSyncEnArchivo((await getApplicationSupportDirectory()).path);

/// La cuenta en las preferencias. Un valor roto o ausente es "sin vincular", nunca un error (igual que el archivo).
class AlmacenCuentaEnPreferencias implements AlmacenCuenta {
  static const clave = 'nodosur_cuenta';

  @override
  Future<CuentaVinculada?> leer() async {
    try {
      final texto = (await SharedPreferences.getInstance()).getString(clave);
      return texto == null ? null : CuentaVinculada.desdeJson(jsonDecode(texto));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar(CuentaVinculada cuenta) async =>
      (await SharedPreferences.getInstance()).setString(clave, jsonEncode(cuenta.toJson()));

  @override
  Future<void> borrar() async => (await SharedPreferences.getInstance()).remove(clave);
}

/// El registro de la sync en las preferencias. Roto o ausente: se arranca de cero (vuelve a bajar todo, sin duplicar nada).
class AlmacenEstadoSyncEnPreferencias implements AlmacenEstadoSync {
  static const clave = 'nodosur_sync';

  @override
  Future<EstadoSyncNube> leer() async {
    try {
      final texto = (await SharedPreferences.getInstance()).getString(clave);
      return EstadoSyncNube.desdeJson(texto == null ? null : jsonDecode(texto));
    } catch (_) {
      return EstadoSyncNube();
    }
  }

  @override
  Future<void> guardar(EstadoSyncNube estado) async =>
      (await SharedPreferences.getInstance()).setString(clave, jsonEncode(estado.toJson()));

  @override
  Future<void> borrar() async => (await SharedPreferences.getInstance()).remove(clave);
}
