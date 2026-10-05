import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart';
import '../../data/repositorio_medios_pago.dart';
import '../../data/repositorio_productos.dart';
import '../../data/repositorio_secciones_menu.dart';
import '../../data/repositorio_usuarios.dart';
import '../../domain/modulos.dart';
import '../../servidor/servidor_companion.dart';

enum SeccionConfiguracion {
  comercio,
  cuentaNube,
  modulos,
  cigarrillos,
  cajaYRedondeo,
  vuelto,
  categorias,
  usuarios,
  mediosPago,
  menu,
  apariencia,
  respaldo,
  impresion,
  companion,
  asistenteIa,
  actualizaciones,
}

/// Los cinco grupos en que se muestra Configuración (El dueño, 2026-10-03: "simplificá lo más posible"): cada
/// sección de siempre sigue existiendo, pero se llega por uno de estos grupos en vez de una lista de quince.
enum GrupoConfiguracion {
  negocio('Negocio', 'Datos del comercio y usuarios', [SeccionConfiguracion.comercio, SeccionConfiguracion.usuarios]),
  cajaYCobros('Caja y cobros', 'Redondeo, recargos, vuelto y medios de pago', [
    SeccionConfiguracion.cajaYRedondeo,
    SeccionConfiguracion.cigarrillos,
    SeccionConfiguracion.vuelto,
    SeccionConfiguracion.mediosPago,
  ]),
  productos('Productos', 'Ganancia por categoría', [SeccionConfiguracion.categorias]),
  equiposYCuenta('Equipos y cuenta', 'Nodo Sur, impresión, celular, IA y copias', [
    SeccionConfiguracion.cuentaNube,
    SeccionConfiguracion.impresion,
    SeccionConfiguracion.companion,
    SeccionConfiguracion.asistenteIa,
    SeccionConfiguracion.respaldo,
    SeccionConfiguracion.actualizaciones,
  ]),
  apariencia('Apariencia', 'Tema, menú y módulos', [SeccionConfiguracion.apariencia, SeccionConfiguracion.menu, SeccionConfiguracion.modulos]);

  const GrupoConfiguracion(this.etiqueta, this.descripcion, this.secciones);
  final String etiqueta;
  final String descripcion;
  final List<SeccionConfiguracion> secciones;

  static GrupoConfiguracion de(SeccionConfiguracion s) => values.firstWhere((g) => g.secciones.contains(s));
}

class ConfiguracionControlador extends ChangeNotifier {
  ConfiguracionControlador(this.db);

  final AppDatabase db;

  SeccionConfiguracion seccionActual = SeccionConfiguracion.comercio;

  GrupoConfiguracion get grupoActual => GrupoConfiguracion.de(seccionActual);

  Configuracion? configuracion;
  ConfiguracionNegocio? configuracionNegocio;
  List<Categoria> categorias = [];
  List<Usuario> usuarios = [];
  List<MedioDePago> mediosDePago = [];
  List<SeccionMenu> secciones = [];
  List<Producto> productos = [];
  bool cargando = true;

  /// IP de LAN recomendada para el QR de emparejamiento — null si la
  /// máquina no tiene ninguna red conectada en este momento (ej. WiFi
  /// apagada), que es distinto de "no hay token generado todavía".
  String? companionIp;

  Future<void> cargarTodo() async {
    configuracion = await db.select(db.configuracionTabla).getSingle();
    configuracionNegocio = await configuracionNegocioActual(db);
    categorias = await listarCategorias(db);
    usuarios = await listarUsuarios(db);
    mediosDePago = await listarMediosDePago(db);
    secciones = await listarSecciones(db);
    productos = await (db.select(db.productos)..where((p) => p.activo.equals(true) & p.esVarios.equals(false))).get();
    cargando = false;
    notifyListeners();

    // Deliberadamente fuera de la cadena de arriba: enumerar interfaces de
    // red es una llamada real al sistema operativo (no a la base), puede
    // tardar o fallar según el entorno (sin red, sandboxeado), y ninguna
    // otra sección de Configuración depende de este dato — que tarde un
    // toque más no puede demorar el resto de la pantalla.
    _cargarIpCompanion();
  }

  Future<void> _cargarIpCompanion() async {
    try {
      companionIp = ipRecomendada(await direccionesIpLocales());
    } catch (_) {
      companionIp = null;
    }
    notifyListeners();
  }

  /// Genera (o regenera) el token de emparejamiento — cualquier celular ya
  /// emparejado con el token anterior deja de poder usar la API companion.
  Future<void> generarTokenCompanion() async {
    await regenerarTokenCompanion(db);
    await cargarTodo();
  }

  void irASeccion(SeccionConfiguracion seccion) {
    seccionActual = seccion;
    notifyListeners();
  }

  Future<void> guardarRecargo({
    required int primerAtado,
    required int atadoAdicional,
    required int suelto,
  }) async {
    await configurarRecargoCigarrillos(
      db,
      primerAtadoCentavos: primerAtado,
      atadoAdicionalCentavos: atadoAdicional,
      sueltoCentavos: suelto,
    );
    await cargarTodo();
  }

  Future<void> guardarFondoFijo(int monto) async {
    await configurarFondoFijo(db, monto);
    await cargarTodo();
  }

  Future<void> cambiarModulo(Modulo modulo, {required bool activo}) async {
    await configurarModulo(db, modulo, activo: activo);
    await cargarTodo();
  }

  Future<void> guardarDatosComercio({required String nombre, required String encabezadoTicket}) async {
    await configurarNombreComercio(db, nombre);
    await configurarEncabezadoTicket(db, encabezadoTicket);
    await cargarTodo();
  }

  Future<void> guardarPasoRedondeo(int monto) async {
    await configurarPasoRedondeo(db, monto);
    await cargarTodo();
  }

  Future<void> guardarProductoVuelto(int? productoId) async {
    await configurarProductoVuelto(db, productoId);
    await cargarTodo();
  }

  Future<void> guardarTemaOscuro(bool oscuro) async {
    await configurarTemaOscuroManual(db, oscuro);
    await cargarTodo();
  }

  Future<void> guardarTemaAutomatico(bool automatico) async {
    await configurarTemaAutomatico(db, automatico);
    await cargarTodo();
  }

  Future<void> guardarMarkupCategoria(int categoriaId, int markupBp) async {
    await actualizarMarkupCategoria(db, categoriaId: categoriaId, markupBp: markupBp);
    await cargarTodo();
  }

  Future<void> agregarUsuario(String nombre) async {
    await crearUsuario(db, nombre);
    await cargarTodo();
  }

  Future<void> renombrarUsuarioExistente(int id, String nombre) async {
    await renombrarUsuario(db, id, nombre);
    await cargarTodo();
  }

  Future<void> alternarActivoUsuario(Usuario usuario) async {
    if (usuario.activo) {
      await desactivarUsuario(db, usuario.id);
    } else {
      await activarUsuario(db, usuario.id);
    }
    await cargarTodo();
  }

  Future<void> renombrarMedio(int id, String nombre) async {
    await renombrarMedioDePago(db, id, nombre);
    await cargarTodo();
  }

  Future<void> alternarActivoMedio(MedioDePago medio) async {
    if (medio.activo) {
      await desactivarMedioDePago(db, medio.id);
    } else {
      await activarMedioDePago(db, medio.id);
    }
    await cargarTodo();
  }

  Future<void> alternarVisibleSeccion(SeccionMenu seccion) async {
    if (seccion.visible) {
      await ocultarSeccion(db, seccion.id);
    } else {
      await mostrarSeccion(db, seccion.id);
    }
    await cargarTodo();
  }

  Future<void> moverSeccion(int indice, {required bool arriba}) async {
    final destino = arriba ? indice - 1 : indice + 1;
    if (destino < 0 || destino >= secciones.length) return;
    final copia = [...secciones];
    final tmp = copia[indice];
    copia[indice] = copia[destino];
    copia[destino] = tmp;
    await reordenarSecciones(db, copia.map((s) => s.id).toList());
    await cargarTodo();
  }
}
