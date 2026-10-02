// Sync instantánea por wifi, del lado del celular (El dueño, 2026-09-28:
// "hagamos 100% fluida y efectiva la sync mediante wifi" — hubo que cerrar
// y abrir la app para que el celular se enterara de una caja abierta en la
// PC).
//
// Deja abierta una conexión con `/companion/eventos` de la PC (Server-Sent
// Events): cada vez que la base de la PC cambia llega una línea, y acá se
// baja lo nuevo con la sync que ya existía (`sincronizarConPc`, las mismas
// `cambiosDesde`/`aplicarCambios` de siempre) y se avisa por
// [avisosCambiosCompanion] para que las pantallas se refresquen solas.
// También empuja al momento lo que el celular escribe en su base local
// (tildar una separación, algo cargado sin la PC).
//
// Si la conexión se corta (la PC se cerró, el celular salió del wifi) se
// reintenta sola, cada vez un poco más espaciado (hasta 10 s); al volver,
// sincroniza de una por si algo cambió mientras tanto.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show TableUpdate;

import '../data/database.dart';
import '../data/repositorio_sincronizacion.dart' show tablasSincronizables;
import 'cambios_companion.dart';
import 'cliente_companion.dart';
import 'servicio_sincronizacion.dart';

class EscuchaPc {
  EscuchaPc(this.conexion, this.db, {this.alCambiarConexion});

  final DatosConexion conexion;
  final AppDatabase db;

  /// Se llama cada vez que la conexión con la PC se abre o se corta (`true` = conectada). Con eso el celular decide
  /// solo si trabaja contra la PC o contra la nube (`conmutador_sync.dart`).
  void Function(bool conectada)? alCambiarConexion;

  HttpClient? _http;
  StreamSubscription<String>? _lineas;
  StreamSubscription<Set<TableUpdate>>? _escriturasLocales;
  Timer? _reintento;
  Timer? _esperaSync;
  bool _activa = false;
  int _intentos = 0;

  /// Si la conexión con la PC está viva ahora mismo.
  bool _conectada = false;
  bool get conectada => _conectada;
  set conectada(bool valor) {
    if (_conectada == valor) return;
    _conectada = valor;
    alCambiarConexion?.call(valor);
  }

  void iniciar() {
    if (_activa) return;
    _activa = true;
    _escriturasLocales = db.tableUpdates().listen((cambios) {
      if (cambios.any((c) => tablasSincronizables.containsKey(c.table))) _pedirSync();
    });
    _conectar();
  }

  void detener() {
    _activa = false;
    conectada = false;
    _reintento?.cancel();
    _esperaSync?.cancel();
    _lineas?.cancel();
    _escriturasLocales?.cancel();
    _http?.close(force: true);
    _http = null;
  }

  /// Volver del segundo plano: Android pudo haber cortado la conexión.
  void reconectarSiHaceFalta() {
    if (!_activa || conectada) return;
    _reintento?.cancel();
    _conectar();
  }

  Future<void> _conectar() async {
    if (!_activa) return;
    try {
      _http?.close(force: true);
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      _http = http;
      final pedido = await http.getUrl(
        Uri(scheme: 'http', host: conexion.ip, port: conexion.puerto, path: '/companion/eventos'),
      );
      pedido.headers.set('X-Companion-Token', conexion.token);
      pedido.headers.set('accept', 'text/event-stream');
      final respuesta = await pedido.close();
      if (respuesta.statusCode != 200) {
        await respuesta.drain<void>();
        throw HttpException('eventos: ${respuesta.statusCode}');
      }
      conectada = true;
      _intentos = 0;
      // Recién conectado (o reconectado): puede haber cambios de mientras
      // no había conexión.
      _pedirSync();
      _lineas = respuesta
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (linea) {
              if (linea.startsWith('data:')) _pedirSync();
            },
            onDone: _alCortarse,
            onError: (_) => _alCortarse(),
            cancelOnError: true,
          );
    } catch (_) {
      _alCortarse();
    }
  }

  void _alCortarse() {
    conectada = false;
    _lineas?.cancel();
    _lineas = null;
    if (!_activa) return;
    _intentos++;
    final espera = Duration(seconds: _intentos.clamp(1, 10));
    _reintento?.cancel();
    _reintento = Timer(espera, _conectar);
  }

  /// Varios avisos casi juntos (una venta toca cinco tablas) → una sola
  /// sincronización.
  void _pedirSync() {
    _esperaSync?.cancel();
    _esperaSync = Timer(const Duration(milliseconds: 80), () async {
      final hubo = await sincronizarConPc(ClienteCompanion(conexion), db: db);
      if (hubo) avisarCambiosCompanion();
    });
  }
}

/// Una sola por proceso (la arranca `PantallaMenuCompanion` con la PC
/// emparejada).
EscuchaPc? escuchaPcCompanion;
