// Avisos de Mercado Pago de la PC (etapa D, 2026-10-04): baja los que el sitio guardó, guarda los que llegan en vivo y deja
// calculada la lista que muestra la campanita. Solo avisa — no toca caja ni stock.
//
// Nunca tira hacia afuera: sin cuenta, sin internet o con el sitio sin configurar simplemente no hay avisos nuevos.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/repositorio_avisos_mp.dart';
import '../domain/avisos_mp.dart';
import 'avisos_cobro_mp.dart';
import 'cuenta_nube.dart';
import 'registro_errores.dart';

class ServicioAvisosMp {
  ServicioAvisosMp({required this.db, required this.almacen, required this.cliente, this.repaso = const Duration(minutes: 1)});

  final AppDatabase db;
  final AlmacenCuenta almacen;
  final ClienteNube cliente;
  final Duration repaso;

  /// Lo que va en la campanita. Se recalcula con cada aviso, cada "visto" y cada [repaso] (un cobro que esperaba su venta
  /// pasa a avisar solo cuando termina la espera).
  final ValueNotifier<List<AvisoParaMostrar>> pendientes = ValueNotifier(const []);

  StreamSubscription<AvisoMp>? _enVivo;
  StreamSubscription<void>? _conexion;
  Timer? _reloj;

  void iniciar() {
    detener();
    _enVivo = avisosMpEnVivo.listen((a) => unawaited(_guardar([a])));
    _conexion = conexionEnVivoAbierta.listen((_) => unawaited(bajarPendientes()));
    _reloj = Timer.periodic(repaso, (_) => unawaited(recalcular()));
    unawaited(bajarPendientes());
  }

  void detener() {
    _enVivo?.cancel();
    _conexion?.cancel();
    _reloj?.cancel();
    _enVivo = _conexion = _reloj = null;
  }

  /// Pide al sitio lo que falta (los que llegaron con la PC apagada) y limpia lo viejo.
  Future<void> bajarPendientes() async {
    try {
      final cuenta = await almacen.leer();
      if (cuenta != null) {
        final nuevos = await cliente.avisosMp(cuenta.token, desde: await ultimoIdAvisoMp(db));
        await _guardar(nuevos);
      }
      await limpiarAvisosMpViejos(db);
    } on ErrorNube {
      // sin conexión, sin cuenta o el sitio sin Mercado Pago: sin novedades
    } catch (e, st) {
      registrarError('avisos_mp', e, st);
    }
    await recalcular();
  }

  Future<void> _guardar(List<AvisoMp> avisos) async {
    try {
      if (avisos.isNotEmpty) await guardarAvisosMp(db, avisos);
    } catch (e, st) {
      registrarError('avisos_mp', e, st);
    }
    await recalcular();
  }

  Future<void> recalcular() async {
    try {
      pendientes.value = await avisosMpParaMostrar(db);
    } catch (e, st) {
      registrarError('avisos_mp', e, st);
    }
  }

  Future<void> marcarVisto(AvisoMp aviso) async {
    await marcarAvisoMpVisto(db, aviso);
    await recalcular();
  }
}
