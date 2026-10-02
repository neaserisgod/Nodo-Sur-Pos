// "Consultar precio" — para responder rápido "¿cuánto sale esto?" sin
// entrar al formulario de edición: escanear o escribir, ver el precio
// grande, listo. Es de solo lectura a propósito (no comparte pantalla con
// "Precios y alta de producto", que sí escribe) — así un vistazo rápido
// nunca corre el riesgo de tocar un precio sin querer.

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart' show ProductoCompanion;
import 'debounce.dart';
import 'emparejamiento.dart';
import 'escanear_codigo.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/colores_companion.dart';
import 'tema/estado_error_companion.dart';
import 'tema/estado_vacio_companion.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

class PantallaConsultarPrecio extends StatefulWidget {
  const PantallaConsultarPrecio({super.key});

  @override
  State<PantallaConsultarPrecio> createState() =>
      _PantallaConsultarPrecioState();
}

class _PantallaConsultarPrecioState extends State<PantallaConsultarPrecio> {
  ServicioCompanion? _cliente;
  bool _pcEmparejada = false;

  final _busquedaCtrl = TextEditingController();
  final _debouncer = Debouncer();
  List<ProductoCompanion> _resultados = [];
  ProductoCompanion? _seleccionado;
  bool _buscando = false;
  bool _escaneando = false;
  bool _cargandoInicial = true;
  String? _error;
  String? _errorInicial;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó" — repite la búsqueda actual sola apenas la sync trae algo
  /// nuevo.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    _iniciar();
    _subCambiosSync = avisosCambiosCompanion.listen((_) {
      if (_busquedaCtrl.text.isNotEmpty) _buscar(_busquedaCtrl.text);
    });
  }

  /// Sin PC emparejada (El dueño, 2026-09-18: "no debería tener que escanear
  /// ya, es innecesario") cae a la base local sincronizada por Supabase en
  /// vez de mostrar un error — buscar/consultar precio no necesita la PC
  /// para nada que ya haya sincronizado.
  Future<void> _iniciar() async {
    setState(() {
      _cargandoInicial = true;
      _errorInicial = null;
    });
    try {
      final conexion = await leerConexion();
      final servicio = conexion == null
          ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
          : await resolverServicioCompanion(conexion);
      if (mounted) {
        setState(() {
          _cliente = servicio;
          _pcEmparejada = conexion != null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorInicial = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
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
    if (_cliente == null) return;
    setState(() {
      _seleccionado = null;
      _buscando = true;
    });
    try {
      final resultados = await _cliente!.productos(busqueda: texto);
      // Descarta una respuesta que ya no corresponde al texto actual —
      // otra, más nueva, pudo llegar antes por el jitter normal de WiFi.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() => _resultados = resultados);
      }
    } catch (e) {
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() => _error = mensajeDeError(e));
      }
    } finally {
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() => _buscando = false);
      }
    }
  }

  Future<void> _escanear() async {
    if (_cliente == null || _escaneando) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() {
      _escaneando = true;
      _error = null;
    });
    try {
      final producto = await _cliente!.porCodigoBarras(codigo);
      if (!mounted) return;
      if (producto == null) {
        setState(() => _error = 'No hay ningún producto con ese código');
      } else {
        setState(() {
          _seleccionado = producto;
          _resultados = [];
          _busquedaCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultar precio'),
        actions: [
          if (_cliente != null)
            IconButton(
              tooltip: 'Escanear código de barras',
              icon: _escaneando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(IconosPlazoleta.qrCodeScanner),
              onPressed: _escaneando ? null : _escanear,
            ),
        ],
      ),
      body: SafeArea(
        child: _cargandoInicial
            ? const EsqueletoLista()
            : _cliente == null
            ? EstadoErrorCompanion(
                mensaje: _errorInicial ?? 'No se pudo conectar.',
                onReintentar: _iniciar,
              )
            : Column(
                children: [
                  AvisoModoLocal(servicio: _cliente, pcEmparejada: _pcEmparejada),
                  Padding(
                    padding: const EdgeInsets.all(Espaciado.lg),
                    child: Superficie(
                      child: CampoTexto(
                        controller: _busquedaCtrl,
                        etiqueta: 'Escribí el nombre, o escaneá',
                        prefixIcon: const Icon(IconosPlazoleta.search),
                        suffixIcon: _buscando
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onChanged: (texto) =>
                            _debouncer.ejecutar(() => _buscar(texto)),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                      child: ErrorEnLinea(_error!),
                    ),
                  if (_seleccionado != null)
                    Expanded(child: _TarjetaPrecio(producto: _seleccionado!))
                  else
                    Expanded(
                      child: _resultados.isEmpty && !_buscando
                          ? EstadoVacioCompanion(
                              mensaje: _busquedaCtrl.text.trim().isEmpty
                                  ? 'Escribí para buscar, o escaneá'
                                  : 'Sin resultados',
                              icono: _busquedaCtrl.text.trim().isEmpty
                                  ? IconosPlazoleta.search
                                  : IconosPlazoleta.searchOff,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(Espaciado.lg),
                              itemCount: _resultados.length,
                              itemBuilder: (context, i) {
                                final p = _resultados[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: Espaciado.sm),
                                  child: Superficie(
                                    padding: EdgeInsets.zero,
                                    child: Presionable(
                                      onTap: () => setState(() => _seleccionado = p),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: Espaciado.lg,
                                          vertical: Espaciado.md,
                                        ),
                                        child: Text(
                                          p.nombre,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
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
    );
  }
}

class _TarjetaPrecio extends StatelessWidget {
  const _TarjetaPrecio({required this.producto});

  final ProductoCompanion producto;

  @override
  Widget build(BuildContext context) {
    final precioTexto = producto.esPesable
        ? '${formatearARS(producto.precioPorKiloCentavos ?? 0)} / kg'
        : formatearARS(producto.precioCentavos ?? 0);
    final stockTexto = producto.esPesable
        ? '${producto.stockGramos ?? 0} g'
        : '${producto.stock} un.';

    final colores = context.colores;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espaciado.lg),
        child: BloqueHero(
          animar: false,
          padding: const EdgeInsets.all(Espaciado.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                producto.nombre,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: context.acentos.textoSobreColor),
              ),
              const SizedBox(height: Espaciado.lg),
              Text(
                precioTexto,
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontSize: 56, color: context.acentos.textoSobreColor),
              ),
              const SizedBox(height: Espaciado.md),
              Text(
                'Stock: $stockTexto',
                style: TextStyle(color: context.acentos.textoSobreColor.withValues(alpha: 0.8)),
              ),
              if (!producto.activo) ...[
                const SizedBox(height: Espaciado.sm),
                Text(
                  'Producto desactivado',
                  style: TextStyle(color: colores.errorTexto, backgroundColor: colores.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
