import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart';
import '../../data/repositorio_ventas.dart';

class RespaldoControlador extends ChangeNotifier {
  RespaldoControlador(this.db);

  final AppDatabase db;

  String? carpeta;
  int cantidadCopias = 14;
  List<ArchivoRespaldo> respaldos = [];

  /// Restaurar queda bloqueado mientras haya una caja abierta (Regla de esta
  /// fase, confirmada por Bruno): evita perder por accidente las ventas del
  /// día en curso, que todavía no están en ningún respaldo.
  bool hayCajaAbierta = false;

  bool cargando = true;
  bool respaldando = false;
  String? error;

  Future<void> cargarTodo() async {
    carpeta = await carpetaRespaldo(db);
    cantidadCopias = await cantidadCopiasConfigurada(db);
    respaldos = await listarRespaldos(db);
    hayCajaAbierta = await sesionAbierta(db) != null;
    cargando = false;
    notifyListeners();
  }

  Future<void> elegirCarpeta(String ruta) async {
    await configurarCarpetaRespaldo(db, ruta);
    await cargarTodo();
  }

  Future<void> cambiarCantidadCopias(int cantidad) async {
    await configurarCantidadCopias(db, cantidad);
    await cargarTodo();
  }

  Future<void> respaldarAhora() async {
    respaldando = true;
    error = null;
    notifyListeners();
    try {
      await hacerRespaldo(db);
    } catch (e) {
      error = 'No se pudo respaldar: $e';
    }
    respaldando = false;
    await cargarTodo();
  }
}
