// "Comparar precios" (El dueño, 2026-09-14: "una noción de los precios de mi
// local... para ajustarlos según si están muy caros o muy baratos") — dos
// fuentes, ver `lib/servicios/comparador_precios.dart` (SEPA/Precios
// Claros, La Anónima y Carrefour) y
// `lib/servicios/comparador_precios_todoatucasa.dart` (la API pública de
// Todo a tu Casa) para el porqué de cada una y el formato real de los
// datos.
//
// Solo informativo (El dueño eligió esto, no un ajuste automático): cada fila
// muestra mi precio al lado del de cada comercio encontrado y la mayor
// diferencia, ordenado de mayor a menor diferencia — El dueño decide qué
// hacer con cada uno, la pantalla no sugiere nada ni resalta con colores
// de alerta (el acento y el color de error del sistema de diseño están
// reservados para otra cosa, `DISENO.md` — una diferencia de precio contra
// el súper no es un estado "mal", es solo un dato).
//
// Lista TODO el catálogo activo con precio propio (El dueño, 2026-09-14:
// "todo lo que esté en mi sistema"), no solo lo que encontró coincidencia
// — un producto sin nada en ningún comercio muestra "—" en vez de
// desaparecer de la lista. Pesables se cruzan por nombre (aproximado, con
// un ícono de aviso) en vez de por código de barras (no tienen) — ver
// `repositorio_comparacion_precios.dart` para el detalle de los dos
// caminos de cruce.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_comparacion_precios.dart';
import '../../domain/dinero.dart';
import '../../domain/ganancia.dart';
import '../../servicios/comparador_precios.dart';
import '../../servicios/comparador_precios_todoatucasa.dart';
import '../comun/armazon_gestion.dart';
import '../comun/estado_vacio.dart';
import '../comun/tarjetas.dart';
import '../navegacion/busqueda_contextual.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../tema/iconos.dart';

class PantallaCompararPrecios extends StatefulWidget {
  const PantallaCompararPrecios({super.key, required this.db, required this.usuarioId, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<PantallaCompararPrecios> createState() => _PantallaCompararPreciosState();
}

class _PantallaCompararPreciosState extends State<PantallaCompararPrecios> {
  bool _cargando = true;
  bool _actualizando = false;
  List<ComparacionPrecio> _comparaciones = const [];
  DateTime? _ultimaActualizacion;
  Map<int, Producto> _productos = const {};
  int? _elegidoId;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final comparaciones = await comparacionDePrecios(widget.db);
    final ultima = await fechaUltimaComparacionDePrecios(widget.db);
    final productos = await widget.db.select(widget.db.productos).get();
    if (!mounted) return;
    setState(() {
      _comparaciones = comparaciones;
      _ultimaActualizacion = ultima;
      _productos = {for (final p in productos) p.id: p};
      _cargando = false;
    });
  }

  /// A diferencia del ciclo automático (`main.dart`), este botón fuerza la
  /// descarga aunque haya corrido hace menos de 20hs — para probar, o como
  /// respaldo si el automático viene fallando en silencio hace días. Las
  /// dos fuentes se piden en paralelo y por separado: si una falla (ej. la
  /// API de Todo a tu Casa está caída) la otra igual se guarda, no se
  /// pierde una actualización buena por la otra.
  Future<void> _actualizarAhora() async {
    setState(() => _actualizando = true);
    final errores = <String>[];
    await Future.wait([
      actualizarComparacionPrecios(widget.db, forzar: true).catchError((error) => errores.add('SEPA: $error')),
      actualizarComparacionPreciosTodoATuCasa(widget.db, forzar: true).catchError((error) => errores.add('Todo a tu Casa: $error')),
    ]);
    await _cargar();
    if (mounted && errores.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar del todo: ${errores.join(' | ')}')));
    }
    if (mounted) setState(() => _actualizando = false);
  }

  // "Lenguaje de diseño" (mock `CompararPrecios`): la lista de productos a
  // la izquierda (lo que más se aleja primero) y el elegido a la derecha,
  // con cada comercio en su fila. El mock comparaba costos de varios
  // proveedores por producto; acá cada producto tiene un solo proveedor, y
  // lo que se compara es mi precio contra los súper — se tomó la
  // distribución, no ese modelo.
  @override
  Widget build(BuildContext context) {
    if (_cargando) return const SizedBox.shrink();
    final visibles = [
      for (final c in _comparaciones)
        if (coincideBusqueda(c.nombre, _busqueda)) c,
    ];
    final elegido = visibles.where((c) => c.productoId == _elegidoId).firstOrNull ?? visibles.firstOrNull;

    return PantallaGestion(
      db: widget.db,
      // Se abre desde Proveedores ("Más acciones"), ya no es un apartado del
      // menú: la navbar muestra Proveedores como sección activa.
      claveActiva: 'proveedores',
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
      titulo: 'Comparar precios',
      busqueda: BusquedaContextual(pista: 'Buscar producto', alCambiar: (t) => setState(() => _busqueda = t)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ActionChip(
                avatar: const Icon(IconosPlazoleta.arrowBackRounded, size: 18),
                label: const Text('Proveedores'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: Espaciado.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu precio al lado del de los súper, para ver qué quedó muy caro o muy barato.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario),
                    ),
                  ],
                ),
              ),
              _AccionActualizar(ultima: _ultimaActualizacion, actualizando: _actualizando, onActualizar: _actualizarAhora),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
          Expanded(
            child: _comparaciones.isEmpty
                ? const EstadoVacio(
                    mensaje: 'Todavía no hay nada para comparar — actualizá arriba a la derecha.',
                    icono: IconosPlazoleta.compareArrowsOutlined,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 420,
                        child: visibles.isEmpty
                            ? const EstadoVacio(mensaje: 'Ningún producto coincide')
                            : ListView.separated(
                                itemCount: visibles.length,
                                separatorBuilder: (_, _) => const SizedBox(height: Espaciado.xs + 2),
                                itemBuilder: (context, i) => _ItemLista(
                                  comparacion: visibles[i],
                                  elegido: visibles[i].productoId == elegido?.productoId,
                                  onTap: () => setState(() => _elegidoId = visibles[i].productoId),
                                ),
                              ),
                      ),
                      const SizedBox(width: Espaciado.lg),
                      Expanded(
                        child: elegido == null
                            ? const SizedBox.shrink()
                            : _Detalle(comparacion: elegido, producto: _productos[elegido.productoId]),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatear(ComparacionPrecio c, int centavos) => c.esPesable ? '${formatearARS(centavos)}/kg' : formatearARS(centavos);

String _porcentaje(double d) {
  final t = '${(d.abs() * 100).toStringAsFixed(0)} %';
  return d > 0 ? '+$t' : (d < 0 ? '−$t' : t);
}

class _ItemLista extends StatelessWidget {
  const _ItemLista({required this.comparacion, required this.elegido, required this.onTap});

  final ComparacionPrecio comparacion;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final n = comparacion.preciosPorComercio.length;
    final dif = comparacion.mayorDiferenciaAbs;
    return Presionable(
      radio: 16,
      color: elegido ? colores.acento.withValues(alpha: 0.18) : colores.fondoBloque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comparacion.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(fontWeight: Pesos.fuerte),
                  ),
                  Text(n == 0 ? 'Sin datos en los súper' : (n == 1 ? '1 comercio' : '$n comercios'), style: textTheme.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatear(comparacion, comparacion.miPrecioCentavos),
                  style: textTheme.titleSmall?.copyWith(fontWeight: Pesos.fuerte).tabular,
                ),
                Text(dif == null ? 'mi precio' : 'hasta ${(dif * 100).toStringAsFixed(0)} %', style: textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.comparacion, required this.producto});

  final ComparacionPrecio comparacion;
  final Producto? producto;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final c = comparacion;
    final costo = producto == null ? null : (c.esPesable ? producto!.costoPorKiloCentavos : producto!.costoCentavos);
    final comercios = c.preciosPorComercio.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final esAproximado = c.tipoCoincidencia == 'nombre';
    final estiloEncabezado = textTheme.labelMedium?.copyWith(color: colores.textoSecundario);
    return ListView(
      children: [
        Superficie(
          padding: const EdgeInsets.all(Espaciado.xl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nombre, style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte)),
                    if (esAproximado)
                      // Cruce por nombre (solo pesables): aproximado, no
                      // exacto como el de código de barras — se avisa en vez
                      // de mostrarlo con la misma confianza.
                      Text('Cruzado por nombre (los pesables no tienen código): puede ser aproximado.', style: textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Mi precio', style: estiloEncabezado),
                  Text(_formatear(c, c.miPrecioCentavos), style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte).tabular),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.md),
        Superficie(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
                child: Row(
                  children: [
                    Expanded(child: Text('Comercio', style: estiloEncabezado)),
                    SizedBox(
                      width: 140,
                      child: Text('Precio', textAlign: TextAlign.right, style: estiloEncabezado),
                    ),
                    SizedBox(
                      width: 140,
                      child: Text('Contra el mío', textAlign: TextAlign.right, style: estiloEncabezado),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (comercios.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Espaciado.xl),
                  child: Text('No apareció en ningún comercio.', style: textTheme.bodyMedium),
                ),
              for (final (i, e) in comercios.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(e.key, style: textTheme.titleSmall?.copyWith(fontWeight: Pesos.fuerte)),
                            ),
                            if (i == 0 && comercios.length > 1) ...[
                              const SizedBox(width: Espaciado.sm),
                              const Insignia(texto: 'Más barato'),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Text(
                          _formatear(c, e.value),
                          textAlign: TextAlign.right,
                          style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Text(
                          // Informativo, sin color de alerta (comentario de
                          // cabecera): más caro o más barato es un dato.
                          _porcentaje((e.value - c.miPrecioCentavos) / c.miPrecioCentavos),
                          textAlign: TextAlign.right,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium).tabular,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (costo != null && costo > 0) ...[
          const SizedBox(height: Espaciado.md),
          TarjetaIndicador(
            etiqueta: 'Con tu costo',
            valor: formatearARS(c.miPrecioCentavos - costo),
            nota:
                'de ganancia por ${c.esPesable ? 'kilo' : 'unidad'} · costo ${_formatear(c, costo)} · ganancia ${c.miPrecioCentavos > 0 ? (gananciaBpDesdeCostoYPrecio(costo, c.miPrecioCentavos) / 100).round() : 0} %',
          ),
        ],
      ],
    );
  }
}

class _AccionActualizar extends StatelessWidget {
  const _AccionActualizar({required this.ultima, required this.actualizando, required this.onActualizar});

  final DateTime? ultima;
  final bool actualizando;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ultima == null ? 'Sin actualizar todavía' : 'Actualizado ${_fechaCorta(ultima!)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
        ),
        const SizedBox(width: Espaciado.md),
        TextButton(
          onPressed: actualizando ? null : onActualizar,
          child: actualizando
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Actualizar ahora'),
        ),
      ],
    );
  }
}

String _fechaCorta(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)} ${dos(f.hour)}:${dos(f.minute)}';
}
