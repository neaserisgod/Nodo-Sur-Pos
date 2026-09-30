import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import '../../data/importar_base.dart';
import '../../data/repositorio_respaldo.dart';
import '../../data/repositorio_ventas.dart';

class RespaldoControlador extends ChangeNotifier {
  RespaldoControlador(this.db, {this.carpetaTemporal});

  final AppDatabase db;

  /// Dónde se deja la base importada ya validada; null = la carpeta temporal del sistema.
  final Directory? carpetaTemporal;

  String? carpeta;
  int cantidadCopias = 14;
  List<ArchivoRespaldo> respaldos = [];

  /// Restaurar queda bloqueado mientras haya una caja abierta (Regla de esta
  /// fase, confirmada por el dueño): evita perder por accidente las ventas del
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

  /// Valida un archivo elegido por la persona y lo deja listo para reemplazar la base. Null (y [error] con el motivo)
  /// si no se puede importar; la base en uso no se toca.
  Future<BaseParaImportar?> prepararImportacionDeArchivo(String ruta) async {
    error = null;
    notifyListeners();
    try {
      final temporal = carpetaTemporal ?? Directory(p.join((await getTemporaryDirectory()).path, 'nodosur_importar'));
      return await prepararImportacion(ruta, esquemaActual: db.schemaVersion, carpetaTemporal: temporal);
    } on ErrorImportacion catch (e) {
      error = e.mensaje;
    } catch (e) {
      error = 'No se pudo leer el archivo: $e';
    }
    notifyListeners();
    return null;
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
