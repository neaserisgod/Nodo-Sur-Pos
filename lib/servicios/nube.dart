// El armado real de la cuenta de Nodo Sur en la app de escritorio: dónde se guarda el token, contra qué servidor
// se habla y cómo se abre el navegador. Es global (como `servicioActualizaciones`) porque lo usan el arranque, el
// cierre de caja y Configuración; los tests de pantalla le pasan la suya.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/notificador_cambios.dart';
import 'actualizaciones.dart';
import 'copias_nube.dart';
import 'cuenta_nube.dart';
import 'pc_local_nube.dart';
import 'sync_nube.dart';

/// Todo lo de la cuenta de Nodo Sur que necesita una pantalla.
class NubeApp {
  NubeApp({
    required this.almacen,
    required this.cliente,
    required this.copias,
    this.sync,
    required this.idDispositivo,
    required this.nombreDispositivo,
    required this.abrirNavegador,
    required this.carpetaTemporal,
  });

  final AlmacenCuenta almacen;
  final ClienteNube cliente;
  final ServicioCopiasNube copias;

  /// Sincronización con los demás dispositivos de la cuenta, a través de la nube.
  final ServicioSyncNube? sync;
  final Future<String> Function() idDispositivo;
  final String Function() nombreDispositivo;
  final Future<void> Function(Uri) abrirNavegador;
  final Directory carpetaTemporal;

  /// Cambia cuando se vincula, se desvincula o termina una subida, para que la pantalla se refresque.
  final ValueNotifier<int> cambios = ValueNotifier(0);

  /// 'beta' si esta PC recibe las versiones de prueba antes (cuenta de administrador); se sabe al avisar.
  String? canal;

  /// El último intento de subir una copia, para mostrarlo en Configuración.
  ResultadoSubida? ultimoResultado;
  DateTime? ultimoIntento;

  void avisarCambio() => cambios.value++;

  Future<ResultadoSubida> subirCopia() async {
    final r = await copias.subirAhora();
    ultimoResultado = r;
    ultimoIntento = DateTime.now();
    avisarCambio();
    return r;
  }
}

NubeApp? nubeApp;

const _claveUltimaSubida = 'nube_ultima_subida';

/// Arma la cuenta real y deja andando el aviso y la copia diaria. Solo en la app real de escritorio.
Future<NubeApp> iniciarNube(AppDatabase db) async {
  final soporte = await getApplicationSupportDirectory();
  final temporal = Directory(p.join((await getTemporaryDirectory()).path, 'nodosur_copias'));
  final almacen = AlmacenCuentaEnArchivo(soporte.path);
  final cliente = ClienteNube(http: http.Client());
  final copias = ServicioCopiasNube(
    db: db,
    almacen: almacen,
    cliente: cliente,
    carpetaTemporal: temporal,
    versionApp: textoVersionApp,
    leerUltimaSubida: () async {
      final ms = (await SharedPreferences.getInstance()).getInt(_claveUltimaSubida);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    },
    guardarUltimaSubida: (d) async => (await SharedPreferences.getInstance()).setInt(_claveUltimaSubida, d.millisecondsSinceEpoch),
  );
  // Cada cambio en la base sube solo; lo que llega de otro dispositivo se avisa a las pantallas con el mismo canal
  // que usa el celular por wifi (`cambioDelCelular`), así que se refrescan igual.
  final avisos = notificadorCambios ??= NotificadorCambios(db);
  final sync = ServicioSyncNube(
    db: db,
    almacenCuenta: almacen,
    cliente: cliente,
    almacenEstado: AlmacenEstadoSyncEnArchivo(soporte.path),
    alAplicarBajada: avisos.cambioDelCelular,
  );
  final nube = NubeApp(
    almacen: almacen,
    cliente: cliente,
    copias: copias,
    sync: sync,
    idDispositivo: idClienteActualizaciones,
    nombreDispositivo: () => Platform.localHostname,
    abrirNavegador: (url) async {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const ErrorNube('sin_navegador', 'No se pudo abrir el navegador.');
      }
    },
    carpetaTemporal: temporal,
  );
  nubeApp = nube;
  // Avisar que la PC está viva (y renovar el token) al abrir; la copia diaria y los avisos siguen solos.
  unawaited(copias
      .avisarYRenovar(cid: await idClienteActualizaciones(), sistema: Platform.operatingSystem)
      .then((canal) => nube.canal = canal));
  unawaited(avisarPcLocal(db, almacen: almacen, cliente: cliente));
  copias.iniciarCopiaDiaria();
  sync.iniciar(cambiosLocales: avisos.cambiosDeLaBase);
  return nube;
}
