// Actualización automática de la app de escritorio (2026-09-30).
//
// Dos piezas a propósito separadas:
//
//  1. DETECCIÓN, propia y silenciosa: la app baja el feed con `http`, lo
//     compara con su versión y, si hay una más nueva, lo guarda para
//     avisar. No usa WinSparkle para esto porque en WinSparkle 0.8.1
//     `check_update_without_ui` NO es silencioso: si hay una versión nueva
//     abre su ventana, y eso interrumpiría una venta (spike 2026-09-30,
//     `DECISIONES.md`).
//  2. INSTALACIÓN, WinSparkle (paquete `auto_updater`), solo cuando alguien
//     lo pide: descarga, verifica la firma DSA contra la clave pública
//     embebida en el .exe y corre el instalador.
//
// Nada de esto toca la base: el instalador (`installer/`) tampoco.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/identidad_sync.dart';
import '../domain/actualizacion.dart';

const _claveIdCliente = 'actualizaciones_cid';

/// Cada cuánto se vuelve a mirar el feed mientras la app sigue abierta (el
/// local la deja prendida todo el día).
const Duration intervaloRevision = Duration(hours: 6);

/// Id aleatorio de esta instalación para el despliegue gradual del servidor.
/// Se genera UNA vez y se guarda: si cambiara en cada arranque, el reparto
/// por porcentaje dejaría de ser estable y una misma PC entraría y saldría
/// del despliegue.
Future<String> idClienteActualizaciones() async {
  final prefs = await SharedPreferences.getInstance();
  final existente = prefs.getString(_claveIdCliente);
  if (existente != null && existente.isNotEmpty) return existente;
  final nuevo = generarGlobalId();
  await prefs.setString(_claveIdCliente, nuevo);
  return nuevo;
}

/// Nombre y build de la app que está corriendo, normalizados (ver
/// [separarVersion]).
Future<({String nombre, String build})> leerVersionApp() async {
  final info = await PackageInfo.fromPlatform();
  return separarVersion(info.version, info.buildNumber);
}

/// "1.0.0+2098", para mostrar (Configuración).
Future<String> textoVersionApp() async {
  final v = await leerVersionApp();
  return v.build.isEmpty ? v.nombre : '${v.nombre}+${v.build}';
}

class ServicioActualizaciones extends ChangeNotifier {
  ServicioActualizaciones({
    required this.cliente,
    required this.versionActual,
    required this.ventaAbierta,
    required this.abrirInstalador,
    this.reloj = DateTime.now,
  }) {
    ventaAbierta.addListener(notifyListeners);
  }

  final http.Client cliente;

  /// Versión de la app en el formato del feed ("1.0.0.2098").
  final Future<String> Function() versionActual;

  /// Verdadero mientras hay una venta en curso en Venta.
  final ValueListenable<bool> ventaAbierta;

  /// Abre la interfaz de WinSparkle para el feed dado (`actualizador_nativo`).
  final Future<void> Function(String urlFeed) abrirInstalador;

  final DateTime Function() reloj;

  /// Sin internet no tiene que colgar nada ni quedar esperando.
  Duration tiempoLimite = const Duration(seconds: 15);

  Timer? _timerRevision;
  Timer? _timerPostergacion;
  String? _versionDisponible;
  DateTime? _postergadaHasta;
  bool _revisando = false;

  /// La versión más nueva que anuncia el feed, o null si está al día o si
  /// todavía no se pudo revisar.
  String? get versionDisponible => _versionDisponible;

  bool get mostrarAviso =>
      decidirAviso(
        hayActualizacion: _versionDisponible != null,
        hayVentaAbierta: ventaAbierta.value,
        postergadaHasta: _postergadaHasta,
        ahora: reloj(),
      ) ==
      AvisoActualizacion.mostrar;

  /// Revisa al arrancar y cada [intervaloRevision]. No bloquea nada.
  void iniciar() {
    unawaited(revisar());
    _timerRevision ??= Timer.periodic(intervaloRevision, (_) => revisar());
  }

  /// Mira el feed. Falla en silencio — la app es offline, sin internet no
  /// hay nada que mostrar —, y una falla no borra una actualización que ya
  /// se había detectado.
  Future<void> revisar() async {
    if (_revisando) return;
    _revisando = true;
    try {
      final actual = await versionActual();
      final respuesta = await cliente.get(Uri.parse(await _urlFeed())).timeout(tiempoLimite);
      if (respuesta.statusCode != 200) return;
      final cuerpo = respuesta.body;
      _versionDisponible = hayActualizacion(versionActual: actual, xmlFeed: cuerpo)
          ? versionMasNuevaDelFeed(cuerpo)
          : null;
      notifyListeners();
    } catch (error) {
      debugPrint('Actualizaciones: no se pudo revisar ($error)');
    } finally {
      _revisando = false;
    }
  }

  /// "Más tarde": silencia el aviso un rato. Solo en memoria — al volver a
  /// abrir la app se vuelve a avisar, que es lo esperable.
  void postergar() {
    _postergadaHasta = reloj().add(postergacionAviso);
    _timerPostergacion?.cancel();
    _timerPostergacion = Timer(postergacionAviso, notifyListeners);
    notifyListeners();
  }

  /// Abre WinSparkle, que descarga, verifica la firma y corre el instalador.
  /// Solo se llama desde un botón: la app nunca instala sola.
  Future<void> instalarAhora() async => abrirInstalador(await _urlFeed());

  Future<String> _urlFeed() async =>
      urlFeedActualizaciones(idCliente: await idClienteActualizaciones());

  @override
  void dispose() {
    ventaAbierta.removeListener(notifyListeners);
    _timerRevision?.cancel();
    _timerPostergacion?.cancel();
    super.dispose();
  }
}

/// El servicio de la app real (`main.dart`). Es null en los tests de widget,
/// que pumpean la app sin pasar por `main()` — mismo patrón que
/// `notificadorCambios`.
ServicioActualizaciones? servicioActualizaciones;
