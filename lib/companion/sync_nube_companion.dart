// El armado real de la sync por la nube en el celular: dónde se guarda la cuenta, contra qué base sincroniza y
// cómo se decide entre la PC y la nube (`conmutador_sync.dart`). Una sola por proceso, como `escuchaPcCompanion`.
//
// La base es la misma que ya usa la companion (`baseLocalCompanion`): todo lo que el celular escribe sin la PC
// queda ahí, y de ahí sale hacia la nube; lo que llega de otros dispositivos entra ahí y las pantallas se
// refrescan con el mismo aviso que usa la sync por wifi.

import '../servicios/catalogo_bot_nube.dart';
import '../servicios/turnos_bot_nube.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/repositorio_sincronizacion.dart' show tablasSincronizables;
import '../servicios/cuenta_nube.dart';
import '../servicios/sync_nube.dart';
import '../servicios/avisos_mp_servicio.dart';
import 'base_local.dart';
import 'cambios_companion.dart';
import 'conmutador_sync.dart';
import 'elegir_sucursal.dart';
import 'google_en_celular.dart';
import 'identidad_dispositivo.dart';
import '../servicios/almacenes_del_equipo.dart';
import '../servicios/registro_errores.dart';
import '../servicios/vincular_web.dart';
import '../plataforma.dart';
import '../edicion.dart';

class SyncNubeCompanion {
  SyncNubeCompanion({
    required this.almacen,
    required this.cliente,
    required this.servicio,
    required this.almacenEstado,
    required this.conmutador,
    required this.abrirNavegador,
    this.pedirCuentaGoogle = pedirCuentaGoogleDelTelefono,
  });

  final AlmacenCuenta almacen;
  final ClienteNube cliente;
  final ServicioSyncNube servicio;
  final AlmacenEstadoSync almacenEstado;
  final ConmutadorSync conmutador;
  final Future<void> Function(Uri) abrirNavegador;
  final PedirCuentaGoogle pedirCuentaGoogle;

  Future<CuentaVinculada?> cuenta() => almacen.leer();

  /// Vincula este celular a la cuenta de Google (abre el navegador, como en la PC). Lanza [ErrorNube] si no se
  /// completa. Al terminar, el conmutador vuelve a decidir: sin PC, la nube arranca sola.
  Future<CuentaVinculada> vincular({required String nombre}) async {
    // En el navegador no hay servidor local: se va a la página del sitio y vuelve con el código (`vincular_web.dart`).
    if (kIsWeb) await empezarVinculacionWeb(idDispositivo: await idDispositivoEstable(), nombre: nombre);
    final cuenta = await vincularEstaPc(
      cliente: cliente,
      almacen: almacen,
      idDispositivo: await idDispositivoEstable(),
      nombre: nombre,
      abrirNavegador: abrirNavegador,
      celular: true,
    );
    // Un registro de otra vinculación no vale para esta cuenta.
    await almacenEstado.borrar();
    conmutador.reevaluar();
    return cuenta;
  }

  /// Entra con la cuenta de Google elegida en el teléfono, sin navegador. Si la persona puede entrar en más de un negocio o
  /// sucursal (o [elegirSiempre], agregando otro negocio al celular), [elegir] le pregunta en cuál, o el nombre de uno nuevo.
  /// Null si cerró el selector o no eligió. Lanza [GoogleNoDisponible] si el teléfono o el sitio no lo permiten (la pantalla
  /// ofrece el navegador) y [ErrorNube] si el sitio dice que no.
  Future<CuentaVinculada?> entrarConGoogle({
    required String nombre,
    required Future<EleccionDeNegocio?> Function(List<SucursalParaElegir> opciones) elegir,
    bool elegirSiempre = false,
  }) async {
    final clientId = await cliente.clienteGoogle();
    if (clientId == null) throw const GoogleNoDisponible('el sitio todavía no lo ofrece');
    final idToken = await pedirCuentaGoogle(clientId);
    if (idToken == null) return null;
    final idDispositivo = await idDispositivoEstable();
    var r = await _sinRutaEsNoDisponible(
      () => cliente.entrarConGoogle(idToken: idToken, idDispositivo: idDispositivo, nombre: nombre, elegirSiempre: elegirSiempre),
    );
    if (r is HayQueElegirSucursal) {
      final eleccion = await elegir(r.opciones);
      if (eleccion == null) return null;
      r = await cliente.entrarConGoogle(
        idToken: idToken,
        idDispositivo: idDispositivo,
        nombre: nombre,
        negocio: eleccion is EligioSucursal ? eleccion.opcion.negocio : null,
        sucursal: eleccion is EligioSucursal ? eleccion.opcion.sucursal : null,
        nuevoNegocio: eleccion is CrearNegocio ? eleccion.nombre : null,
      );
    }
    if (r is! EntroConGoogle) throw const ErrorNube('google_invalido', 'No se pudo entrar en ese negocio. Probá de nuevo.');
    await almacen.guardar(r.cuenta);
    // Un registro de otra vinculación no vale para esta cuenta (igual que [vincular]).
    await almacenEstado.borrar();
    conmutador.reevaluar();
    return r.cuenta;
  }

  /// Un sitio que todavía no tiene la entrada con Google (404/405): para la pantalla es lo mismo que un teléfono sin Google,
  /// se ofrece el navegador.
  Future<T> _sinRutaEsNoDisponible<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ErrorNube catch (e) {
      if (e.estado == 404 || e.estado == 405) throw GoogleNoDisponible('el sitio todavía no lo ofrece (${e.estado})');
      rethrow;
    }
  }

  Future<void> desvincular() async {
    servicio.detener();
    await almacen.borrar();
    await almacenEstado.borrar();
    conmutador.reevaluar();
  }
}

SyncNubeCompanion? syncNubeCompanion;

/// Arma la sync una sola vez. [db] es solo para tests; en la app real es la base local del celular.
SyncNubeCompanion armarSyncNubeCompanion({
  required AlmacenCuenta almacen,
  required AlmacenEstadoSync almacenEstado,
  required ClienteNube cliente,
  required Future<void> Function(Uri) abrirNavegador,
  required AppDatabase db,
  Duration esperaTraspaso = const Duration(seconds: 10),
  PedirCuentaGoogle pedirCuentaGoogle = pedirCuentaGoogleDelTelefono,
}) {
  final servicio = ServicioSyncNube(
    db: db,
    almacenCuenta: almacen,
    cliente: cliente,
    almacenEstado: almacenEstado,
    alAplicarBajada: avisarCambiosCompanion,
    // Cuando el celular sube a la nube (sin PC), publica también el catálogo del bot de WhatsApp (si el negocio lo tiene).
    alTerminarVuelta: _alTerminarVuelta(db, cliente),
  );
  final conmutador = ConmutadorSync(
    hayCuenta: () async => await almacen.leer() != null,
    iniciarNube: () => servicio.iniciar(cambiosLocales: _escriturasLocales(db)),
    detenerNube: servicio.detener,
    esperaTraspaso: esperaTraspaso,
  );
  return SyncNubeCompanion(
    almacen: almacen,
    cliente: cliente,
    servicio: servicio,
    almacenEstado: almacenEstado,
    conmutador: conmutador,
    abrirNavegador: abrirNavegador,
    pedirCuentaGoogle: pedirCuentaGoogle,
  );
}

/// Al terminar cada vuelta de subida, el bot de WhatsApp (si el negocio lo tiene): el catálogo (comercios) y los turnos de la
/// Agenda (servicios). Los dos se fijan solos si les toca.
Future<void> Function(String token) _alTerminarVuelta(AppDatabase db, ClienteNube cliente) {
  final catalogo = PublicadorCatalogoBot(db: db, cliente: cliente);
  final turnos = SincronizadorTurnosBot(db: db, cliente: cliente, alBajar: avisarCambiosCompanion);
  return (token) async {
    await catalogo.publicarSiHaceFalta(token);
    await turnos.vuelta(token);
  };
}

/// Un aviso por cada escritura local en una tabla que se sincroniza (el servicio las agrupa).
Stream<void> _escriturasLocales(AppDatabase db) => db
    .tableUpdates()
    .where((cambios) => cambios.any((c) => tablasSincronizables.containsKey(c.table)))
    .map((_) {});

/// La de la app real. Se arma la primera vez que se pide.
Future<SyncNubeCompanion> syncNubeDelCelular() async {
  final existente = syncNubeCompanion;
  if (existente != null) return existente;
  final almacen = await almacenCuentaDelEquipo();
  final almacenEstado = await almacenEstadoSyncDelEquipo();
  final cliente = ClienteNube(http: http.Client());
  if (kIsWeb) {
    // Volviendo de entrar con Google (Nodo Sur Servicios web): se termina acá, antes de que nadie pregunte si hay cuenta. Si el
    // código ya no sirve, la pantalla de entrar ofrece entrar de nuevo.
    try {
      if (await terminarVinculacionWeb(url: Uri.base, cliente: cliente, almacen: almacen, nombre: nombreDelCelular()) != null) {
        await almacenEstado.borrar();
      }
    } catch (e, st) {
      unawaited(registrarSiNoEsDeRed('Terminar de entrar desde el navegador', e, st));
    }
  }
  if (syncNubeCompanion != null) return syncNubeCompanion!;
  return syncNubeCompanion = armarSyncNubeCompanion(
    almacen: almacen,
    almacenEstado: almacenEstado,
    cliente: cliente,
    abrirNavegador: (url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const ErrorNube('sin_navegador', 'No se pudo abrir el navegador.');
      }
    },
    db: baseLocalCompanion(),
  );
}

/// Nombre con el que este celular aparece en "Mis dispositivos" del sitio.
String nombreDelCelular() => kIsWeb ? 'Navegador' : esEscritorioServicios ? 'Compu ($nombreDelSistema)' : 'Celular ($nombreDelSistema)';

/// Avisos de Mercado Pago del celular (El dueño, 2026-10-09: independizar el celular): el mismo servicio de la PC, sobre la base
/// del celular y con su cuenta vinculada. Se arma una sola vez.
ServicioAvisosMp? avisosMpCompanion;

Future<ServicioAvisosMp> avisosMpDelCelular() async {
  final existente = avisosMpCompanion;
  if (existente != null) return existente;
  final sync = await syncNubeDelCelular();
  return avisosMpCompanion ??= ServicioAvisosMp(db: baseLocalCompanion(), almacen: sync.almacen, cliente: sync.cliente);
}
