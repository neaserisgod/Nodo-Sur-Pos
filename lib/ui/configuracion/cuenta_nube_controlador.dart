// Estado de Configuración → Cuenta de Nodo Sur: si la PC está vinculada, qué copias hay, y las acciones
// (vincular, guardar una copia ahora, restaurar, desvincular). Nada acá puede frenar la caja: toda falla es un texto.

import 'package:flutter/foundation.dart';

import '../../data/database.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../../servicios/copias_nube.dart';
import '../../servicios/cuenta_nube.dart';
import '../../servicios/nube.dart';

class CuentaNubeControlador extends ChangeNotifier {
  CuentaNubeControlador({required this.nube, required this.db});

  final NubeApp nube;
  final AppDatabase db;

  bool cargando = true;
  bool vinculando = false;
  bool subiendo = false;
  CuentaVinculada? cuenta;
  EstadoCopias? estado;

  /// Sucursal y equipo del negocio (informativo). Null si todavía no se leyó, no hay o el servidor no lo ofrece.
  EquipoDeCuenta? equipo;
  String? error;
  String? aviso;
  bool hayCajaAbierta = false;

  bool get vinculada => cuenta != null;
  String? get canal => nube.canal;

  /// Vuelve a leer la cuenta y las copias. [conservarMensajes]: después de una acción, el resultado de esa acción
  /// (copia guardada, falló tal cosa) tiene que seguir a la vista; solo un error propio de la lectura lo pisa.
  Future<void> cargar({bool conservarMensajes = false}) async {
    cargando = true;
    notifyListeners();
    cuenta = await nube.almacen.leer();
    estado = null;
    equipo = null;
    if (!conservarMensajes) {
      error = null;
      aviso = null;
    }
    hayCajaAbierta = await sesionAbierta(db) != null;
    final c = cuenta;
    if (c != null) {
      try {
        estado = await nube.cliente.estado(c.token);
      } on ErrorNube catch (e) {
        error ??= e.mensaje;
      }
      // Solo informativo: si falla (sin red, un sitio más viejo) simplemente no se muestra, y no cuenta como error de la cuenta.
      try {
        equipo = await nube.cliente.equipo(c.token);
      } catch (_) {
        equipo = null;
      }
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> vincular() async {
    vinculando = true;
    error = null;
    aviso = null;
    notifyListeners();
    try {
      await vincularEstaPc(
        cliente: nube.cliente,
        almacen: nube.almacen,
        idDispositivo: await nube.idDispositivo(),
        nombre: nube.nombreDispositivo(),
        abrirNavegador: nube.abrirNavegador,
      );
      nube.canal = await nube.copias.avisarYRenovar(cid: await nube.idDispositivo(), sistema: 'windows');
      aviso = 'Listo: esta PC quedó vinculada.';
    } on ErrorNube catch (e) {
      error = e.mensaje;
    } catch (e) {
      error = 'No se pudo vincular: $e';
    }
    vinculando = false;
    nube.avisarCambio();
    await cargar(conservarMensajes: true);
  }

  Future<void> desvincular() async {
    await nube.almacen.borrar();
    // Si después se vincula otra cuenta (o la misma), no tiene que heredar "hasta acá bajé" de la anterior.
    await nube.sync?.reiniciar();
    nube.canal = null;
    nube.ultimoResultado = null;
    await cargar();
    aviso = 'Esta PC ya no está vinculada. Las copias guardadas siguen en tu cuenta.';
    notifyListeners();
    nube.avisarCambio();
  }

  Future<void> subirAhora() async {
    subiendo = true;
    error = null;
    aviso = null;
    notifyListeners();
    final r = await nube.subirCopia();
    switch (r) {
      case SubidaOk():
        aviso = 'Copia guardada en tu cuenta.';
      case SubidaSinCuenta():
        error = 'Primero vinculá esta PC a tu cuenta.';
      case SubidaFallida(:final mensaje):
        error = mensaje;
    }
    subiendo = false;
    await cargar(conservarMensajes: true);
  }

  /// Baja y verifica la copia; la pantalla pide la confirmación y reemplaza la base. Tira [ErrorRestauracion] o
  /// [ErrorNube] con un texto para mostrar.
  Future<CopiaParaRestaurar> prepararRestauracion(CopiaEnNube copia) => nube.copias.prepararRestauracion(copia.id);
}
