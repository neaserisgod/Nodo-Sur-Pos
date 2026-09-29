// Transporte por Firestore — reemplaza el HTTP celular↔PC
// (`servidor_companion.dart`/`cliente_companion.dart`) como intermediario
// para las 14 tablas sincronizables. No decide NADA de merge acá: eso sigue
// viviendo en `repositorio_sincronizacion.dart` (`cambiosDesde`/
// `aplicarCambios`), que ya es 100% transporte-agnóstico — trabaja con
// `Map<String, dynamic>` en snake_case, exactamente lo que un documento de
// Firestore da y recibe. Esto solo sabe llevar filas de/hacia Firestore.
//
// En Windows usa `firebase_rest_escritorio.dart` (HTTP puro) en vez del
// plugin nativo `cloud_firestore`: el plugin nativo de `firebase_auth` en
// Windows tiene un bug real (no emite un ID token utilizable después de
// loguearse — ver el comentario de cabecera de ese archivo), y sin token
// válido Firestore rechaza todo. La companion Android sigue con el plugin
// nativo tal cual (esa plataforma no tiene este bug).
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' as native;

import 'firebase_rest_escritorio.dart' as rest;

/// Negocio único — Bruno no tiene (ni va a tener) más de un local, así que
/// un id fijo alcanza en vez de generar/coordinar uno entre dispositivos.
const negocioIdFirestore = 'la-plazoleta';

native.CollectionReference<Map<String, dynamic>> _coleccionNativa(String tabla) =>
    native.FirebaseFirestore.instance.collection('negocios/$negocioIdFirestore/$tabla');

/// Handle genérico de una suscripción activa (listener nativo en Android,
/// sondeo periódico por REST en Windows) — a quien llama solo le importa
/// poder cancelarla, nunca le importa cuál de los dos es.
class SuscripcionFirestore {
  SuscripcionFirestore._(this._cancelar);
  final void Function() _cancelar;
  void cancel() => _cancelar();
}

/// Sube [filas] a Firestore, una por documento con `global_id` como id del
/// documento — así un reintento después de una falla parcial nunca duplica
/// nada (vuelve a escribir el mismo documento, no uno nuevo).
Future<void> subirFilasAFirestore(String tabla, List<Map<String, dynamic>> filas) async {
  if (filas.isEmpty) return;
  if (Platform.isWindows) {
    final sesion = rest.sesionRestActual;
    if (sesion == null) return; // sin sesión: no hay a nombre de quién escribir
    await rest.subirFilasRest(sesion, tabla, filas);
    return;
  }
  await _subirFilasNativo(tabla, filas);
}

/// Firestore rechaza un batch de más de 500 operaciones — un margen de
/// seguridad, no el límite exacto, para dejar lugar a que cada operación
/// cuente más de una "escritura" en casos que no controlamos nosotros.
const _maximoOperacionesPorLote = 450;

Future<void> _subirFilasNativo(String tabla, List<Map<String, dynamic>> filas) async {
  final coleccion = _coleccionNativa(tabla);
  for (var inicio = 0; inicio < filas.length; inicio += _maximoOperacionesPorLote) {
    final tanda = filas.skip(inicio).take(_maximoOperacionesPorLote);
    final batch = native.FirebaseFirestore.instance.batch();
    for (final fila in tanda) {
      batch.set(coleccion.doc(fila['global_id'] as String), fila);
    }
    await batch.commit();
  }
}

/// Escucha cambios de [tabla]. En Android es un listener nativo en tiempo
/// real (`snapshots()` — el primer evento ya trae todo lo que existía al
/// suscribirse, así que sirve de pull inicial Y de escucha en vivo). En
/// Windows es un sondeo periódico con cursor propio
/// (`descargarCambiosRest`, guarda su avance en SharedPreferences) — sin
/// listener nativo disponible, pero el costo en lecturas sigue siendo
/// proporcional a lo que cambió, no al tamaño total de la base.
SuscripcionFirestore escucharTablaFirestore(String tabla, void Function(List<Map<String, dynamic>> filas) alCambiar) {
  if (Platform.isWindows) {
    Timer? timer;
    Future<void> unaVuelta() async {
      final sesion = rest.sesionRestActual;
      if (sesion == null) return;
      try {
        final filas = await rest.descargarCambiosRest(sesion, tabla);
        if (filas.isNotEmpty) alCambiar(filas);
      } catch (_) {
        // Sin internet, token vencido sin poder renovar, lo que sea — se
        // reintenta solo en la próxima vuelta (el cursor no avanzó).
      }
    }

    unaVuelta();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => unaVuelta());
    return SuscripcionFirestore._(() => timer?.cancel());
  }

  final sub = _coleccionNativa(tabla).snapshots().listen((snapshot) {
    final filas = [
      for (final cambio in snapshot.docChanges)
        if (cambio.type != native.DocumentChangeType.removed) cambio.doc.data()!,
    ];
    if (filas.isNotEmpty) alCambiar(filas);
  }, onError: (Object e) => print('escucharTablaFirestore: $tabla: $e'));
  return SuscripcionFirestore._(sub.cancel);
}

/// Credenciales de cobro por terminal Point (Bruno, 2026-09-18: "quiero que
/// ande sin la PC" — que el celular pueda mandar la orden directo a
/// Mercado Pago) — documento fijo aparte de las 14 tablas, nunca mezclado
/// con el resto de `configuracion_tabla` por ser un token de pago. Solo el
/// escritorio escribe; solo la companion lee.
Future<void> escribirConfigCobro({
  required String? mpAccessToken,
  required String? mpTerminalCobroId,
}) async {
  if (Platform.isWindows) {
    final sesion = rest.sesionRestActual;
    if (sesion == null) return;
    await rest.escribirConfigCobroRest(
      sesion,
      mpAccessToken: mpAccessToken,
      mpTerminalCobroId: mpTerminalCobroId,
    );
    return;
  }
  await native.FirebaseFirestore.instance
      .doc('negocios/$negocioIdFirestore/configuracion/cobro')
      .set({'mp_access_token': mpAccessToken, 'mp_terminal_cobro_id': mpTerminalCobroId});
}

/// Lectura puntual (no un listener en vivo — esta credencial cambia poquísimo,
/// alcanza con leerla fresca cada vez que se va a cobrar por Point). `null`
/// si el documento no existe todavía o si no hay sesión (Windows sin login).
Future<({String? mpAccessToken, String? mpTerminalCobroId})?> leerConfigCobro() async {
  if (Platform.isWindows) {
    final sesion = rest.sesionRestActual;
    if (sesion == null) return null;
    final campos = await rest.leerConfigCobroRest(sesion);
    if (campos == null) return null;
    return (
      mpAccessToken: campos['mp_access_token'] as String?,
      mpTerminalCobroId: campos['mp_terminal_cobro_id'] as String?,
    );
  }
  final doc = await native.FirebaseFirestore.instance
      .doc('negocios/$negocioIdFirestore/configuracion/cobro')
      .get();
  final datos = doc.data();
  if (datos == null) return null;
  return (
    mpAccessToken: datos['mp_access_token'] as String?,
    mpTerminalCobroId: datos['mp_terminal_cobro_id'] as String?,
  );
}
