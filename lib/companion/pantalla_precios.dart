// "Productos" — pestaña propia de la navbar (Bruno, 2026-09-19: "productos
// pasa a ser la segunda pantalla más importante después de vender"),
// promovida desde adentro de Gestión, donde competía por espacio con
// Conteo de stock y Carga histórica sin merecerlo. Buscar por nombre, más
// los filtros de higiene de catálogo (`_FiltroCatalogo`, más abajo); el
// alta/edición completa vive en `pantalla_formulario_producto.dart` (hoja
// de vidrio, compartida con el escáner central,
// `boton_escaner_companion.dart`) — el botón de escanear que tenía esta
// pantalla se sacó de acá porque quedó redundante con ese (Bruno: "que
// quede como búsqueda por nombre"). Sin `AppBar`, mismo criterio que el
// resto de las pestañas raíz (Inicio/Historial/Gestión): título grande en
// el cuerpo, no una franja fija arriba.

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/markup.dart';
import '../ui/comun/tarjetas.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'emparejamiento.dart';
import 'hoja_edicion_masiva.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'pantalla_formulario_producto.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/chip_seleccionable.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/estado_error_companion.dart';
import 'tema/estado_vacio_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class PantallaPrecios extends StatefulWidget {
  const PantallaPrecios({super.key});

  @override
  State<PantallaPrecios> createState() => _PantallaPreciosState();
}

class _PantallaPreciosState extends State<PantallaPrecios> {
  ServicioCompanion? _cliente;
  bool _pcEmparejada = false;
  int? _usuarioId;
  List<ProveedorCompanion> _proveedores = [];
  List<CategoriaCompanion> _categorias = [];

  final _busquedaCtrl = TextEditingController();
  final _debouncer = Debouncer();
  List<ProductoCompanion> _resultados = [];
  bool _buscando = false;
  bool _cargandoInicial = true;
  String? _error;

  /// Pulido del catálogo (Bruno, 2026-09-19: "filtrar por productos sin
  /// proveedor, sin costo, etcétera") — cada uno se combina con lo que haya
  /// tipeado en el buscador, no lo reemplaza: se puede acotar "sin costo" a
  /// un nombre en particular. "Todos" es `ninguno`, sin filtro activo.
  _FiltroCatalogo _filtro = _FiltroCatalogo.ninguno;

  /// "Por proveedor" (Bruno, 2026-09-19, segunda vuelta del editor masivo:
  /// "llegó un pedido de un proveedor" / "un proveedor subió precios") es un
  /// filtro más, pero necesita ELEGIR cuál — no es un flag booleano como los
  /// de `_FiltroCatalogo`, así que vive en su propio estado en vez de sumar
  /// un caso más a ese enum. Mutuamente excluyente con `_filtro`: elegir uno
  /// limpia el otro (`_elegirFiltro`/`_elegirPorProveedor`).
  int? _proveedorFiltroId;
  String? _proveedorFiltroNombre;

  /// Editor masivo — mantener presionada una fila entra al modo selección
  /// (mismo gesto que Gmail/Archivos). Funciona en CUALQUIER contexto
  /// (Bruno, 2026-09-19: "no funciona la parte de mantener apretado para
  /// seleccionar" — antes solo respondía en los tres contextos con una
  /// acción real, así que en la vista normal de búsqueda mantener
  /// presionado no hacía nada, sin ningún aviso; parecía roto). Ahora
  /// siempre se puede seleccionar; lo que cambia según el contexto es qué
  /// hace el botón de abajo con esa selección (`_etiquetaEdicionMasiva`/
  /// `_abrirEdicionMasiva`).
  final Set<int> _seleccionados = {};
  bool get _enSeleccion => _seleccionados.isNotEmpty;

  void _alternarSeleccion(int id) {
    setState(() {
      if (!_seleccionados.remove(id)) _seleccionados.add(id);
    });
  }

  /// Cuál hoja abrir depende de POR QUÉ se está seleccionando (Bruno,
  /// 2026-09-19: "las opciones que da no se correlacionan con el editor
  /// como tal" — la versión anterior ofrecía las mismas siete opciones sin
  /// importar el contexto). Acá no hay "elegí una acción cualquiera": cada
  /// contexto tiene una sola hoja con sentido — y si el contexto actual no
  /// tiene ninguna (ej. seleccionando desde la búsqueda normal), lo dice en
  /// vez de quedarse en silencio (mismo motivo de más arriba).
  Future<void> _abrirEdicionMasiva(BuildContext context) async {
    final Widget hoja;
    if (_proveedorFiltroId != null) {
      hoja = HojaEdicionMasiva.porProveedor(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        productoIds: _seleccionados.toList(),
        nombreProveedor: _proveedorFiltroNombre!,
      );
    } else if (_filtro == _FiltroCatalogo.sinProveedor) {
      hoja = HojaEdicionMasiva.asignarProveedor(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        productoIds: _seleccionados.toList(),
        proveedores: _proveedores,
      );
    } else if (_filtro == _FiltroCatalogo.sinCategoria) {
      hoja = HojaEdicionMasiva.asignarCategoria(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        productoIds: _seleccionados.toList(),
        categorias: _categorias,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para editar en lote elegí "Por proveedor" arriba, o un filtro '
            '"Sin proveedor"/"Sin categoría".',
          ),
        ),
      );
      return;
    }
    final cambio = await mostrarHojaVidrio<bool>(context, builder: (_) => hoja);
    if (cambio == true) {
      setState(() => _seleccionados.clear());
      _buscar();
    }
  }

  /// Bruno, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó" — repite la búsqueda actual sola apenas la sync trae algo
  /// nuevo, en vez de necesitar salir y volver a entrar para verlo.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    _iniciar();
    _subCambiosSync = avisosCambiosCompanion.listen((_) => _buscar());
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debouncer.dispose();
    _subCambiosSync?.cancel();
    super.dispose();
  }

  /// Sin usuario elegido, error explícito con reintentar (no debería pasar
  /// normalmente). Sin PC emparejada (Bruno, 2026-09-18: "no debería tener
  /// que escanear ya, es innecesario") cae a la base local sincronizada por
  /// Supabase, no es un error.
  Future<void> _iniciar() async {
    setState(() {
      _cargandoInicial = true;
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
      List<ProveedorCompanion> proveedores = [];
      List<CategoriaCompanion> categorias = [];
      try {
        final resultados = await Future.wait([cliente.proveedores(), cliente.categorias()]);
        proveedores = resultados[0] as List<ProveedorCompanion>;
        categorias = resultados[1] as List<CategoriaCompanion>;
      } catch (_) {
        // sin proveedores/categorías no se bloquea la pantalla — el
        // formulario los deja en "Sin proveedor"/"Sin categoría" si esta
        // lista vino vacía por lo que sea.
      }
      if (!mounted) return;
      setState(() {
        _cliente = cliente;
        _pcEmparejada = conexion != null;
        _usuarioId = usuario.id;
        _proveedores = proveedores;
        _categorias = categorias;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
    }
  }

  /// A diferencia de antes (solo por nombre), ahora también dispara con el
  /// campo vacío si hay un filtro de catálogo o de proveedor activo — "Sin
  /// proveedor"/"Por proveedor" con nada tipeado tiene que traer la lista
  /// completa, no esperar una letra.
  Future<void> _buscar() async {
    if (_cliente == null) return;
    final texto = _busquedaCtrl.text.trim();
    final filtro = _filtro;
    final proveedorId = _proveedorFiltroId;
    if (texto.isEmpty && filtro == _FiltroCatalogo.ninguno && proveedorId == null) {
      setState(() => _resultados = []);
      return;
    }
    // Identifica esta búsqueda puntual para descartar una respuesta que ya
    // no corresponde al estado actual — el mismo criterio que antes
    // comparaba solo el texto, extendido para que un cambio de filtro en
    // pleno vuelo también invalide la respuesta vieja.
    final clave = (texto, filtro, proveedorId);
    setState(() => _buscando = true);
    try {
      final resultados = await _cliente!.productos(
        busqueda: texto.isEmpty ? null : texto,
        proveedorId: proveedorId,
        sinProveedor: filtro == _FiltroCatalogo.sinProveedor,
        sinCosto: filtro == _FiltroCatalogo.sinCosto,
        sinCategoria: filtro == _FiltroCatalogo.sinCategoria,
        sinCodigoBarras: filtro == _FiltroCatalogo.sinCodigoBarras,
      );
      if (mounted && (_busquedaCtrl.text.trim(), _filtro, _proveedorFiltroId) == clave) {
        setState(() => _resultados = resultados);
      }
    } catch (e) {
      if (mounted && (_busquedaCtrl.text.trim(), _filtro, _proveedorFiltroId) == clave) {
        setState(() => _error = mensajeDeError(e));
      }
    } finally {
      if (mounted && (_busquedaCtrl.text.trim(), _filtro, _proveedorFiltroId) == clave) {
        setState(() => _buscando = false);
      }
    }
  }

  void _elegirFiltro(_FiltroCatalogo filtro) {
    setState(() {
      _filtro = filtro;
      _proveedorFiltroId = null;
      _proveedorFiltroNombre = null;
      _seleccionados.clear();
    });
    _buscar();
  }

  /// Abre el elegidor de proveedor — cancelar (sin tocar nada) deja el
  /// filtro como estaba, no lo "activa" a medias.
  Future<void> _elegirPorProveedor(BuildContext context) async {
    final elegido = await mostrarHojaVidrio<ProveedorCompanion>(
      context,
      builder: (_) => _HojaElegirProveedor(proveedores: _proveedores),
    );
    if (elegido == null) return;
    setState(() {
      _filtro = _FiltroCatalogo.ninguno;
      _proveedorFiltroId = elegido.id;
      _proveedorFiltroNombre = elegido.nombre;
      _seleccionados.clear();
    });
    _buscar();
  }

  String _mensajeVacio() {
    final hayTexto = _busquedaCtrl.text.trim().isNotEmpty;
    if (_proveedorFiltroId != null) {
      return hayTexto ? 'Sin resultados' : 'Este proveedor no tiene productos cargados';
    }
    if (!hayTexto && _filtro == _FiltroCatalogo.ninguno) {
      return 'Escribí para buscar un producto';
    }
    if (_filtro == _FiltroCatalogo.ninguno) return 'Sin resultados';
    final sinProblema = switch (_filtro) {
      _FiltroCatalogo.sinProveedor => 'Ningún producto sin proveedor',
      _FiltroCatalogo.sinCosto => 'Ningún producto sin costo',
      _FiltroCatalogo.sinCategoria => 'Ningún producto sin categoría',
      _FiltroCatalogo.sinCodigoBarras => 'Ningún producto sin código de barras',
      _FiltroCatalogo.ninguno => 'Sin resultados',
    };
    return hayTexto ? 'Sin resultados' : sinProblema;
  }

  Widget _filaFiltros(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
        children: [
          for (final filtro in _FiltroCatalogo.values) ...[
            ChipSeleccionable(
              texto: _tituloFiltro(filtro),
              seleccionado: _proveedorFiltroId == null && _filtro == filtro,
              onTap: () => _elegirFiltro(filtro),
            ),
            const SizedBox(width: Espaciado.sm),
          ],
          ChipSeleccionable(
            texto: _proveedorFiltroNombre ?? 'Por proveedor',
            seleccionado: _proveedorFiltroId != null,
            onTap: () => _elegirPorProveedor(context),
          ),
        ],
      ),
    );
  }

  String _tituloFiltro(_FiltroCatalogo filtro) => switch (filtro) {
    _FiltroCatalogo.ninguno => 'Todos',
    _FiltroCatalogo.sinProveedor => 'Sin proveedor',
    _FiltroCatalogo.sinCosto => 'Sin costo',
    _FiltroCatalogo.sinCategoria => 'Sin categoría',
    _FiltroCatalogo.sinCodigoBarras => 'Sin código',
  };

  /// Nombra el botón por lo que realmente va a hacer, no un genérico
  /// "Editar" — la queja de Bruno era justo que las opciones no se
  /// correlacionaban con el contexto; el nombre del botón es la primera
  /// señal de que ahora sí.
  String get _etiquetaEdicionMasiva {
    final n = _seleccionados.length;
    if (_proveedorFiltroId != null) return 'Editar ($n)';
    if (_filtro == _FiltroCatalogo.sinProveedor) return 'Asignar proveedor ($n)';
    if (_filtro == _FiltroCatalogo.sinCategoria) return 'Asignar categoría ($n)';
    // Seleccionando fuera de los tres contextos con acción real — el botón
    // sigue tocable (explica por qué acá no hay nada para hacer, ver
    // `_abrirEdicionMasiva`) en vez de desaparecer sin avisar.
    return '$n seleccionado(s)';
  }

  Widget _barraSeleccion(BuildContext context) {
    return Row(
      children: [
        Presionable(
          onTap: () => setState(_seleccionados.clear),
          child: const Padding(
            padding: EdgeInsets.all(Espaciado.xs),
            child: Icon(IconosPlazoleta.close),
          ),
        ),
        const SizedBox(width: Espaciado.sm),
        Text(
          '${_seleccionados.length} seleccionado(s)',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }

  /// Mock `MovilProveedores` ("Lenguaje de diseño", 2026-09-26): con nada
  /// escrito, la pestaña arranca por los proveedores — tocar uno es el
  /// mismo filtro "Por proveedor" de siempre.
  Widget _listaProveedores(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.lg + NavbarCompanion.espacioReservado),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Espaciado.sm),
          child: Text('Proveedores', style: textTheme.bodySmall),
        ),
        for (final prov in _proveedores)
          Padding(
            padding: const EdgeInsets.only(bottom: Espaciado.sm),
            child: Superficie(
              padding: EdgeInsets.zero,
              child: Presionable(
                onTap: () {
                  setState(() {
                    _filtro = _FiltroCatalogo.ninguno;
                    _proveedorFiltroId = prov.id;
                    _proveedorFiltroNombre = prov.nombre;
                  });
                  _buscar();
                },
                child: Padding(
                  padding: const EdgeInsets.all(Espaciado.md),
                  child: Row(
                    children: [
                      AvatarIniciales(texto: inicialesDe(prov.nombre)),
                      const SizedBox(width: Espaciado.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(prov.nombre, style: textTheme.titleMedium),
                            Text('Código ${prov.codigo}', style: textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Icon(IconosPlazoleta.chevronRight, color: context.colores.textoTenue),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _abrirFormulario({ProductoCompanion? producto}) async {
    final cambio = await mostrarFormularioProducto(
      context,
      cliente: _cliente!,
      usuarioId: _usuarioId!,
      proveedores: _proveedores,
      categorias: _categorias,
      producto: producto,
    );
    if (cambio) _buscar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Padding inferior extra (Regla de esta pestaña ahora que es raíz del
      // `PageView`, `extendBody: true`): sin esto el FAB queda tapado por —
      // o superpuesto con — la navbar flotante, que ocupa esa misma franja.
      floatingActionButton: _cliente == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: NavbarCompanion.espacioReservado),
              child: _enSeleccion
                  ? FloatingActionButton.extended(
                      onPressed: () => _abrirEdicionMasiva(context),
                      icon: const Icon(IconosPlazoleta.editOutlined),
                      label: Text(_etiquetaEdicionMasiva),
                    )
                  : FloatingActionButton.extended(
                      onPressed: () => _abrirFormulario(),
                      icon: const Icon(IconosPlazoleta.add),
                      label: const Text('Nuevo'),
                    ),
            ),
      body: SafeArea(
        child: _cargandoInicial
            ? const EsqueletoLista()
            : _cliente == null
            ? EstadoErrorCompanion(mensaje: _error ?? 'No se pudo conectar.', onReintentar: _iniciar)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.lg, Espaciado.lg, 0),
                    child: _enSeleccion ? _barraSeleccion(context) : Text('Productos', style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  AvisoModoLocal(servicio: _cliente, pcEmparejada: _pcEmparejada),
                  Padding(
                    padding: const EdgeInsets.all(Espaciado.lg),
                    child: Superficie(
                      child: CampoTexto(
                        controller: _busquedaCtrl,
                        etiqueta: 'Buscar producto por nombre',
                        prefixIcon: const Icon(IconosPlazoleta.search),
                        suffixIcon: _buscando
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onChanged: (_) => _debouncer.ejecutar(_buscar),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: _filaFiltros(context),
                  ),
                  if (_proveedorFiltroId != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.sm),
                      child: Row(
                        children: [
                          AvatarIniciales(texto: inicialesDe(_proveedorFiltroNombre ?? ''), elegido: true),
                          const SizedBox(width: Espaciado.md),
                          Expanded(
                            child: Text(
                              _proveedorFiltroNombre ?? '',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _elegirFiltro(_FiltroCatalogo.ninguno),
                            child: const Text('Todos'),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                      child: Text(
                        _error!,
                        style: TextStyle(color: context.colores.error),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _buscar,
                      child: _resultados.isEmpty &&
                              !_buscando &&
                              _busquedaCtrl.text.trim().isEmpty &&
                              _filtro == _FiltroCatalogo.ninguno &&
                              _proveedorFiltroId == null
                          ? _listaProveedores(context)
                          : _resultados.isEmpty && !_buscando
                          ? ListView(
                              padding: const EdgeInsets.only(
                                bottom: NavbarCompanion.espacioReservado,
                              ),
                              children: [
                                SizedBox(
                                  height: 300,
                                  child: EstadoVacioCompanion(
                                    mensaje: _mensajeVacio(),
                                    icono: _busquedaCtrl.text.trim().isEmpty &&
                                            _filtro == _FiltroCatalogo.ninguno &&
                                            _proveedorFiltroId == null
                                        ? IconosPlazoleta.search
                                        : IconosPlazoleta.searchOff,
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                Espaciado.lg,
                                Espaciado.lg,
                                Espaciado.lg,
                                Espaciado.lg + NavbarCompanion.espacioReservado,
                              ),
                              itemCount: _resultados.length,
                              itemBuilder: (context, i) {
                                final p = _resultados[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: Espaciado.sm),
                                  child: _TarjetaProducto(
                                    producto: p,
                                    enSeleccion: _enSeleccion,
                                    seleccionado: _seleccionados.contains(p.id),
                                    onTap: () => _enSeleccion ? _alternarSeleccion(p.id) : _abrirFormulario(producto: p),
                                    onLongPress: () => _alternarSeleccion(p.id),
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

/// Filtros de higiene de catálogo (Bruno, 2026-09-19: "filtrar por
/// productos sin proveedor, sin costo, etcétera") — uno solo activo por
/// vez, `ninguno` es "Todos". Ver `listarProductos` en
/// `data/repositorio_productos.dart` para qué mira cada uno.
enum _FiltroCatalogo { ninguno, sinProveedor, sinCosto, sinCategoria, sinCodigoBarras }

/// Lista simple de proveedores para elegir "Por proveedor" — cierra
/// devolviendo el elegido, o `null` si se cancela (no hay forma de
/// "confirmar sin elegir nada": tocar afuera o el gesto de descartar son la
/// única salida sin resultado).
class _HojaElegirProveedor extends StatelessWidget {
  const _HojaElegirProveedor({required this.proveedores});

  final List<ProveedorCompanion> proveedores;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Elegir proveedor', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.md),
        if (proveedores.isEmpty)
          Text('No hay proveedores cargados.', style: TextStyle(color: context.colores.textoSecundario))
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: proveedores.length,
              itemBuilder: (context, i) {
                final p = proveedores[i];
                return Presionable(
                  onTap: () => Navigator.of(context).pop(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
                    child: Text('${p.codigo} — ${p.nombre}', style: Theme.of(context).textTheme.titleMedium),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Tarjeta de producto del mock `MovilProveedor`: nombre, precio con su
/// margen, costo y stock.
class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({
    required this.producto,
    required this.enSeleccion,
    required this.seleccionado,
    required this.onTap,
    required this.onLongPress,
  });

  final ProductoCompanion producto;
  final bool enSeleccion;
  final bool seleccionado;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final precio = p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos;
    final costo = p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos;
    final porKilo = p.esPesable ? '/kg' : '';
    // Costo $0 = sin costo (Regla 4): sin margen que mostrar.
    final margen = precio == null || costo == null || costo <= 0 ? null : markupBpDesdeCostoYPrecio(costo, precio);
    final stock = p.esPesable ? p.stockGramos ?? 0 : p.stock;
    return Superficie(
      padding: EdgeInsets.zero,
      child: Presionable(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.lg),
          child: Row(
            children: [
              if (enSeleccion) ...[
                Icon(
                  seleccionado ? IconosPlazoleta.checkCircle : IconosPlazoleta.radioButtonUnchecked,
                  color: seleccionado ? colores.acento : colores.textoTenue,
                ),
                const SizedBox(width: Espaciado.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, style: textTheme.titleMedium),
                    const SizedBox(height: Espaciado.xs),
                    Row(
                      children: [
                        Text(
                          precio == null ? 'Sin precio' : '${formatearARS(precio)}$porKilo',
                          style: textTheme.titleLarge?.tabular,
                        ),
                        if (margen != null) ...[
                          const SizedBox(width: Espaciado.sm),
                          Insignia(texto: '+${(margen / 100).round()}%', tono: Tono.ganancia),
                        ],
                      ],
                    ),
                    const SizedBox(height: Espaciado.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            costo == null || costo <= 0 ? 'Sin costo' : 'Costo ${formatearARS(costo)}',
                            style: textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          stock <= 0 ? 'Sin stock' : 'Stock $stock${p.esPesable ? ' g' : ''}',
                          style: textTheme.bodySmall?.copyWith(
                            color: stock <= 0 ? colores.error : colores.textoSecundario,
                            fontWeight: Pesos.fuerte,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
