// Conteo de stock (mock completo del celular, 2026-10-02): una sola pantalla
// para recorrer la góndola. Arriba se elige el proveedor ("Todos juntos" o uno)
// y, si hace falta, el filtro "Sin stock"; abajo, un producto por fila con su
// stock del sistema y un campo numérico con −/+ para cargar lo contado.
//
// Las reglas no cambiaron respecto de la versión anterior (El dueño,
// 2026-09-07, "el conteo de stock es muy nefasto"):
//  * Un campo vacío significa que el stock guardado está bien y NO se toca. El
//    número del sistema se muestra apagado hasta que se carga algo propio.
//  * Lo que se guarda es el valor contado (absoluto), no una diferencia, con el
//    motivo "Conteo físico" para que el movimiento de stock deje rastro
//    (Convención 6).
//  * Cambiar de proveedor o de filtro no pierde lo ya cargado: lo contado vive
//    por producto, no por lista. El botón de guardar dice cuántos hay cargados.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/comun/estado_error.dart';
import '../ui/comun/estado_vacio.dart';
import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart' show ErrorCompanion, ProductoCompanion, ProveedorCompanion;
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/app_bar_companion.dart';
import 'tema/chip_seleccionable.dart';
import 'tema/error_en_linea.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/superficie.dart';

class PantallaConteoStock extends StatefulWidget {
  const PantallaConteoStock({super.key});

  @override
  State<PantallaConteoStock> createState() => _PantallaConteoStockState();
}

class _PantallaConteoStockState extends State<PantallaConteoStock> {
  ServicioCompanion? _cliente;
  bool _pcEmparejada = false;
  int? _usuarioId;

  List<ProveedorCompanion> _proveedores = [];
  List<ProductoCompanion> _productos = [];

  /// Los que el sistema considera sin stock (`productosSinStock`): una sola
  /// definición para las dos formas de verlos (Convención 3).
  Set<int> _sinStockIds = {};

  /// null = "Todos juntos".
  int? _proveedorId;
  bool _soloSinStock = false;

  /// Un campo por producto, creado al cargar y conservado al cambiar de
  /// proveedor o de filtro. Vacío = sin tocar.
  final Map<int, TextEditingController> _controladores = {};

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  /// Sin esto, el botón atrás del sistema salía directo perdiendo un conteo
  /// físico a medio recorrer (hasta 30-80 campos) sin avisar nada.
  bool get _hayDatosSinGuardar => _cantidadContados > 0;

  /// Cuántos productos tienen un valor cargado, estén o no a la vista.
  int get _cantidadContados => _controladores.values.where((c) => c.text.trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Sin usuario elegido, error explícito con reintentar (no debería pasar
  /// normalmente). Sin PC emparejada cae a la base local sincronizada, no es
  /// un error (El dueño, 2026-09-18: "no debería tener que escanear ya").
  Future<void> _iniciar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final conexion = await leerConexion();
      final usuario = await leerUsuario();
      if (usuario == null) {
        throw const ErrorCompanion(0, 'Falta elegir usuario.');
      }
      final cliente = conexion == null
          ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
          : await resolverServicioCompanion(conexion);
      if (!mounted) return;
      setState(() {
        _cliente = cliente;
        _pcEmparejada = conexion != null;
        _usuarioId = usuario.id;
      });
      await _cargarCatalogo();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Trae proveedores, productos y cuáles están sin stock. Conserva lo ya
  /// cargado en los campos: sirve tanto para el primer arranque como para
  /// refrescar después de guardar.
  Future<void> _cargarCatalogo() async {
    final cliente = _cliente!;
    final resultados = await Future.wait([cliente.proveedores(), cliente.productos(), cliente.productosSinStock()]);
    final productos = resultados[1] as List<ProductoCompanion>;
    for (final p in productos) {
      // El listener alimenta el contador del botón de guardar: sin él, tipear
      // no reconstruye la pantalla y quedaría siempre en 0.
      _controladores.putIfAbsent(p.id, () {
        final c = TextEditingController();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        return c;
      });
    }
    if (!mounted) return;
    setState(() {
      _proveedores = resultados[0] as List<ProveedorCompanion>;
      _productos = productos;
      _sinStockIds = {for (final p in resultados[2] as List<ProductoCompanion>) p.id};
    });
  }

  List<ProductoCompanion> get _visibles => [
    for (final p in _productos)
      if ((_proveedorId == null || p.proveedorId == _proveedorId) && (!_soloSinStock || _sinStockIds.contains(p.id))) p,
  ];

  String? _nombreProveedor(int? id) {
    if (id == null) return null;
    for (final p in _proveedores) {
      if (p.id == id) return p.nombre;
    }
    return null;
  }

  /// Guarda solo los productos con un valor cargado: el resto queda como está
  /// (El dueño: "si no se pone nada se asume que el stock guardado es
  /// correcto"). Las requests salen todas juntas y se esperan una por una para
  /// atribuir cada error a SU producto: un conteo real puede tener 30-80
  /// productos y en serie serían otros tantos viajes de WiFi con el spinner
  /// a la vista.
  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });

    final errores = <String>[];
    final pendientes = <(ProductoCompanion, Future<void>)>[];
    for (final producto in _productos) {
      final texto = _controladores[producto.id]?.text.trim() ?? '';
      if (texto.isEmpty) continue;
      final valor = int.tryParse(texto);
      if (valor == null || valor < 0) {
        errores.add('${producto.nombre}: número inválido');
        continue;
      }
      pendientes.add((
        producto,
        _cliente!.ajustarStock(
          producto.id,
          stock: producto.esPesable ? producto.stock : valor,
          stockGramos: producto.esPesable ? valor : null,
          motivo: 'Conteo físico',
          usuarioId: _usuarioId!,
        ),
      ));
    }

    final guardadosOk = <int>{};
    for (final (producto, future) in pendientes) {
      try {
        await future;
        guardadosOk.add(producto.id);
      } catch (e) {
        errores.add('${producto.nombre}: ${mensajeDeError(e)}');
      }
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    // `SnackBar` y no un texto arriba de la lista: tras recorrer 30-80
    // productos la lista queda scrolleada y un aviso fijo arriba no se vería.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errores.isEmpty
              ? (guardadosOk.isEmpty ? 'No había nada para guardar' : 'Guardado — ${guardadosOk.length} producto(s) actualizados')
              : '${guardadosOk.length} guardado(s), con errores: ${errores.join('; ')}',
        ),
      ),
    );
    if (guardadosOk.isNotEmpty) {
      // Solo se limpian los que se guardaron: lo que dio error queda cargado
      // para corregirlo o reintentarlo sin volver a tipearlo.
      for (final id in guardadosOk) {
        _controladores[id]?.clear();
      }
      try {
        await _cargarCatalogo();
      } catch (e) {
        if (mounted) setState(() => _error = mensajeDeError(e));
      }
    }
  }

  Future<void> _volver() async {
    if (!_hayDatosSinGuardar || await confirmarSalirSinGuardar(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Un toque en − o + parte del valor del sistema si todavía no se cargó nada.
  void _ajustar(ProductoCompanion p, int delta) {
    final c = _controladores[p.id]!;
    final base = int.tryParse(c.text.trim()) ?? p.stock;
    final nuevo = base + delta;
    c.text = '${nuevo < 0 ? 0 : nuevo}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Siempre `false`: se decide fresco adentro del callback, no con un
      // `canPop` calculado en un build anterior.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _volver();
      },
      child: Scaffold(
        appBar: const AppBarCompanion(titulo: 'Conteo de stock', etiquetaSalida: null),
        body: SafeArea(
          child: _cargando
              ? const EsqueletoLista()
              : _cliente == null
              ? EstadoError(mensaje: _error ?? 'No se pudo conectar.', onReintentar: _iniciar)
              : Column(
                  children: [
                    AvisoModoLocal(servicio: _cliente, pcEmparejada: _pcEmparejada),
                    _filtros(context),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, 0),
                        child: ErrorEnLinea(_error!),
                      ),
                    Expanded(child: _lista(context)),
                    _pie(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _etiqueta(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.sm, Espaciado.xl, Espaciado.xs),
    child: Text(
      texto,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.colores.textoSecundario, fontWeight: Pesos.fuerte),
    ),
  );

  Widget _filtros(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Proveedor'),
        // Todos a la vista, acomodados en varias líneas como en el mock: en una
        // fila que se desliza los últimos proveedores quedaban escondidos. Con
        // muchos proveedores la franja tiene tope y scrollea para no comerse la lista.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: Espaciado.sm,
                runSpacing: Espaciado.sm,
                children: [
                  ChipSeleccionable(texto: 'Todos juntos', seleccionado: _proveedorId == null, onTap: () => setState(() => _proveedorId = null)),
                  for (final p in _proveedores)
                    ChipSeleccionable(texto: p.nombre, seleccionado: _proveedorId == p.id, onTap: () => setState(() => _proveedorId = p.id)),
                ],
              ),
            ),
          ),
        ),
        _etiqueta('Filtro'),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
            children: [
              ChipSeleccionable(texto: 'Todos', seleccionado: !_soloSinStock, onTap: () => setState(() => _soloSinStock = false)),
              const SizedBox(width: Espaciado.sm),
              ChipSeleccionable(texto: 'Sin stock', seleccionado: _soloSinStock, onTap: () => setState(() => _soloSinStock = true)),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.sm),
      ],
    );
  }

  Widget _lista(BuildContext context) {
    final visibles = _visibles;
    if (visibles.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargarCatalogo,
        child: ListView(
          children: [
            SizedBox(
              height: 280,
              child: EstadoVacio(
                mensaje: _soloSinStock ? 'Nada sin stock — todo contado' : 'Sin productos acá',
                icono: _soloSinStock ? IconosPlazoleta.checkCircleOutline : IconosPlazoleta.inventory2Outlined,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargarCatalogo,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.md),
        itemCount: visibles.length,
        itemBuilder: (context, i) {
          final p = visibles[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: Espaciado.xs),
            child: _FilaConteo(
              // La clave por producto evita que, al filtrar, el campo de una
              // fila herede el texto de otra que ocupaba su lugar.
              key: ValueKey(p.id),
              producto: p,
              controlador: _controladores[p.id]!,
              proveedor: _proveedorId == null ? _nombreProveedor(p.proveedorId) : null,
              onMenos: () => _ajustar(p, -1),
              onMas: () => _ajustar(p, 1),
            ),
          );
        },
      ),
    );
  }

  Widget _pie(BuildContext context) {
    final n = _cantidadContados;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _guardando || n == 0 ? null : _guardar,
            child: _guardando
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(n == 0 ? 'Guardar conteo' : 'Guardar conteo ($n)'),
          ),
          const SizedBox(height: Espaciado.sm),
          OutlinedButton(onPressed: _guardando ? null : _volver, child: const Text('Volver')),
        ],
      ),
    );
  }
}

/// Un producto del conteo: nombre y stock del sistema a la izquierda; a la
/// derecha el campo de lo contado (con −/+ por unidad; los pesables, que van en
/// gramos, solo llevan el campo).
class _FilaConteo extends StatelessWidget {
  const _FilaConteo({
    super.key,
    required this.producto,
    required this.controlador,
    required this.proveedor,
    required this.onMenos,
    required this.onMas,
  });

  final ProductoCompanion producto;
  final TextEditingController controlador;
  final String? proveedor;
  final VoidCallback onMenos;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final sistema = p.esPesable ? p.stockGramos ?? 0 : p.stock;
    final unidad = p.esPesable ? 'g' : 'u.';
    final cargado = controlador.text.trim().isNotEmpty;
    return Superficie(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium),
                Text(
                  proveedor == null ? 'Sistema: $sistema $unidad' : '$proveedor · Sistema: $sistema $unidad',
                  style: textTheme.bodySmall?.copyWith(color: sistema <= 0 ? colores.error : colores.textoSecundario),
                ),
              ],
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          DecoratedBox(
            decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!p.esPesable)
                  IconButton(tooltip: 'Uno menos', visualDensity: VisualDensity.compact, icon: const Icon(IconosPlazoleta.remove), onPressed: onMenos),
                SizedBox(
                  width: p.esPesable ? 96 : 56,
                  child: TextField(
                    controller: controlador,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    // Vacío se ve el número del sistema, apagado: es lo que se
                    // asume si no se toca. Al cargar algo propio pasa a tinta.
                    style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte, color: cargado ? colores.textoPrimario : colores.textoTenue),
                    decoration: InputDecoration(
                      hintText: '$sistema',
                      hintStyle: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte, color: colores.textoTenue),
                      suffixText: p.esPesable ? 'g' : null,
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
                    ),
                  ),
                ),
                if (!p.esPesable)
                  IconButton(tooltip: 'Uno más', visualDensity: VisualDensity.compact, icon: const Icon(IconosPlazoleta.add), onPressed: onMas),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
