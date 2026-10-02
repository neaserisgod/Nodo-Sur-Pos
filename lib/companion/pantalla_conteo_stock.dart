// Conteo de stock, rediseñado (El dueño, 2026-09-07: "el conteo de stock es
// muy nefasto"): mismo menú que la app de escritorio — listar proveedores,
// al entrar listar los productos de ese proveedor con su stock real
// (solo lectura) y un recuadro para el conteo. Vacío = el stock guardado
// ya está bien, no se toca.
//
// El buscador con precio (El dueño: "nada que ver con el tema de conteo")
// vive en la pantalla principal del menú (`pantalla_menu_companion.dart`),
// no acá — esta pantalla es solo el flujo proveedor → productos.
//
// "Sin stock" (El dueño, 2026-09-07: "yo debería poder revisar los productos
// sin stock desde la app Android para ajustarlos") — un segundo punto de
// entrada, arriba de la lista de proveedores, que salta directo a los
// agotados de TODOS los proveedores juntos en vez de tener que entrar
// proveedor por proveedor buscando ceros. Comparte la misma pantalla de
// conteo (`PantallaConteoProductos`, extraída de acá) — la única
// diferencia es de dónde sale la lista de productos.

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart'
    show ErrorCompanion, ProductoCompanion, ProveedorCompanion;
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'seleccion_servicio.dart';
import 'tema/chip_icono.dart';
import 'tema/esqueleto_companion.dart';
import '../ui/comun/estado_error.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

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
  bool _cargandoProveedores = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  /// Sin usuario elegido, error explícito con reintentar (no debería pasar
  /// normalmente — se llega acá recién con usuario elegido). Sin PC
  /// emparejada (El dueño, 2026-09-18: "no debería tener que escanear ya, es
  /// innecesario") cae a la base local sincronizada por Supabase, no es un
  /// error.
  Future<void> _iniciar() async {
    setState(() {
      _cargandoProveedores = true;
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
      final proveedores = await cliente.proveedores();
      if (mounted) setState(() => _proveedores = proveedores);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargandoProveedores = false);
    }
  }

  void _abrirProveedor(ProveedorCompanion proveedor) {
    pushSinTeclado(
      context,
      (_) => PantallaConteoProductos(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        titulo: proveedor.nombre,
        cargarProductos: () => _cliente!.productos(proveedorId: proveedor.id),
      ),
    );
  }

  void _abrirSinStock() {
    pushSinTeclado(
      context,
      (_) => PantallaConteoProductos(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        titulo: 'Sin stock',
        cargarProductos: () => _cliente!.productosSinStock(),
        mostrarProveedor: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conteo de stock')),
      body: SafeArea(
        child: _cargandoProveedores
            ? const EsqueletoLista()
            : _error != null
            ? EstadoError(mensaje: _error!, onReintentar: _iniciar)
            : Column(
                children: [
                  AvisoModoLocal(servicio: _cliente, pcEmparejada: _pcEmparejada),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _iniciar,
                      // `ListTile` crudo sin padding de pantalla ni `Bloque`
                      // (El dueño, 2026-09-13: "se ve muy genérica") — el resto
                      // de la companion usa tarjetas propias (`_TileCompacta`
                      // en Gestión/Más) para cualquier lista de accesos;
                      // esta pantalla se había quedado con el estilo
                      // Material de fábrica desde antes de que existiera ese
                      // patrón.
                      child: ListView.builder(
                        padding: const EdgeInsets.all(Espaciado.lg),
                        itemCount: _proveedores.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Espaciado.sm),
                              child: _TileProveedor(
                                icono: IconosPlazoleta.productionQuantityLimits,
                                iconoColor: context.colores.error,
                                titulo: 'Sin stock',
                                subtitulo: 'Todos los proveedores juntos',
                                onTap: _abrirSinStock,
                              ),
                            );
                          }
                          final p = _proveedores[i - 1];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: Espaciado.sm),
                            child: _TileProveedor(
                              icono: IconosPlazoleta.storefrontOutlined,
                              titulo: p.nombre,
                              subtitulo: p.codigo,
                              onTap: () => _abrirProveedor(p),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Fila de acceso con el mismo lenguaje visual que el resto de la
/// companion (`Bloque` + ícono + título/subtítulo + flecha) — se repite
/// como widget propio en vez de compartirse (Regla 3 aplica a fórmulas de
/// dominio, no a un widget visual de cuatro líneas como este).
class _TileProveedor extends StatelessWidget {
  const _TileProveedor({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.iconoColor,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final Color? iconoColor;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      padding: EdgeInsets.zero,
      child: Presionable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Espaciado.lg,
            vertical: Espaciado.md,
          ),
          child: Row(
            children: [
              ChipIcono(icono: icono, color: iconoColor ?? context.colores.textoSecundario),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      subtitulo,
                      style: TextStyle(color: context.colores.textoSecundario),
                    ),
                  ],
                ),
              ),
              Icon(IconosPlazoleta.chevronRight, color: context.colores.textoTenue),
            ],
          ),
        ),
      ),
    );
  }
}

/// El conteo en sí — lista de productos con el stock guardado (solo
/// lectura) y un campo para el valor real. [cargarProductos] es lo único
/// que cambia entre "por proveedor" y "sin stock, todos juntos"
/// (Regla 3: una sola pantalla de conteo, no dos casi iguales).
class PantallaConteoProductos extends StatefulWidget {
  const PantallaConteoProductos({
    super.key,
    required this.cliente,
    required this.usuarioId,
    required this.titulo,
    required this.cargarProductos,
    this.mostrarProveedor = false,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final String titulo;
  final Future<List<ProductoCompanion>> Function() cargarProductos;

  /// true en "Sin stock" (productos de proveedores distintos mezclados) —
  /// agrega el proveedor como subtítulo para no perder ese contexto. Falso
  /// en "por proveedor", donde ya es el título de la pantalla.
  final bool mostrarProveedor;

  @override
  State<PantallaConteoProductos> createState() =>
      _PantallaConteoProductosState();
}

class _PantallaConteoProductosState extends State<PantallaConteoProductos> {
  List<ProductoCompanion> _productos = [];
  List<ProveedorCompanion> _proveedores = [];
  final Map<int, TextEditingController> _controladores = {};
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  /// Sin esto, el botón atrás del sistema salía directo perdiendo un
  /// conteo físico a medio recorrer (hasta 30-80 campos tipeados) sin
  /// avisar nada.
  bool get _hayDatosSinGuardar =>
      _controladores.values.any((c) => c.text.trim().isNotEmpty);

  /// Cuántos productos ya tienen un valor tipeado, de los que hay en
  /// pantalla — se muestra en el botón de guardar para que recorrer la
  /// góndola no sea "sin ningún indicio de cuánto falta".
  int get _cantidadContados =>
      _controladores.values.where((c) => c.text.trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _controladores.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resultados = await Future.wait([
        widget.cargarProductos(),
        widget.mostrarProveedor
            ? widget.cliente.proveedores()
            : Future.value(_proveedores),
      ]);
      final productos = resultados[0] as List<ProductoCompanion>;
      for (final p in productos) {
        // El listener alimenta `_cantidadContados` — sin él, tipear no
        // reconstruye la pantalla y el contador del botón de guardar
        // quedaría siempre en 0 (Regla de este archivo: en una lista de
        // 30-80 productos hace falta saber a mitad de camino cuánto falta).
        _controladores.putIfAbsent(p.id, () {
          final c = TextEditingController();
          c.addListener(() => setState(() {}));
          return c;
        });
      }
      if (mounted) {
        setState(() {
          _productos = productos;
          _proveedores = resultados[1] as List<ProveedorCompanion>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String? _nombreProveedor(int? proveedorId) {
    if (proveedorId == null) return null;
    for (final p in _proveedores) {
      if (p.id == proveedorId) return p.nombre;
    }
    return null;
  }

  /// Guarda solo los productos con un valor tipeado — el resto se deja tal
  /// cual está guardado (El dueño: "si no se pone nada se asume que el stock
  /// guardado es correcto").
  ///
  /// Las requests salen todas juntas, no una detrás de la otra: un conteo
  /// físico real recorre la góndola y puede terminar con 30-80 productos
  /// tipeados de una — esperar cada `ajustarStock` en serie significaba esa
  /// cantidad de round-trips WiFi seguidos, con el spinner de "guardando"
  /// visible todo ese tiempo. Se validan y se lanzan todos los futures de
  /// una (sin `await` inmediato: ya empiezan a viajar), y recién ahí se
  /// esperan uno por uno para poder seguir atribuyendo cada error a SU
  /// producto — igual que antes, solo que en paralelo.
  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });

    final errores = <String>[];
    final pendientes = <(ProductoCompanion, Future<void>)>[];
    for (final producto in _productos) {
      final texto = _controladores[producto.id]!.text.trim();
      if (texto.isEmpty) continue;
      final valor = int.tryParse(texto);
      if (valor == null || valor < 0) {
        errores.add('${producto.nombre}: número inválido');
        continue;
      }
      pendientes.add((
        producto,
        widget.cliente.ajustarStock(
          producto.id,
          stock: producto.esPesable ? producto.stock : valor,
          stockGramos: producto.esPesable ? valor : null,
          motivo: 'Conteo físico',
          usuarioId: widget.usuarioId,
        ),
      ));
    }

    var guardados = 0;
    for (final (producto, future) in pendientes) {
      try {
        await future;
        guardados++;
      } catch (e) {
        errores.add('${producto.nombre}: ${mensajeDeError(e)}');
      }
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    // `SnackBar`, no un texto fijo arriba de la lista: después de recorrer
    // 30-80 productos la lista queda scrolleada a la mitad o al final, y
    // un texto arriba del todo quedaba invisible fuera de pantalla sin
    // ningún indicio de que había que volver a scrollear para verlo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errores.isEmpty
              ? (guardados == 0
                    ? 'No había nada para guardar'
                    : 'Guardado — $guardados producto(s) actualizados')
              : '$guardados guardado(s), con errores: ${errores.join('; ')}',
        ),
      ),
    );
    if (guardados > 0) {
      for (final c in _controladores.values) {
        c.clear();
      }
      await _cargar(); // trae el stock ya actualizado para mostrarlo — en
      // "Sin stock" esto también saca de la lista lo que ya se contó y
      // dejó de estar en cero.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Siempre `false`: los controllers de conteo cambian sin pasar por
      // `setState` (no hace falta rebuild por cada tecla en 30-80 campos),
      // así que `_hayDatosSinGuardar` se evalúa fresco recién acá adentro,
      // no en un `canPop` que podría quedar desactualizado.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hayDatosSinGuardar || await confirmarSalirSinGuardar(context)) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(IconosPlazoleta.saveOutlined),
          label: Text(
            _cantidadContados == 0
                ? 'Guardar conteo'
                : 'Guardar conteo ($_cantidadContados de ${_productos.length})',
          ),
        ),
        body: SafeArea(
          child: _cargando
              ? const EsqueletoLista()
              : Column(
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(Espaciado.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: ErrorEnLinea(_error!),
                            ),
                            TextButton(
                              onPressed: _cargar,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    if (!_cargando && _productos.isEmpty)
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _cargar,
                          child: ListView(
                            children: [
                              SizedBox(
                                height: 300,
                                child: EstadoVacio(
                                  mensaje: widget.mostrarProveedor
                                      ? 'Nada sin stock — todo contado'
                                      : 'Sin productos acá',
                                  icono: widget.mostrarProveedor
                                      ? IconosPlazoleta.checkCircleOutline
                                      : IconosPlazoleta.inventory2Outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _cargar,
                          child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            Espaciado.lg,
                            Espaciado.sm,
                            Espaciado.lg,
                            80, // lugar para el FloatingActionButton
                          ),
                          itemCount: _productos.length,
                          itemBuilder: (context, i) {
                            final p = _productos[i];
                            final stockGuardado = p.esPesable
                                ? '${p.stockGramos ?? 0} g'
                                : '${p.stock} un.';
                            final proveedor = widget.mostrarProveedor
                                ? _nombreProveedor(p.proveedorId)
                                : null;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: Espaciado.xs,
                              ),
                              child: Superficie(
                                // Antes usaba el padding parejo de `Bloque`
                                // (16 arriba y abajo) — en una lista de
                                // 30-80 productos (recorrer la góndola
                                // entera) eso hacía que cada fila ocupara
                                // demasiado espacio vertical (El dueño,
                                // 2026-09-13). Menos padding vertical que
                                // horizontal es suficiente acá: la fila ya
                                // tiene su propio aire por el contenido.
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Espaciado.lg,
                                  vertical: Espaciado.sm,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.nombre,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          Text(
                                            proveedor == null
                                                ? 'Guardado: $stockGuardado'
                                                : '$proveedor · Guardado: $stockGuardado',
                                            style: TextStyle(
                                              color: context
                                                  .colores
                                                  .textoSecundario,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: Espaciado.md),
                                    Expanded(
                                      flex: 2,
                                      // `TextField` crudo a propósito acá, no
                                      // `CampoTexto` del kit: este campo vive
                                      // en una fila densa de una lista que
                                      // puede tener decenas de productos (el
                                      // conteo físico recorriendo la góndola)
                                      // — necesita teclado numérico, texto
                                      // centrado e `isDense`, que el kit no
                                      // ofrece, y envolverlo en `Bloque` con
                                      // etiqueta fija arriba le agregaría
                                      // altura a cada fila sin necesidad.
                                      // `hintText` (no `labelText`): un label
                                      // flotante reserva espacio vertical
                                      // fijo para el estado "con contenido"
                                      // aunque el campo esté vacío — en una
                                      // lista de 30-80 filas eso solo
                                      // pesa (El dueño, 2026-09-13: "las cards
                                      // ocupan demasiado espacio vertical").
                                      child: TextField(
                                        controller: _controladores[p.id],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          hintText: p.esPesable
                                              ? 'Gramos'
                                              : 'Unidades',
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: Espaciado.sm,
                                            vertical: Espaciado.sm,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
