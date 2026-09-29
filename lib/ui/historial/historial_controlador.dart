import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_historial.dart';

class HistorialControlador extends ChangeNotifier {
  HistorialControlador(this.db);

  final AppDatabase db;

  List<ResumenDia> dias = [];
  bool cargando = true;

  Future<void> cargarTodo() async {
    dias = await listarDias(db);
    cargando = false;
    notifyListeners();
  }
}
