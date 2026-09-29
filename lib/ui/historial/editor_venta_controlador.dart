// Editor completo tipo carrito de una venta ya cobrada (fase 9, Regla 9):
// agregar/quitar líneas, cambiar cantidades, cambiar medio de pago. Al
// guardar, revierte lo viejo y reaplica lo nuevo (repositorio_edicion_venta.dart).
//
// Una línea sin producto real (venta de carga histórica) se edita como
// texto libre + monto — no tiene sentido ofrecerle un buscador de catálogo
// para algo que nunca fue un producto del catálogo.

import 'package:flutter/widgets.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart';
import '../../data/repositorio_edicion_venta.dart';
import '../../data/repositorio_historial.dart';
import '../../data/repositorio_ventas.dart';
import '../../domain/descuento.dart';
import '../../domain/medio_pago.dart';
import '../../domain/recargo_cigarrillos.dart';
import '../../domain/venta.dart';

class EditorVentaControlador extends ChangeNotifier {
  EditorVentaControlador(this.db, {required this.ventaId, required this.usuarioId});

  final AppDatabase db;
  final int ventaId;
  final int usuarioId;

  FilaVenta? ventaOriginal;
  List<LineaVenta> lineas = [];
  ComposicionPago? medioElegido;
  int? montoEfectivoMixtoCentavos;

  /// Canal de la terminal (qr/débito) del pago virtual original — se conserva
  /// al editar, si el medio sigue siendo virtual.
  String? canalOriginal;
  ConfiguracionNegocio? configuracion;
  MedioDePago? medioEfectivo;
  MedioDePago? medioVirtual;
  int? productoVariosId;
  bool cargando = true;

  List<Producto> _catalogo = [];
  String busqueda = '';
  List<Producto> resultadosBusqueda = [];

  int get subtotalCentavos => Venta(lineas: lineas).subtotalCentavos;

  // ─── Lo que va a cambiar ("Lenguaje de diseño", mock `EditorVenta`) ────
  //
  // Todo se calcula contra cómo estaba la venta al abrir el editor: nada de
  // esto toca la base hasta "Guardar cambios".

  /// Las líneas como estaban al abrir el editor.
  List<LineaVenta> lineasOriginales = const [];
  Map<String, String> nombresProveedor = {};

  /// Anular una venta solo mientras su caja siga abierta (Bruno,
  /// 2026-09-13): anularla con la caja ya arqueada descuadraría ese arqueo.
  bool sesionAbierta = false;

  /// Unidades (o gramos, en pesables) por producto — clave `productoId`.
  /// "Varios" y los renglones libres no tienen stock: afuera.
  Map<String, ({String nombre, int cantidad, bool pesable})> _porProducto(List<LineaVenta> ls) {
    final r = <String, ({String nombre, int cantidad, bool pesable})>{};
    for (final l in ls) {
      if (l is LineaVentaPorUnidad && l.esVarios) continue;
      final pesable = l is LineaVentaPesable;
      final cantidad = pesable ? l.gramos : (l as LineaVentaPorUnidad).cantidad;
      final previo = r[l.productoId];
      r[l.productoId] = (nombre: l.nombreProducto, cantidad: (previo?.cantidad ?? 0) + cantidad, pesable: pesable);
    }
    return r;
  }

  /// "Cambió: 1 → 2" o "Nuevo" de cada línea de ahora, por su producto.
  String? cambioDeLinea(LineaVenta l) {
    if (l is LineaVentaPorUnidad && l.esVarios) {
      final estaba = lineasOriginales.any((o) => o.nombreProducto == l.nombreProducto && o.subtotalCentavos == l.subtotalCentavos);
      return estaba ? null : 'Nuevo';
    }
    final antes = _porProducto(lineasOriginales)[l.productoId];
    if (antes == null) return 'Nuevo';
    final ahora = _porProducto(lineas)[l.productoId]!;
    if (ahora.cantidad == antes.cantidad) return null;
    final u = ahora.pesable ? ' g' : '';
    return 'Cambió: ${antes.cantidad}$u → ${ahora.cantidad}$u';
  }

  /// Cuánto cambia el stock de cada producto al guardar: vender más baja el
  /// stock, sacar una línea lo devuelve.
  List<({String nombre, int delta, bool pesable})> get ajustesDeStock {
    final antes = _porProducto(lineasOriginales);
    final ahora = _porProducto(lineas);
    return [
      for (final id in {...antes.keys, ...ahora.keys})
        if ((antes[id]?.cantidad ?? 0) != (ahora[id]?.cantidad ?? 0))
          (
            nombre: (ahora[id] ?? antes[id])!.nombre,
            delta: (antes[id]?.cantidad ?? 0) - (ahora[id]?.cantidad ?? 0),
            pesable: (ahora[id] ?? antes[id])!.pesable,
          ),
    ];
  }

  /// Cuánto cambia lo que hay que separar para cada proveedor (el costo-foto
  /// de lo vendido, Regla 5).
  List<({String proveedor, int deltaCentavos})> get ajustesDeSeparacion {
    Map<String, int> costos(List<LineaVenta> ls) {
      final r = <String, int>{};
      for (final l in ls) {
        final costo = l.costoLineaCentavos;
        if (costo == null || l.proveedorId == null) continue;
        r[l.proveedorId!] = (r[l.proveedorId!] ?? 0) + costo;
      }
      return r;
    }

    final antes = costos(lineasOriginales);
    final ahora = costos(lineas);
    return [
      for (final id in {...antes.keys, ...ahora.keys})
        if ((ahora[id] ?? 0) != (antes[id] ?? 0))
          (proveedor: nombresProveedor[id] ?? 'Sin proveedor', deltaCentavos: (ahora[id] ?? 0) - (antes[id] ?? 0)),
    ];
  }

  /// Ganancia de la venta como quedaría (solo lo que tiene costo cargado).
  int get gananciaNuevaCentavos => lineas.fold(0, (a, l) {
        final costo = l.costoLineaCentavos;
        return costo == null ? a : a + l.subtotalCentavos - costo;
      });

  void sumarUnidad(int indice, int delta) {
    final l = lineas[indice];
    if (l is! LineaVentaPorUnidad || l.esVarios) return;
    final nueva = l.cantidad + delta;
    if (nueva <= 0) {
      quitarLinea(indice);
    } else {
      cambiarCantidad(indice, nueva);
    }
  }

  /// Anula la venta entera (misma función que Historial → Anular).
  Future<void> anular({required String motivo}) =>
      anularVenta(db, ventaId: ventaId, usuarioId: usuarioId, motivo: motivo);

  ResultadoTotalVenta? get resultado {
    final medio = medioElegido;
    final config = configuracion;
    if (medio == null || config == null) return null;
    return calcularTotalVenta(
      venta: Venta(lineas: lineas),
      composicionPago: medio,
      configRecargoCigarrillos: ConfigRecargoCigarrillos(
        primerAtadoCentavos: config.recargoPrimerAtadoCentavos,
        atadoAdicionalCentavos: config.recargoAtadoAdicionalCentavos,
        cigarroSueltoCentavos: config.recargoSueltoCentavos,
      ),
      pasoRedondeoCentavos: config.pasoRedondeoCentavos,
      // El descuento de la venta original se conserva como monto fijo: antes
      // el editor lo tiraba y el total subía sin avisar (revisión 2026-09-29).
      // Con tope en el total (`calcularDescuento`), así que si se sacan
      // líneas nunca deja un total negativo.
      tipoDescuento: (ventaOriginal?.descuentoCentavos ?? 0) > 0 ? TipoDescuento.monto : null,
      valorDescuento: ventaOriginal?.descuentoCentavos ?? 0,
    );
  }

  Future<void> cargarTodo() async {
    ventaOriginal = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    final filasLinea = await lineasDeVenta(db, ventaId);
    final filasPago = await pagosDeVenta(db, ventaId);
    configuracion = await configuracionNegocioActual(db);
    medioEfectivo = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
    medioVirtual = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
    _catalogo = await db.select(db.productos).get();
    productoVariosId = _catalogo.firstWhere((p) => p.esVarios).id;

    lineas = filasLinea.map((f) => lineaVentaDesdeFila(f, productoVariosId: productoVariosId!)).toList();
    lineasOriginales = List.unmodifiable(lineas);
    nombresProveedor = {for (final p in await db.select(db.proveedores).get()) p.id.toString(): p.nombre};
    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(ventaOriginal!.sesionCajaId))).getSingleOrNull();
    sesionAbierta = sesion?.estado == 'ABIERTA';

    var montoEfectivo = 0;
    var montoVirtual = 0;
    for (final pago in filasPago) {
      if (pago.canal != null) canalOriginal = pago.canal;
      if (pago.medioPagoId == medioEfectivo!.id) {
        montoEfectivo += pago.montoCentavos;
      } else {
        montoVirtual += pago.montoCentavos;
      }
    }
    if (montoEfectivo > 0 && montoVirtual > 0) {
      medioElegido = ComposicionPago.mixto;
      montoEfectivoMixtoCentavos = montoEfectivo;
    } else if (montoVirtual > 0) {
      medioElegido = ComposicionPago.virtual;
    } else {
      medioElegido = ComposicionPago.efectivo;
    }

    cargando = false;
    notifyListeners();
  }

  void elegirMedio(ComposicionPago medio) {
    medioElegido = medio;
    if (medio != ComposicionPago.mixto) montoEfectivoMixtoCentavos = null;
    notifyListeners();
  }

  void fijarMontoEfectivoMixto(int monto) {
    montoEfectivoMixtoCentavos = monto;
    notifyListeners();
  }

  void buscar(String texto) {
    busqueda = texto;
    resultadosBusqueda = texto.trim().isEmpty
        ? []
        : buscarProductos(catalogo: _catalogo, textoBuscado: texto);
    notifyListeners();
  }

  void agregarProducto(Producto producto, {int cantidad = 1, int? gramos}) {
    lineas = [...lineas, lineaDesdeProducto(producto, cantidad: cantidad, gramos: gramos)];
    busqueda = '';
    resultadosBusqueda = [];
    notifyListeners();
  }

  /// Renglón libre (texto + monto), para líneas sin producto real —
  /// exactamente lo que necesita corregir una venta de carga histórica.
  void agregarLineaLibre({
    required String detalle,
    required int montoCentavos,
    int? proveedorId,
    int? costoCentavos,
  }) {
    lineas = [
      ...lineas,
      LineaVentaPorUnidad(
        productoId: productoVariosId!.toString(),
        nombreProducto: detalle,
        proveedorId: proveedorId?.toString(),
        cantidad: 1,
        esVarios: true,
        precioUnitarioCentavos: montoCentavos,
        costoUnitarioCentavos: costoCentavos,
      ),
    ];
    notifyListeners();
  }

  void quitarLinea(int indice) {
    lineas = [...lineas]..removeAt(indice);
    notifyListeners();
  }

  void cambiarCantidad(int indice, int nuevaCantidad) {
    final actual = lineas[indice];
    if (actual is! LineaVentaPorUnidad || nuevaCantidad <= 0) return;
    final copia = [...lineas];
    copia[indice] = LineaVentaPorUnidad(
      productoId: actual.productoId,
      nombreProducto: actual.nombreProducto,
      proveedorId: actual.proveedorId,
      cantidad: nuevaCantidad,
      esVarios: actual.esVarios,
      tipoCigarrillo: actual.tipoCigarrillo,
      precioUnitarioCentavos: actual.precioUnitarioCentavos,
      costoUnitarioCentavos: actual.costoUnitarioCentavos,
    );
    lineas = copia;
    notifyListeners();
  }

  Future<bool> guardar({required String motivo}) async {
    final r = resultado;
    final medio = medioElegido;
    if (r == null || medio == null || lineas.isEmpty || motivo.trim().isEmpty) return false;

    final pagos = <PagoARegistrar>[];
    switch (medio) {
      case ComposicionPago.efectivo:
        pagos.add(PagoARegistrar(medioPagoId: medioEfectivo!.id, montoCentavos: r.totalCentavos, esEfectivo: true));
      case ComposicionPago.virtual:
        pagos.add(PagoARegistrar(medioPagoId: medioVirtual!.id, montoCentavos: r.totalCentavos, esEfectivo: false, canal: canalOriginal));
      case ComposicionPago.mixto:
        final efectivo = montoEfectivoMixtoCentavos;
        if (efectivo == null || efectivo < 0 || efectivo > r.totalCentavos) return false;
        pagos.add(PagoARegistrar(medioPagoId: medioEfectivo!.id, montoCentavos: efectivo, esEfectivo: true));
        pagos.add(PagoARegistrar(
          medioPagoId: medioVirtual!.id,
          montoCentavos: r.totalCentavos - efectivo,
          esEfectivo: false,
          canal: canalOriginal,
        ));
    }

    await editarVenta(
      db,
      ventaId: ventaId,
      ventaNueva: Venta(lineas: lineas),
      resultadoNuevo: r,
      pagosNuevos: pagos,
      usuarioId: usuarioId,
      motivo: motivo.trim(),
    );
    return true;
  }
}
