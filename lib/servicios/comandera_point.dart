// La terminal Point como comandera de Nodo Gastro (El dueño, 2026-10-24: "como si fuese una comandera, nada de desarrollar app…
// usar la misma función que tiene almacén"; "cuando un pedido se confirma como tal, debe imprimir la comanda", y los del bot
// también). Es el mismo camino con que el almacén imprime el ticket en la Point (`impresion_posnet_nube.dart`); lo que cambia es
// el texto (`domain/comanda.dart`) y cuándo sale.
//
// Mira la tabla de pedidos en vez de engancharse en cada lugar que confirma, porque un pedido queda "por hacer" por muchos
// caminos: lo carga el local, lo acepta, entra solo del bot, llega pagado por Mercado Pago o baja por la sync desde otro equipo
// (el bot lo puede bajar el celular y la comanda salir en la compu del mostrador). Así no se escapa ninguno.
//
// Se prende por equipo y arranca apagada: con dos equipos prendidos saldría cada comanda dos veces. Lo impreso se anota en el
// equipo (`podarComandas` lo limpia), así abrir la app de nuevo no repite nada.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/repositorio_pedidos_gastronomia.dart' show lineasDe;
import '../domain/comanda.dart';
import '../domain/pedido_gastronomico.dart';
import 'marca_actual.dart';
import 'registro_errores.dart';

/// Manda una comanda a la terminal con esa clave de idempotencia (la misma clave no imprime dos veces).
typedef ImprimirComanda = Future<void> Function(String contenido, {required String idempotencyKey, required String externalReference});

/// Si este equipo es la comandera y qué comandas ya imprimió (gid del pedido → cuándo).
abstract class RegistroComandas {
  Future<bool> activa();
  Future<void> fijarActiva(bool valor);
  Future<Map<String, int>> impresas();
  Future<void> guardarImpresas(Map<String, int> impresas);
}

class RegistroComandasEnMemoria implements RegistroComandas {
  bool prendida = false;
  Map<String, int> anotadas = {};

  @override
  Future<bool> activa() async => prendida;
  @override
  Future<void> fijarActiva(bool valor) async => prendida = valor;
  @override
  Future<Map<String, int>> impresas() async => Map.of(anotadas);
  @override
  Future<void> guardarImpresas(Map<String, int> impresas) async => anotadas = Map.of(impresas);
}

/// En las preferencias del equipo: no viaja con la sync ni con las copias (como "Imprimir el ticket en la Point al cobrar").
class RegistroComandasPrefs implements RegistroComandas {
  const RegistroComandasPrefs();
  static const _claveActiva = 'comandas_en_point';
  static const _claveImpresas = 'comandas_impresas';

  @override
  Future<bool> activa() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_claveActiva) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> fijarActiva(bool valor) async => (await SharedPreferences.getInstance()).setBool(_claveActiva, valor);

  @override
  Future<Map<String, int>> impresas() async {
    try {
      final crudo = (await SharedPreferences.getInstance()).getString(_claveImpresas);
      final j = crudo == null ? null : jsonDecode(crudo);
      return j is Map ? {for (final e in j.entries) if (e.value is int) '${e.key}': e.value as int} : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> guardarImpresas(Map<String, int> impresas) async =>
      (await SharedPreferences.getInstance()).setString(_claveImpresas, jsonEncode(impresas));
}

/// Por qué no salió la última comanda (null: salió todo). Lo muestra la pantalla de Pedidos.
final ValueNotifier<String?> errorComanda = ValueNotifier(null);

/// Lo que va en la comanda de [p].
DatosComanda datosComandaDe(PedidoGastronomia p) {
  final lineas = lineasDe(p);
  return DatosComanda(
    numero: p.numero,
    canal: CanalPedido.desdeClave(p.canal),
    forma: FormaEntrega.desdeClave(p.formaEntrega),
    nombreCliente: p.nombreCliente,
    telefono: p.telefono,
    direccion: p.direccion,
    zona: p.zona,
    lineas: lineas,
    nota: p.nota,
    fecha: p.fechaCreacion,
    horaEstimada: p.horaEstimada,
    programado: p.programado,
    pagado: p.pagado,
    totalCentavos: totalPedidoCentavos(lineas, costoEnvioCentavos: p.costoEnvioCentavos),
  );
}

class ComanderaPoint {
  ComanderaPoint({
    required this.db,
    required this.imprimir,
    this.registro = const RegistroComandasPrefs(),
    this.reintento = const Duration(minutes: 1),
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  final AppDatabase db;
  final ImprimirComanda imprimir;
  final RegistroComandas registro;

  /// Cada cuánto se reintenta lo que no salió (sin internet, la terminal apagada).
  final Duration reintento;
  final DateTime Function() _reloj;

  StreamSubscription<void>? _cambios;
  Timer? _timer;
  Future<void>? _enCurso;

  /// Cuántas veces falló cada comanda: cada reintento va con otra clave. Mercado Pago puede guardar la respuesta de una clave, y
  /// con la misma un "la terminal no contesta" se repetiría para siempre. A cambio, un corte justo después de imprimir puede dar
  /// una copia de más, que es mejor que una comanda que no sale.
  final Map<String, int> _fallas = {};
  bool _otraVuelta = false;

  bool get andando => _cambios != null;

  /// Empieza a mirar los pedidos si este equipo es la comandera. Se puede llamar de nuevo: no duplica nada.
  Future<void> iniciar() async {
    detener();
    if (!await registro.activa()) return;
    final porHacer = db.select(db.pedidosGastronomia)..where((p) => p.estado.equals(EstadoPedido.porHacer.clave));
    _cambios = porHacer.watch().listen((_) => unawaited(revisar()));
    _timer = Timer.periodic(reintento, (_) => unawaited(revisar()));
  }

  void detener() {
    _cambios?.cancel();
    _timer?.cancel();
    _cambios = null;
    _timer = null;
  }

  /// Prende o apaga este equipo como comandera. Al prender, lo que ya está en la cocina cuenta como impreso: la cocina ya lo
  /// tiene, y una tanda de comandas viejas de golpe confunde.
  Future<void> activar(bool valor) async {
    await registro.fijarActiva(valor);
    if (!valor) {
      detener();
      errorComanda.value = null;
      return;
    }
    final ahora = _reloj().millisecondsSinceEpoch;
    final impresas = await registro.impresas();
    for (final p in await _porHacer()) {
      final gid = p.globalId;
      if (gid != null) impresas.putIfAbsent(gid, () => ahora);
    }
    await registro.guardarImpresas(impresas);
    await iniciar();
  }

  Future<List<PedidoGastronomia>> _porHacer() =>
      (db.select(db.pedidosGastronomia)..where((p) => p.estado.equals(EstadoPedido.porHacer.clave))).get();

  /// Imprime lo confirmado que todavía no salió en este equipo (apagada, nada). De a una vuelta por vez: un cambio mientras imprime pide otra.
  Future<void> revisar() {
    if (!andando) return Future.value();
    final enCurso = _enCurso;
    if (enCurso != null) {
      _otraVuelta = true;
      return enCurso;
    }
    return _enCurso = _vueltas().whenComplete(() => _enCurso = null);
  }

  Future<void> _vueltas() async {
    do {
      _otraVuelta = false;
      await _vuelta();
    } while (_otraVuelta);
  }

  Future<void> _vuelta() async {
    final ahora = _reloj();
    final impresas = podarComandas(await registro.impresas(), ahora: ahora);
    final pedidos = {for (final p in await _porHacer()) if (p.globalId != null) p.globalId!: p};
    final salen = comandasPorImprimir(
      [for (final p in pedidos.values) (gid: p.globalId!, estado: EstadoPedido.desdeClave(p.estado), momento: p.actualizadoEn ?? p.fechaCreacion)],
      impresas: impresas.keys.toSet(),
      ahora: ahora,
    );
    if (salen.isEmpty) {
      errorComanda.value = null;
      return;
    }
    final encabezado = (await marcaDeBase(db)).encabezadoTicketEfectivo;
    for (final gid in salen) {
      final p = pedidos[gid]!;
      try {
        await imprimir(
          contenidoComandaPosnetMp(datosComandaDe(p), encabezadoNegocio: encabezado),
          idempotencyKey: 'comanda-$gid-${_fallas[gid] ?? 0}',
          externalReference: 'comanda-$gid',
        );
      } catch (e, st) {
        _fallas[gid] = (_fallas[gid] ?? 0) + 1;
        // Lo que no salió se reintenta en la próxima vuelta; los que siguen esperan (salen en orden, como entraron).
        errorComanda.value = 'No salió la comanda de ${p.numero} en la terminal: $e. Se reintenta sola.';
        unawaited(registrarSiNoEsDeRed('Imprimir la comanda', e, st));
        break;
      }
      impresas[gid] = _reloj().millisecondsSinceEpoch;
      await registro.guardarImpresas(impresas);
      errorComanda.value = null;
    }
  }

  /// "Imprimir comanda" del detalle: sale siempre (otra copia), y cuenta como impresa para que no salga sola después.
  Future<void> imprimirDeNuevo(PedidoGastronomia p) async {
    final encabezado = (await marcaDeBase(db)).encabezadoTicketEfectivo;
    final momento = _reloj().millisecondsSinceEpoch;
    await imprimir(
      contenidoComandaPosnetMp(datosComandaDe(p), encabezadoNegocio: encabezado),
      idempotencyKey: 'comanda-${p.globalId ?? p.id}-$momento',
      externalReference: 'comanda-$momento',
    );
    final gid = p.globalId;
    if (gid != null) {
      final impresas = await registro.impresas();
      impresas[gid] = momento;
      await registro.guardarImpresas(impresas);
    }
  }
}
