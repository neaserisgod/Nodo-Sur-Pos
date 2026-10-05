// "Consultar precio", tal cual el mock (docs/03 C1): escribir o escanear, ver el
// precio gigante en una tarjeta oscura y, si hace falta, agregarlo a la venta.
// Es de solo lectura a propósito: un vistazo rápido nunca corre el riesgo de
// tocar un precio sin querer.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_ns.dart';
import 'base_local.dart';
import 'cambios_companion.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart' show ProductoCompanion;
import 'debounce.dart';
import 'emparejamiento.dart';
import 'escanear_codigo.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import '../domain/venta.dart';

class PantallaConsultarPrecio extends StatefulWidget {
  const PantallaConsultarPrecio({super.key});

  @override
  State<PantallaConsultarPrecio> createState() => _PantallaConsultarPrecioState();
}

class _PantallaConsultarPrecioState extends State<PantallaConsultarPrecio> {
  ServicioCompanion? _servicio;
  final _busquedaCtrl = TextEditingController();
  final _debouncer = Debouncer();
  List<ProductoCompanion> _resultados = [];
  Map<int, String> _proveedores = {};
  ProductoCompanion? _seleccionado;
  bool _escaneando = false;
  String? _error;
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    _iniciar();
    // Llegó algo nuevo por la sync: se repite la búsqueda sola.
    _subCambiosSync = avisosCambiosCompanion.listen((_) => _buscar(_busquedaCtrl.text));
  }

  /// Sin PC emparejada cae a la base local sincronizada: buscar un precio no necesita la PC.
  Future<void> _iniciar() async {
    try {
      final conexion = await leerConexion();
      final servicio = conexion == null ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion())) : await resolverServicioCompanion(conexion);
      if (!mounted) return;
      _servicio = servicio;
      try {
        final provs = await servicio.proveedores();
        _proveedores = {for (final p in provs) p.id: p.nombre};
      } catch (_) {
        // Sin proveedores solo se muestra el stock.
      }
      await _buscar('');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debouncer.dispose();
    _subCambiosSync?.cancel();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    final servicio = _servicio;
    if (servicio == null) return;
    try {
      final lista = await servicio.productos(busqueda: texto.trim().isEmpty ? null : texto);
      // Descarta una respuesta que ya no corresponde al texto actual.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() {
          _resultados = texto.trim().isEmpty ? lista.take(6).toList() : lista;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _busquedaCtrl.text == texto) setState(() => _error = mensajeDeError(e));
    }
  }

  Future<void> _escanear() async {
    final servicio = _servicio;
    if (servicio == null || _escaneando) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() {
      _escaneando = true;
      _error = null;
    });
    try {
      final producto = await servicio.porCodigoBarras(codigo);
      if (!mounted) return;
      if (producto == null) {
        setState(() => _error = 'No hay ningún producto con ese código');
      } else {
        setState(() {
          _seleccionado = producto;
          _busquedaCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  /// "Agregar a la venta": suma el producto al carrito (un pesable entra con 250 g) y va a Vender.
  void _agregarALaVenta(ProductoCompanion p) {
    final app = AppNs.of(context);
    final r = lineaDesdeResultadoBusqueda(p, gramos: p.esPesable ? 250 : null);
    if (r.error != null) {
      mostrarAvisoNs(context, r.error!, largo: true);
      return;
    }
    final nueva = r.linea!;
    final i = app.carrito.indexWhere((l) => l.productoId == nueva.productoId);
    if (i != -1) {
      app.carrito[i] = sumarLineasVenta(app.carrito[i], nueva);
    } else {
      app.carrito.add(nueva);
    }
    Navigator.of(context).pop();
    app.irAPestania(PestaniaNs.vender);
  }

  String _meta(ProductoCompanion p) {
    final prov = _proveedores[p.proveedorId];
    return [if (p.esPesable) 'Por kilo', ?prov, 'stock ${stockTextoNs(p)}'].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final sel = _seleccionado;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CabeceraSubNs(titulo: 'Consultar precio', onVolver: () => Navigator.of(context).maybePop(), track: -0.05),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: BuscadorNs(
                        controller: _busquedaCtrl,
                        placeholder: 'Escribí el nombre o escaneá',
                        onChanged: (t) {
                          setState(() => _seleccionado = null);
                          _debouncer.ejecutar(() => _buscar(t));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    PresionNs(
                      onTap: _escaneando ? null : _escanear,
                      etiqueta: 'Escanear código de barras',
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: ns.prim, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const IconoNsWidget(IconoNs.escanear, tamanio: 24, color: TokensNs.blanco),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_error != null) ...[InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo, tamanio: 15, peso: FontWeight.w500), const SizedBox(height: 14)],
                if (sel != null) ...[
                  EntradaNs(
                    child: HeroNs(
                      radio: 40,
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sel.nombre, style: estiloNs(15, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
                          const SizedBox(height: 6),
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(precioTextoNs(sel), style: tituloNs(72, track: -0.065, color: TokensNs.blanco))),
                          const SizedBox(height: 12),
                          Text(_meta(sel), style: estiloNs(15, color: const Color(0xC7FFFFFF))),
                          if (!sel.activo) ...[const SizedBox(height: 8), Text('Producto desactivado', style: estiloNs(14, peso: FontWeight.w700, color: TokensNs.eliminarSobreOscuro))],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  BotonNs.primario(context, 'Agregar a la venta', () => _agregarALaVenta(sel)),
                  const SizedBox(height: 14),
                ],
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _resultados.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = _resultados[i];
                      return EntradaNs(
                        child: PresionNs(
                          onTap: () => setState(() => _seleccionado = p),
                          etiqueta: p.nombre,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 56),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              children: [
                                Expanded(child: Text(p.nombre, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
                                const SizedBox(width: 12),
                                Text(precioTextoNs(p), style: estiloNs(19, peso: FontWeight.w500, color: ns.ink, tabular: true)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
