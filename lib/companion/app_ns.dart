// Estado compartido entre las pestañas del celular. `PantallaMenuCompanion`
// es quien lo sostiene (servicio, sesión de caja, carrito, usuario, conexión)
// y lo expone con [AppNs]; las pantallas del mock lo leen desde acá en vez de
// recibir diez parámetros cada una.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/venta.dart';
import 'cliente_companion.dart';
import 'funciones_ns.dart';
import 'kit/kit_ns.dart';
import 'modo_uso.dart';
import 'servicio_companion.dart';

/// Lo que hay para hacer, calculado de los datos reales (docs/02 §3.8).
class PendientesNs {
  const PendientesNs({this.faltaSepararCentavos = 0, this.proveedoresPendientes = 0, this.proveedoresTotal = 0, this.sinStock = 0, this.hayActualizacion = false, this.arqueoVencido = false, this.minutosDesdeConteo = 0, this.avisosMp = 0});

  /// Plata del día que todavía no se separó para proveedores.
  final int faltaSepararCentavos;
  final int proveedoresPendientes;
  final int proveedoresTotal;
  final int sinStock;
  final bool hayActualizacion;

  /// Pasaron 2 horas desde el último conteo de la caja (aviso no bloqueante).
  final bool arqueoVencido;

  /// Cuánto hace del último conteo (o de la apertura): "Hace 2 h 15 min".
  final int minutosDesdeConteo;

  /// Avisos de Mercado Pago sin ver (cobros sin venta, contracargos, reclamos). Solo sin la PC: con PC los muestra la PC.
  final int avisosMp;

  int get proveedoresSeparados => proveedoresTotal - proveedoresPendientes;
  bool get haySeparar => proveedoresPendientes > 0;

  /// Cuántos pendientes vigentes marca la campana.
  int get cantidad => (haySeparar ? 1 : 0) + (sinStock > 0 ? 1 : 0) + (hayActualizacion ? 1 : 0) + (arqueoVencido ? 1 : 0) + avisosMp;
}

/// Cifras del día (Inicio y Resumen de Caja), leídas de la base local.
class DatosDiaNs {
  const DatosDiaNs({this.vendidoCentavos = 0, this.gananciaCentavos = 0, this.efectivoCentavos = 0, this.mpCentavos = 0, this.ventas = 0});

  final int vendidoCentavos;
  final int gananciaCentavos;
  final int efectivoCentavos;
  final int mpCentavos;
  final int ventas;
}

abstract class ControladorAppNs {
  ServicioCompanion? get servicio;
  ClienteCompanion? get cliente;
  int? get usuarioId;
  String? get nombreUsuario;
  SesionCompanion? get sesion;
  EstadoCajaCompanion? get estadoCaja;
  List<LineaVenta> get carrito;
  ModoUso? get modoUso;

  /// Hay una PC emparejada (con o sin respuesta).
  bool get pcEmparejada;

  /// La PC está emparejada y no contesta: se trabaja con los datos del celular.
  bool get sinConexion;

  bool get cajaAbierta;

  ValueNotifier<PendientesNs> get pendientes;
  ValueNotifier<DatosDiaNs> get datosDia;

  /// Solapa de Caja (0 Resumen, 1 Separar, 2 Ventas).
  ValueNotifier<int> get segmentoCaja;

  /// Productos en modo "Controlar stock".
  ValueNotifier<bool> get productosEnConteo;

  /// Vender en el paso de cobro o de "hecho": la barra inferior se esconde.
  ValueNotifier<bool> get ocultarBarra;

  PestaniaNs get pestania;
  void irAPestania(PestaniaNs p);

  /// Empuja una pantalla secundaria (sin barra inferior).
  Future<T?> irA<T>(WidgetBuilder builder);

  /// Vuelve a pedir sesión de caja, cifras y pendientes.
  Future<void> refrescar();

  /// Hoja "Abrir caja" (docs/03 H1).
  Future<void> abrirCaja();

  /// Sincroniza con la PC y vuelve a calcular todo.
  Future<void> sincronizar();

  /// Hoja "Actualizar" (docs/03 H8).
  Future<void> abrirActualizacion();

  /// Ejecuta una función del buscador (navegación directa, docs/06).
  Future<void> ejecutarFuncion(AccionFuncion accion);

  /// Conteo de stock: de un proveedor, de los productos sin stock o vacío para elegir.
  Future<void> abrirConteo({bool soloSinStock = false});

  /// Cerrar el turno y volver a elegir usuario / desconectar de esta PC.
  Future<void> cambiarUsuario();
  Future<void> cambiarModo();
}

class AppNs extends InheritedWidget {
  const AppNs({super.key, required this.controlador, required this.version, required super.child});

  final ControladorAppNs controlador;

  /// Cambia cada vez que el controlador tiene datos nuevos, para reconstruir a quien lo lea.
  final int version;

  static ControladorAppNs of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<AppNs>();
    assert(w != null, 'Falta AppNs arriba en el árbol');
    return w!.controlador;
  }

  /// Como [of], pero null fuera del menú (una pantalla probada sola).
  static ControladorAppNs? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppNs>()?.controlador;

  @override
  bool updateShouldNotify(AppNs old) => old.version != version || old.controlador != controlador;
}

/// El controlador del menú publicado para TODA la app: las pantallas que se abren con `Navigator.push` (Notificaciones,
/// Buscador, Cierre, Consultar precio…) cuelgan del navegador y no del menú, así que sin esto no encuentran `AppNs`.
/// `companion_app.dart` lo pone arriba del navegador.
final ValueNotifier<({ControladorAppNs controlador, int version})?> puenteAppNs = ValueNotifier(null);

/// Hay una PC emparejada que no contesta: el cartel "Sin conexión con la PC"
/// se dibuja arriba de todas las pantallas (menos las de arranque).
final ValueNotifier<bool> sinConexionGlobalNs = ValueNotifier(false);

/// Tema elegido en Más → Apariencia (claro, oscuro o automático). El mock
/// arranca en claro.
final ValueNotifier<ThemeMode> modoTemaNs = ValueNotifier(ThemeMode.light);

const _claveTema = 'companion_tema';

Future<void> cargarModoTemaNs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    modoTemaNs.value = switch (prefs.getString(_claveTema)) {
      'oscuro' => ThemeMode.dark,
      'auto' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  } catch (_) {
    // Sin preferencias guardadas queda en claro.
  }
}

Future<void> guardarModoTemaNs(ThemeMode modo) async {
  modoTemaNs.value = modo;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveTema, switch (modo) {
      ThemeMode.dark => 'oscuro',
      ThemeMode.system => 'auto',
      ThemeMode.light => 'claro',
    });
  } catch (_) {
    // No se pudo guardar: el cambio vale hasta cerrar la app.
  }
}

/// Pone `AppNs` arriba del navegador con el controlador del menú, para que lo encuentren también las pantallas que se
/// abren con `Navigator.push` (ver `puenteAppNs`).
class PuenteAppNs extends StatelessWidget {
  const PuenteAppNs({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<({ControladorAppNs controlador, int version})?>(
        valueListenable: puenteAppNs,
        child: child,
        builder: (context, publicado, hijo) =>
            publicado == null ? hijo! : AppNs(controlador: publicado.controlador, version: publicado.version, child: hijo!),
      );
}
