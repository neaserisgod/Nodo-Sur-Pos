// El armado real de la sync por la nube en el celular: dónde se guarda la cuenta, contra qué base sincroniza y
// cómo se decide entre la PC y la nube (`conmutador_sync.dart`). Una sola por proceso, como `escuchaPcCompanion`.
//
// La base es la misma que ya usa la companion (`baseLocalCompanion`): todo lo que el celular escribe sin la PC
// queda ahí, y de ahí sale hacia la nube; lo que llega de otros dispositivos entra ahí y las pantallas se
// refrescan con el mismo aviso que usa la sync por wifi.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/repositorio_sincronizacion.dart' show tablasSincronizables;
import '../servicios/cuenta_nube.dart';
import '../servicios/sync_nube.dart';
import '../servicios/avisos_mp_servicio.dart';
import 'base_local.dart';
import 'cambios_companion.dart';
import 'conmutador_sync.dart';
import 'identidad_dispositivo.dart';

class SyncNubeCompanion {
  SyncNubeCompanion({
    required this.almacen,
    required this.cliente,
    required this.servicio,
    required this.almacenEstado,
    required this.conmutador,
    required this.abrirNavegador,
  });

  final AlmacenCuenta almacen;
  final ClienteNube cliente;
  final ServicioSyncNube servicio;
  final AlmacenEstadoSync almacenEstado;
  final ConmutadorSync conmutador;
  final Future<void> Function(Uri) abrirNavegador;

  Future<CuentaVinculada?> cuenta() => almacen.leer();

  /// Vincula este celular a la cuenta de Google (abre el navegador, como en la PC). Lanza [ErrorNube] si no se
  /// completa. Al terminar, el conmutador vuelve a decidir: sin PC, la nube arranca sola.
  Future<CuentaVinculada> vincular({required String nombre}) async {
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
}) {
  final servicio = ServicioSyncNube(
    db: db,
    almacenCuenta: almacen,
    cliente: cliente,
    almacenEstado: almacenEstado,
    alAplicarBajada: avisarCambiosCompanion,
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
  );
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
  final soporte = await getApplicationSupportDirectory();
  return syncNubeCompanion ??= armarSyncNubeCompanion(
    almacen: AlmacenCuentaEnArchivo(soporte.path),
    almacenEstado: AlmacenEstadoSyncEnArchivo(soporte.path),
    cliente: ClienteNube(http: http.Client()),
    abrirNavegador: (url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const ErrorNube('sin_navegador', 'No se pudo abrir el navegador.');
      }
    },
    db: baseLocalCompanion(),
  );
}

/// Nombre con el que este celular aparece en "Mis dispositivos" del sitio.
String nombreDelCelular() => 'Celular (${Platform.operatingSystem})';

/// Avisos de Mercado Pago del celular (El dueño, 2026-10-09: independizar el celular): el mismo servicio de la PC, sobre la base
/// del celular y con su cuenta vinculada. Se arma una sola vez.
ServicioAvisosMp? avisosMpCompanion;

Future<ServicioAvisosMp> avisosMpDelCelular() async {
  final existente = avisosMpCompanion;
  if (existente != null) return existente;
  final sync = await syncNubeDelCelular();
  return avisosMpCompanion ??= ServicioAvisosMp(db: baseLocalCompanion(), almacen: sync.almacen, cliente: sync.cliente);
}
