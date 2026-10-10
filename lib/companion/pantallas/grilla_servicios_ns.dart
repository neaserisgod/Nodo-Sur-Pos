// Cobrar en un negocio de servicios (`REGLAS-NEGOCIO.md` §20; mock `docs/mock-servicios`, "Cobrar"): en vez de buscar o
// escanear productos, una grilla con los servicios por categoría. Tocar uno lo suma al carrito con su precio y con lo que
// cuestan hoy sus insumos como costo-foto (Regla 4; la mano de obra no entra en la ganancia). Si con el stock de hoy no
// alcanza un insumo, se avisa y se cobra igual (por defecto solo avisa).
//
// Lee la base del celular, como la pestaña Servicios: cobrar servicios es solo para "Solo celular" (etapa 3).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show listarCategorias;
import '../../data/repositorio_servicios.dart';
import '../../domain/modulos.dart';
import '../../domain/venta.dart';
import '../../servicios/modulos_activos.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../kit/kit_ns.dart';

/// La línea de venta de un servicio: una vez, con su precio y el costo de sus insumos de hoy.
LineaVentaPorUnidad lineaDeServicio(ServicioListado s) => LineaVentaPorUnidad(
      productoId: '${s.producto.id}',
      nombreProducto: s.producto.nombre,
      proveedorId: null,
      cantidad: 1,
      esVarios: false,
      tipoCigarrillo: TipoCigarrillo.ninguno,
      precioUnitarioCentavos: s.producto.precioCentavos ?? 0,
      costoUnitarioCentavos: s.costo.insumosCentavos,
    );

/// El aviso de un servicio que con el stock de hoy no alcanza, o null si alcanza (o no lleva la cuenta de insumos).
String? avisoDeInsumos(ServicioListado s) {
  if (!moduloActivo(Modulo.insumos)) return null;
  final alcanza = s.alcanzaPara;
  if (alcanza == null || alcanza >= 1) return null;
  final falta = s.seAcabaPrimero?.producto.nombre;
  return falta == null ? 'No alcanzan los insumos' : 'Falta ${falta.toLowerCase()}';
}

class GrillaServiciosNs extends StatefulWidget {
  /// [db] es para tests.
  const GrillaServiciosNs({super.key, required this.onElegir, this.db});

  final ValueChanged<ServicioListado> onElegir;
  final AppDatabase? db;

  @override
  State<GrillaServiciosNs> createState() => _GrillaServiciosNsState();
}

class _GrillaServiciosNsState extends State<GrillaServiciosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<ServicioListado>? _servicios;
  Map<int, String> _categorias = const {};
  String? _categoria;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = avisosCambiosCompanion.listen((_) => _cargar());
    _cargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    final r = await Future.wait([listarServicios(_db, conManoDeObra: false), listarCategorias(_db)]);
    if (!mounted) return;
    setState(() {
      _servicios = [for (final s in r[0] as List<ServicioListado>) if ((s.producto.precioCentavos ?? 0) > 0) s];
      _categorias = {for (final c in r[1] as List<Categoria>) c.id: c.nombre};
    });
  }

  String _categoriaDe(ServicioListado s) => _categorias[s.producto.categoriaId] ?? 'Sin categoría';

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final servicios = _servicios;
    if (servicios == null) return const EsqueletoListaNs();
    if (servicios.isEmpty) {
      return const InfoNs('Todavía no hay servicios con precio. Cargalos en la pestaña Servicios y aparecen acá para cobrar.');
    }
    final categorias = {for (final s in servicios) _categoriaDe(s)}.toList();
    final visibles = [for (final s in servicios) if (_categoria == null || _categoriaDe(s) == _categoria) s];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categorias.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChipNs(texto: 'Todos', activo: _categoria == null, onTap: () => setState(() => _categoria = null)),
              for (final c in categorias) ChipNs(texto: c, activo: _categoria == c, onTap: () => setState(() => _categoria = c)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 165 / 96,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final s in visibles)
              PresionNs(
                key: ValueKey('cobrar-servicio-${s.producto.id}'),
                onTap: () => widget.onElegir(s),
                etiqueta: s.producto.nombre,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, altura: 1.2, color: ns.ink)),
                      Row(
                        children: [
                          Expanded(child: Text(plataNs(s.producto.precioCentavos ?? 0), style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, tabular: true))),
                          Text('${s.producto.duracionMinutos ?? 0} min', style: estiloNs(13, color: ns.mute)),
                        ],
                      ),
                      if (avisoDeInsumos(s) case final aviso?)
                        Text(aviso, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(12, peso: FontWeight.w600, color: ns.w)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
