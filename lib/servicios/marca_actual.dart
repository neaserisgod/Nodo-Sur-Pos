// La marca que se muestra en la app (nombre del comercio, encabezado del
// ticket), siempre al día con la configuración.
//
// Es un aviso global, como `notificadorCambios`: las pantallas que muestran el
// nombre (menú, barra de la ventana, ticket de muestra) lo escuchan sin tener
// que recibir la base. `seguirMarca` lo alimenta desde la base, así un cambio
// hecho en Configuración, o llegado por sincronización, se ve al toque.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repositorio_configuracion.dart';
import '../domain/marca.dart';

/// Vale el nombre del producto hasta que [seguirMarca] lee la base.
final ValueNotifier<MarcaNegocio> marcaActual = ValueNotifier(const MarcaNegocio());

MarcaNegocio _marcaDe(ConfiguracionNegocio? fila) =>
    fila == null ? const MarcaNegocio() : MarcaNegocio(nombreComercio: fila.nombreComercio, encabezadoTicket: fila.encabezadoTicket);

/// Mantiene [marcaActual] igual a lo guardado en la base mientras no se cancele.
StreamSubscription<MarcaNegocio> seguirMarca(AppDatabase db) {
  return db
      .select(db.configuracionNegocioTabla)
      .watchSingleOrNull()
      .map(_marcaDe)
      .listen((marca) => marcaActual.value = marca);
}

/// La marca guardada ahora, para el código que no es una pantalla (armar un
/// ticket, por ejemplo).
Future<MarcaNegocio> marcaDeBase(AppDatabase db) async => _marcaDe(await configuracionNegocioActual(db));
