// Controlador de app de mentira para dibujar y probar las pantallas del mock
// sin servicios reales: devuelve las cifras de ejemplo del mock (docs/02 §3.4).
import 'package:flutter/material.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/funciones_ns.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/servicio_companion.dart';
import 'package:la_plazoleta/domain/venta.dart';

class ControladorFalsoNs implements ControladorAppNs {
  ControladorFalsoNs({this.abierta = true, this.sinConex = false, PendientesNs? pend, DatosDiaNs? dia})
      : pendientes = ValueNotifier(pend ?? const PendientesNs(faltaSepararCentavos: 18140000, proveedoresPendientes: 4, proveedoresTotal: 4, sinStock: 3, hayActualizacion: true)),
        datosDia = ValueNotifier(dia ?? const DatosDiaNs(vendidoCentavos: 48230000, gananciaCentavos: 16890000, efectivoCentavos: 23150000, mpCentavos: 25080000, ventas: 6));

  final bool abierta;
  final bool sinConex;
  final List<String> llamadas = [];

  @override
  final ValueNotifier<PendientesNs> pendientes;
  @override
  final ValueNotifier<DatosDiaNs> datosDia;
  @override
  final ValueNotifier<int> segmentoCaja = ValueNotifier(0);
  @override
  final ValueNotifier<bool> productosEnConteo = ValueNotifier(false);
  @override
  final ValueNotifier<bool> ocultarBarra = ValueNotifier(false);

  @override
  final List<LineaVenta> carrito = [];
  @override
  PestaniaNs pestania = PestaniaNs.inicio;

  @override
  String? get nombreUsuario => 'Ana';
  @override
  bool get cajaAbierta => abierta;
  @override
  bool get sinConexion => sinConex;
  @override
  bool get pcEmparejada => true;
  @override
  ServicioCompanion? get servicio => null;
  @override
  ClienteCompanion? get cliente => null;
  @override
  int? get usuarioId => 1;
  @override
  SesionCompanion? get sesion => SesionCompanion(abierta: abierta, id: abierta ? 1 : null, fechaApertura: DateTime(2026, 10, 4, 9));
  @override
  EstadoCajaCompanion? get estadoCaja => EstadoCajaCompanion(
        sesionId: 1,
        fechaApertura: DateTime(2026, 10, 4, 9),
        efectivoEsperadoCentavos: 18640000,
        mpEsperadoCentavos: 25080000,
        redondeoAcumuladoCentavos: 0,
        lataInicialCentavos: 4200000,
        cantidadVentas: 6,
        resumen: const ResumenDiaHistoricoCompanion(
          totalCentavos: 48230000,
          efectivoCentavos: 23150000,
          mercadoPagoCentavos: 25080000,
          cigarrillosListaCentavos: 0,
          vendidoSinCostoCentavos: 0,
          productosSinDatos: [],
          porProveedor: [],
        ),
      );
  @override
  ModoUso? get modoUso => ModoUso.pcYCelular;

  @override
  void irAPestania(PestaniaNs p) {
    llamadas.add('pestania:${p.name}');
    pestania = p;
  }

  @override
  Future<T?> irA<T>(WidgetBuilder builder) async {
    llamadas.add('irA');
    return null;
  }

  @override
  Future<void> refrescar() async => llamadas.add('refrescar');
  @override
  Future<void> abrirCaja() async => llamadas.add('abrirCaja');
  @override
  Future<void> sincronizar() async => llamadas.add('sincronizar');
  @override
  Future<void> abrirActualizacion() async => llamadas.add('actualizacion');
  @override
  Future<void> cambiarUsuario() async => llamadas.add('cambiarUsuario');
  @override
  Future<void> cambiarModo() async => llamadas.add('cambiarModo');
  @override
  Future<void> abrirConteo({bool soloSinStock = false}) async => llamadas.add('conteo:$soloSinStock');
  @override
  Future<void> ejecutarFuncion(AccionFuncion accion) async => llamadas.add('funcion:${accion.name}');
}

/// El controlador de mentira, pero con un servicio real (base de test) para las pantallas que lo usan.
class ControladorConServicio extends ControladorFalsoNs {
  ControladorConServicio(this._servicio);
  final ServicioCompanion _servicio;

  @override
  ServicioCompanion? get servicio => _servicio;
}
