// El carrito de una venta desde el celular (El dueño, 2026-09-07: "que la
// parte de vender use la misma lógica que la app de desktop"). Efectivo,
// QR y Débito en esta primera versión, sin Mixto (decisión de el dueño,
// 2026-09-07) — descuento (Regla 17 generalizada) sí, agregado el
// 2026-09-10 ("el carrito del celular no tiene para descuento"), mismo
// mecanismo que el escritorio.
//
// El buscador vivía en una pestaña propia de la navbar hasta que el dueño
// (2026-09-13) pidió juntarlo acá: "buscar está estrictamente ligado al
// carrito... para que al entrar en el carrito directamente se pueda
// agregar y cobrar desde ahí mismo". Con texto en el campo, esta pantalla
// muestra resultados en vez de las líneas; se agrega tocando un resultado,
// igual que agregaba la pestaña vieja (misma lógica de dominio,
// `lineaDesdeResultadoBusqueda`/`sumarLineasVenta`, Regla 3).
//
// El descuento (El dueño, 2026-09-13: "usa muchísimo espacio... se usa cada
// tanto") pasó de un bloque siempre visible a un botón chico que abre un
// diálogo — mismo mecanismo (tipo monto/porcentaje + `CampoPlata`), solo
// que ahora ocupa espacio nada más cuando hace falta.

import 'package:flutter/material.dart';

import '../data/identidad_sync.dart' show generarGlobalId;
import '../domain/descuento.dart';
import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../domain/vuelto.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'boton_escaner_companion.dart';
import 'dialogo_cobro_posnet_companion.dart';
import 'escanear_codigo.dart';
import 'fila_linea_carrito.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'sesion_abierta_gate.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';
import 'tema/app_bar_companion.dart';
import 'tema/colores_companion.dart';

enum _MedioVenta { efectivo, qr, debito }

/// Los tres momentos de una venta en esta pantalla (mock completo del
/// celular): armar el carrito, elegir cómo paga y confirmar, y el resumen de
/// la venta cobrada.
enum _Paso { carrito, cobro, cobrado }

/// Lo que muestra la pantalla de "Venta cobrada" una vez asentada la venta.
typedef _ResumenCobro = ({int ventaId, int totalCentavos, _MedioVenta medio, int productos, int vueltoCentavos});

class PantallaCarritoVenta extends StatefulWidget {
  const PantallaCarritoVenta({
    super.key,
    required this.cliente,
    required this.servicio,
    required this.usuarioId,
    required this.carrito,
    this.encargueId,
  });

  /// Imprimir ticket — exclusivo de la PC (El dueño, 2026-09-18: la orden de
  /// Point ahora sale directo desde `widget.servicio`, sin pasar por acá;
  /// solo imprimir sigue necesitando de verdad la impresora/PDF de la PC).
  /// Null sin PC emparejada — "Imprimir ticket" avisa en vez de tirar.
  final ClienteCompanion? cliente;

  /// Buscar, calcular, sesión y cobrar en efectivo — con fallback
  /// automático a la base local si la PC no responde (fase 3).
  final ServicioCompanion servicio;

  final int usuarioId;

  /// Referencia mutable al carrito del menú principal — esta pantalla lo
  /// edita (eliminar líneas, vaciarlo tras cobrar) directamente, sin
  /// callbacks: el menú vuelve a leerlo al recibir el foco de nuevo
  /// (mismo criterio que cualquier otra pantalla de gestión que vuelve a
  /// cargar al hacer pop).
  final List<LineaVenta> carrito;

  /// El encargue por apartado que esta venta entrega: al cobrar, por cualquier medio, libera lo apartado.
  final int? encargueId;

  @override
  State<PantallaCarritoVenta> createState() => _PantallaCarritoVentaState();
}

class _PantallaCarritoVentaState extends State<PantallaCarritoVenta> {
  int? _sesionCajaId;
  _MedioVenta? _medio;
  ResultadoTotalVenta? _resultado;
  bool _calculando = false;
  bool _cobrando = false;
  String? _error;

  _Paso _paso = _Paso.carrito;
  _ResumenCobro? _cobrado;

  /// Con cuánto paga en efectivo: null hasta que elige un atajo (se toma el
  /// primero) y `_pagaJusto` para "Justo". Solo orienta el vuelto, no se registra.
  int? _pagaCentavos;
  bool _pagaJusto = false;
  bool _escaneando = false;

  // Descuento sobre el total (Regla 17 generalizada) — El dueño, 2026-09-10:
  // "el carrito del celular no tiene para descuento". Mismo mecanismo que
  // el escritorio (`VentaControlador`): `parsearARS` sirve igual de bien
  // para plata que para porcentaje, las dos escalas son "dos decimales"
  // (`$15,00` = 1500 centavos, `15,00%` = 1500 basis points, 10000 = 100%).
  TipoDescuento _tipoDescuento = TipoDescuento.monto;
  final _descuentoCtrl = TextEditingController();
  final _debouncerDescuento = Debouncer();

  // Buscador para agregar productos sin salir de esta pantalla (El dueño,
  // 2026-09-13). Con `_busquedaCtrl` no vacío, el cuerpo muestra
  // `_resultadosBusqueda` en vez de las líneas del carrito.
  final _busquedaCtrl = TextEditingController();
  final _busquedaFocus = FocusNode();
  final _debouncerBusqueda = Debouncer();
  List<ProductoCompanion> _resultadosBusqueda = [];

  /// No nulo si el texto pedía gramos de un pesable ("200 queso") — ya
  /// parseado por el servidor, mismo criterio que el resto de la companion.
  int? _gramosBusqueda;
  bool _buscando = false;

  // Identifica este intento de cobro ante el servidor (ver `/ventas/cobrar`): se renueva cuando cambia lo que se cobra y al
  // cobrar, así un reintento por mala señal no duplica la venta pero una venta igual a la anterior sí se graba.
  String? _claveCobroActual;
  String get _claveCobro => _claveCobroActual ??= generarGlobalId();

  int get _valorDescuentoIngresado {
    final texto = _descuentoCtrl.text.trim();
    if (texto.isEmpty) return 0;
    try {
      return parsearARS(texto);
    } on FormatException {
      return 0;
    }
  }

  @override
  void dispose() {
    _descuentoCtrl.dispose();
    _debouncerDescuento.dispose();
    _busquedaCtrl.dispose();
    _busquedaFocus.dispose();
    _debouncerBusqueda.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() {
        _resultadosBusqueda = [];
        _gramosBusqueda = null;
      });
      return;
    }
    setState(() => _buscando = true);
    try {
      final resultado = await widget.servicio.buscarVenta(texto);
      // Mismo cuidado que en el resto de la companion: una respuesta vieja
      // que llega tarde no debe pisar el resultado del texto actual.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() {
          _resultadosBusqueda = resultado.resultados;
          _gramosBusqueda = resultado.gramos;
        });
      }
    } finally {
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() => _buscando = false);
      }
    }
  }

  /// Agrega [producto] al carrito con la misma lógica que
  /// `VentaControlador.agregarProducto` (Regla 3,
  /// `lineaDesdeResultadoBusqueda`): un pesable sin gramos o sin precio por
  /// kilo no se agrega, avisa por qué. Un producto repetido suma cantidad
  /// en la misma línea (`sumarLineasVenta`), no crea una segunda.
  ///
  /// El dueño, 2026-09-14: "es complicado el hecho de agregar productos de
  /// manera continua... no hay espacio" — tocar un resultado (un `InkWell`
  /// fuera del campo) le sacaba el foco al buscador y cerraba el teclado
  /// solo, así que agregar el producto siguiente pedía volver a tocar el
  /// campo a mano cada vez. `requestFocus()` acá abajo lo devuelve
  /// apenas se agrega — mismo espíritu que "el campo único siempre con
  /// foco" de la pantalla de venta de escritorio, adaptado a que acá el
  /// campo comparte pantalla con el teclado en vez de tener una columna
  /// aparte.
  void _alTocarResultadoBusqueda(ProductoCompanion producto) {
    final resultado = lineaDesdeResultadoBusqueda(producto, gramos: _gramosBusqueda);
    if (resultado.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(resultado.error!)));
      return;
    }
    final nueva = resultado.linea!;
    _claveCobroActual = null;
    setState(() {
      final indiceExistente = widget.carrito.indexWhere(
        (l) => l.productoId == nueva.productoId,
      );
      if (indiceExistente != -1) {
        widget.carrito[indiceExistente] = sumarLineasVenta(
          widget.carrito[indiceExistente],
          nueva,
        );
      } else {
        widget.carrito.add(nueva);
      }
      // El total ya calculado (si lo había) dejó de valer con el carrito
      // cambiado — mismo motivo que `_actualizarLinea`.
      _medio = null;
      _resultado = null;
      _busquedaCtrl.clear();
      _resultadosBusqueda = [];
      _gramosBusqueda = null;
    });
    _busquedaFocus.requestFocus();
  }

  void _elegirTipoDescuento(TipoDescuento tipo) {
    setState(() => _tipoDescuento = tipo);
    _recalcularSiHayMedio();
  }

  /// El descuento no se calcula solo con lo que hay en el carrito — el
  /// total real depende también del medio elegido (recargo de
  /// cigarrillos, redondeo), así que cambiar el descuento sin medio
  /// elegido todavía no tiene nada contra qué recalcular. Con un medio ya
  /// elegido, vuelve a pedir el total con el valor nuevo (debounced: el
  /// campo dispara esto en cada tecla).
  void _recalcularSiHayMedio() {
    final medio = _medio;
    if (medio == null) return;
    _debouncerDescuento.ejecutar(() => _elegirMedio(medio));
  }

  Future<void> _elegirMedio(_MedioVenta medio) async {
    _claveCobroActual = null;
    setState(() {
      _medio = medio;
      _calculando = true;
      _error = null;
    });
    try {
      final valorDescuento = _valorDescuentoIngresado;
      final resultado = await widget.servicio.calcularVenta(
        lineas: widget.carrito,
        medio: medio == _MedioVenta.efectivo ? 'efectivo' : 'virtual',
        tipoDescuento: valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: valorDescuento,
      );
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  void _eliminarLinea(int index) {
    final quitada = widget.carrito[index];
    _actualizarLinea(index, null);
    // Sin confirmación previa: un toque saca la línea, así que se puede deshacer.
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.clearSnackBars();
    mensajero.showSnackBar(
      SnackBar(
        content: Text('Quitaste ${quitada.nombreProducto}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            if (!mounted) return;
            _claveCobroActual = null;
            setState(() {
              widget.carrito.insert(index.clamp(0, widget.carrito.length), quitada);
              _medio = null;
              _resultado = null;
            });
          },
        ),
      ),
    );
  }

  /// `nueva` null = eliminar la línea (mismo criterio que el escritorio:
  /// restar por debajo de 1 saca la línea entera, el dueño, 2026-09-07: "no
  /// puedo agregar más de 1 unidad a la vez... misma funcionalidad que
  /// carrito").
  void _actualizarLinea(int index, LineaVenta? nueva) {
    _claveCobroActual = null;
    setState(() {
      if (nueva == null) {
        widget.carrito.removeAt(index);
      } else {
        widget.carrito[index] = nueva;
      }
      // El total ya calculado dejó de valer con el carrito cambiado — hay
      // que elegir el medio de nuevo para recalcularlo.
      _medio = null;
      _resultado = null;
    });
  }

  Future<void> _confirmar() async {
    final medio = _medio;
    if (medio == null) return;
    if (medio == _MedioVenta.efectivo) {
      await _cobrarEfectivo();
    } else {
      await _cobrarPosnet(medio == _MedioVenta.qr ? 'qr' : 'debit_card');
    }
  }

  Future<void> _cobrarEfectivo() async {
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final valorDescuento = _valorDescuentoIngresado;
      final r = await widget.servicio.cobrarEfectivo(
        lineas: widget.carrito,
        sesionCajaId: _sesionCajaId!,
        usuarioId: widget.usuarioId,
        tipoDescuento: valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: widget.encargueId,
        claveCobro: _claveCobro,
      );
      await _ventaCobrada(r.ventaId, r.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _cobrarPosnet(String canal) async {
    // Bug real: sin este try/finally, si algo tira una excepción antes de
    // que el diálogo llegue a abrirse (`_resultado` todavía null porque el
    // cálculo previo falló, por ejemplo), `_cobrando` quedaba en `true`
    // para siempre — el botón "Cobrar" se veía trabado con el spinner
    // girando, sin ningún error visible, y la única salida era cerrar la
    // pantalla. Mismo patrón que ya tenían `_cobrarEfectivo`/`_cobrarAMano`.
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final total = _resultado?.totalCentavos;
      if (total == null) {
        setState(
          () => _error = 'Elegí el medio de pago de nuevo antes de cobrar.',
        );
        return;
      }
      final valorDescuento = _valorDescuentoIngresado;
      final resultado = await mostrarDialogoCobroPosnetCompanion(
        context,
        cliente: widget.servicio,
        usuarioId: widget.usuarioId,
        sesionCajaId: _sesionCajaId!,
        lineas: widget.carrito,
        canal: canal,
        montoCentavos: total,
        tipoDescuento: valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: widget.encargueId,
      );
      if (resultado != null) {
        await _ventaCobrada(resultado.ventaId, resultado.totalCentavos);
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  /// Salta la terminal Point directamente, sin intentar la orden primero
  /// (El dueño, 2026-09-07: "el cobro manual del qr/posnet, es para cargar
  /// las ventas de hoy y seguir cargando mientras tanto") — a diferencia
  /// de "Cobrar a mano" adentro del diálogo de Point (que aparece recién
  /// si la orden falla), esta es para cuando ya se sabe que no hace falta
  /// tocar la terminal: ventas ya cobradas por otro medio (link de pago,
  /// MP de otro celular) que solo faltan asentar. Mismo endpoint que ese
  /// fallback (`cobrarVirtualAMano`, Regla 3), un solo camino de verdad.
  Future<void> _cobrarAMano() async {
    final medio = _medio;
    if (medio == null || medio == _MedioVenta.efectivo) return;
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final valorDescuento = _valorDescuentoIngresado;
      final r = await widget.servicio.cobrarVirtualAMano(
        lineas: widget.carrito,
        sesionCajaId: _sesionCajaId!,
        usuarioId: widget.usuarioId,
        canal: medio == _MedioVenta.qr ? 'qr' : 'debit_card',
        tipoDescuento: valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: valorDescuento,
        encargueId: widget.encargueId,
        claveCobro: _claveCobro,
      );
      await _ventaCobrada(r.ventaId, r.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _ventaCobrada(int ventaId, int totalCentavos) async {
    _claveCobroActual = null;
    // Se arma el resumen ANTES de vaciar el carrito: cuántos productos fueron
    // y cuánto se devuelve dependen de lo que había.
    final medio = _medio ?? _MedioVenta.efectivo;
    final productos = widget.carrito.length;
    final vuelto = medio == _MedioVenta.efectivo
        ? vueltoCentavos(pagaCentavos: _pagaEfectivoCentavos(totalCentavos), totalCentavos: totalCentavos)
        : 0;
    widget.carrito.clear();
    _tipoDescuento = TipoDescuento.monto;
    _descuentoCtrl.clear();
    if (!mounted) return;
    setState(() {
      _cobrado = (ventaId: ventaId, totalCentavos: totalCentavos, medio: medio, productos: productos, vueltoCentavos: vuelto < 0 ? 0 : vuelto);
      _paso = _Paso.cobrado;
    });
  }

  Future<void> _imprimirTicket(int ventaId) async {
    final cliente = widget.cliente;
    if (cliente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para imprimir hace falta estar emparejado con la PC.')),
      );
      return;
    }
    try {
      await cliente.imprimirTicket(ventaId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo imprimir: ${mensajeDeError(e)}')));
      }
    }
  }

  /// Con cuánto paga en efectivo para el total [total]: lo elegido, y si no
  /// eligió nada, el primer atajo (el billete que alcanza); sin atajos, justo.
  int _pagaEfectivoCentavos(int total) {
    if (_pagaJusto) return total;
    return _pagaCentavos ?? (atajosDeEfectivo(total).firstOrNull ?? total);
  }

  /// Pasa a "cómo paga": calcula el total con efectivo, que es lo que se
  /// elige por defecto, y deja el vuelto sin elegir.
  Future<void> _irACobro() async {
    setState(() {
      _paso = _Paso.cobro;
      _pagaCentavos = null;
      _pagaJusto = false;
    });
    await _elegirMedio(_MedioVenta.efectivo);
  }

  void _volverAlCarrito() => setState(() {
    _paso = _Paso.carrito;
    _error = null;
  });

  /// Escanea un código y suma el producto al carrito: el mismo camino que
  /// tocar un resultado de la búsqueda (`_alTocarResultadoBusqueda`).
  Future<void> _escanearYAgregar() async {
    if (_escaneando) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() => _escaneando = true);
    try {
      final producto = await widget.servicio.porCodigoBarras(codigo);
      if (!mounted) return;
      if (producto == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay un producto con ese código.')));
      } else {
        _alTocarResultadoBusqueda(producto);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  /// REGLAS-NEGOCIO §3: cuando el vuelto da $100 exactos se agrega el
  /// producto de vuelto (el caramelo) en vez de dar el cambio. Es una venta
  /// normal: entra como línea del carrito y el total se recalcula.
  Future<void> _agregarCaramelo() async {
    try {
      final config = await widget.servicio.configuracionNegocio();
      final id = config.productoVueltoId;
      if (id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay un producto de vuelto configurado (Gestión → Configuración).')),
          );
        }
        return;
      }
      final todos = await widget.servicio.productos();
      final producto = todos.where((x) => x.id == id).firstOrNull;
      if (!mounted) return;
      if (producto == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró el producto de vuelto.')));
        return;
      }
      _alTocarResultadoBusqueda(producto);
      setState(() {
        _pagaCentavos = null;
        _pagaJusto = false;
      });
      await _elegirMedio(_MedioVenta.efectivo);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _busquedaCtrl.text.trim().isNotEmpty;
    return PopScope(
      // En "cómo paga" volver es volver al carrito, no salir de la venta.
      canPop: _paso != _Paso.cobro,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volverAlCarrito();
      },
      child: Scaffold(
        appBar: const AppBarCompanion(titulo: 'Carrito', etiquetaSalida: 'Cerrar'),
        body: SafeArea(
          child: _sesionCajaId == null
              ? SesionAbiertaGate(
                  cliente: widget.servicio,
                  usuarioId: widget.usuarioId,
                  onLista: (id) => setState(() => _sesionCajaId = id),
                )
              : switch (_paso) {
                  _Paso.carrito => Column(
                    children: [
                      _campoBuscador(context),
                      // Mientras se busca, el carrito queda oculto detrás de
                      // los resultados (no entran los dos juntos en la
                      // pantalla) — esta franja chica es la única señal de que
                      // lo que ya se agregó sigue ahí, sin tener que borrar la
                      // búsqueda para confirmarlo (El dueño, 2026-09-14: "no hay
                      // espacio").
                      if (buscando && widget.carrito.isNotEmpty) _resumenCarritoCompacto(context),
                      Expanded(child: buscando ? _listaResultadosBusqueda(context) : _listaLineas(context)),
                      if (!buscando) _panelTotal(context),
                    ],
                  ),
                  _Paso.cobro => _vistaCobro(context),
                  _Paso.cobrado => _vistaCobrado(context),
                },
        ),
      ),
    );
  }

  Widget _campoBuscador(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _busquedaCtrl,
              focusNode: _busquedaFocus,
              // El dueño, 2026-09-19: "abre siempre el teclado automáticamente, cosa
              // que solo debería pasar cuando se entra la primera vez" — "primera
              // vez" es empezar una venta nueva (carrito vacío), no cada
              // reingreso a esta pantalla con líneas ya cargadas.
              autofocus: widget.carrito.isEmpty,
              decoration: InputDecoration(
                hintText: 'Agregar producto…',
                prefixIcon: const Icon(IconosPlazoleta.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _busquedaCtrl.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Borrar la búsqueda',
                        icon: const Icon(IconosPlazoleta.clear),
                        onPressed: () {
                          _debouncerBusqueda.cancelar();
                          _busquedaCtrl.clear();
                          setState(() {
                            _resultadosBusqueda = [];
                            _gramosBusqueda = null;
                          });
                          _busquedaFocus.requestFocus();
                        },
                      )
                    : null,
              ),
              onChanged: (texto) {
                setState(() {}); // para que aparezca/desaparezca el ícono de limpiar
                if (texto.trim().isEmpty) {
                  _debouncerBusqueda.cancelar();
                  _buscar(texto);
                } else {
                  _debouncerBusqueda.ejecutar(() => _buscar(texto));
                }
              },
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          BotonEscanerCampo(onTap: _escanearYAgregar, cargando: _escaneando),
        ],
      ),
    );
  }

  /// Franja compacta (no el panel de total completo, que no entra junto a
  /// los resultados) — cuántas líneas hay y el subtotal, y un toque la
  /// cierra para volver a ver el carrito entero. Ver el comentario de
  /// [_alTocarResultadoBusqueda] para el porqué completo.
  Widget _resumenCarritoCompacto(BuildContext context) {
    final cantidad = widget.carrito.length;
    final subtotal = Venta(lineas: widget.carrito).subtotalCentavos;
    return InkWell(
      onTap: () {
        _debouncerBusqueda.cancelar();
        _busquedaCtrl.clear();
        setState(() {
          _resultadosBusqueda = [];
          _gramosBusqueda = null;
        });
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.sm),
        child: Row(
          children: [
            Icon(IconosPlazoleta.shoppingCartOutlined, size: 16, color: context.colores.textoSecundario),
            const SizedBox(width: Espaciado.xs),
            Text(
              cantidad == 1 ? '1 producto · ${formatearARS(subtotal)}' : '$cantidad productos · ${formatearARS(subtotal)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
            ),
            const Spacer(),
            Text(
              'Ver carrito',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.colores.acento),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaResultadosBusqueda(BuildContext context) {
    if (_resultadosBusqueda.isEmpty && !_buscando) {
      return const EstadoVacio(mensaje: 'Sin resultados', icono: IconosPlazoleta.searchOff);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Espaciado.lg),
      itemCount: _resultadosBusqueda.length,
      itemBuilder: (context, i) {
        final p = _resultadosBusqueda[i];
        final precioTexto = p.esPesable
            ? '${formatearARS(p.precioPorKiloCentavos ?? 0)}/kg'
            : formatearARS(p.precioCentavos ?? 0);
        return Padding(
          padding: const EdgeInsets.only(bottom: Espaciado.sm),
          child: Superficie(
            padding: EdgeInsets.zero,
            child: Presionable(
              onTap: () => _alTocarResultadoBusqueda(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Espaciado.lg,
                  vertical: Espaciado.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.nombre,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(precioTexto, style: TextStyle(color: context.colores.textoSecundario)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _listaLineas(BuildContext context) {
    if (widget.carrito.isEmpty) {
      return const EstadoVacio(
        mensaje: 'El carrito está vacío',
        icono: IconosPlazoleta.shoppingCartOutlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.sm,
        Espaciado.lg,
        Espaciado.sm,
      ),
      itemCount: widget.carrito.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: Espaciado.xs),
        child: FilaLineaCarrito(
          linea: widget.carrito[i],
          onCambiar: (nueva) => _actualizarLinea(i, nueva),
          onEliminar: () => _eliminarLinea(i),
        ),
      ),
    );
  }

  /// Abajo del carrito: el atajo de descuento y la cantidad de productos, y
  /// la barra negra con el total y "Cobrar", que lleva a elegir cómo paga.
  Widget _panelTotal(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final subtotal = Venta(lineas: widget.carrito).subtotalCentavos;
    final vacio = widget.carrito.isEmpty || _calculando || _cobrando;
    final n = widget.carrito.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ActionChip(
                shape: _formaChip,
                side: BorderSide.none,
                backgroundColor: _fondoChip(context),
                onPressed: widget.carrito.isEmpty ? null : _abrirHojaDescuento,
                avatar: Icon(_valorDescuentoIngresado > 0 ? IconosPlazoleta.sellActivo : IconosPlazoleta.add, size: 18),
                label: Text(_valorDescuentoIngresado > 0 ? 'Descuento aplicado' : 'Descuento'),
              ),
              const Spacer(),
              Text(n == 1 ? '1 producto' : '$n productos', style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          BloqueHero(
            animar: false,
            padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.md, Espaciado.md, Espaciado.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total', style: textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.75), fontWeight: Pesos.fuerte)),
                      Text(formatearARS(subtotal), style: textTheme.headlineMedium?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                FilledButton(
                  // El tema estira los botones a todo el ancho: dentro de una fila hay que darle uno propio.
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF121317), minimumSize: const Size(128, 56)),
                  onPressed: vacio ? null : _irACobro,
                  child: const Text('Cobrar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _nombreMedio(_MedioVenta m) => switch (m) {
    _MedioVenta.efectivo => 'Efectivo',
    _MedioVenta.qr => 'QR de Mercado Pago',
    _MedioVenta.debito => 'Tarjeta de débito',
  };

  /// "¿Cómo paga?": el total ya calculado con el medio elegido, la lista de
  /// medios (sin Mixto en el celular, decisión del dueño del 2026-09-07) y,
  /// con efectivo, los atajos de con cuánto paga y el vuelto en vivo.
  Widget _vistaCobro(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final resultado = _resultado;
    final total = resultado?.totalCentavos;
    final medio = _medio ?? _MedioVenta.efectivo;
    final hayDesglose = resultado != null &&
        (resultado.recargoCigarrillosCentavos > 0 || resultado.descuentoCentavos > 0 || resultado.redondeoCentavos > 0);
    final puedeConfirmar = total != null && !_calculando && !_cobrando;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              shape: _formaChip,
              side: BorderSide.none,
              backgroundColor: _fondoChip(context),
              onPressed: _cobrando ? null : _volverAlCarrito,
              avatar: const Icon(IconosPlazoleta.arrowBackRounded, size: 18),
              label: const Text('Volver'),
            ),
          ),
          const SizedBox(height: Espaciado.md),
          Text('Total a cobrar', style: textTheme.labelLarge?.copyWith(color: colores.textoSecundario, fontWeight: Pesos.fuerte)),
          Text(total == null ? '…' : formatearARS(total), style: textTheme.displayMedium),
          if (hayDesglose)
            Text(
              [
                if (resultado.recargoCigarrillosCentavos > 0) 'Recargo ${formatearARS(resultado.recargoCigarrillosCentavos)}',
                if (resultado.descuentoCentavos > 0) 'Desc. -${formatearARS(resultado.descuentoCentavos)}',
                if (resultado.redondeoCentavos > 0) 'Redondeo ${formatearARS(resultado.redondeoCentavos)}',
              ].join(' · '),
              style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
            ),
          const SizedBox(height: Espaciado.lg),
          Text('¿Cómo paga?', style: textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          for (final m in _MedioVenta.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: _OpcionMedio(
                texto: _nombreMedio(m),
                elegido: medio == m,
                onTap: _cobrando ? null : () => _elegirMedio(m),
              ),
            ),
          if (medio == _MedioVenta.efectivo && total != null) _bloqueEfectivo(context, total),
          if (medio != _MedioVenta.efectivo)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _cobrando ? null : _cobrarAMano,
                child: const Text('Cobrar a mano (sin terminal)'),
              ),
            ),
          const Spacer(),
          if (_error != null) ...[ErrorEnLinea(_error!), const SizedBox(height: Espaciado.sm)],
          FilledButton(
            onPressed: puedeConfirmar ? _confirmar : null,
            child: _cobrando
                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colores.acentoTexto))
                : const Text('Confirmar cobro'),
          ),
        ],
      ),
    );
  }

  /// Atajos de con cuánto paga y el vuelto: orientación para quien cobra, no
  /// se registra (la caja cuenta lo cobrado). Con exactamente $100 de vuelto
  /// ofrece el caramelo (REGLAS-NEGOCIO §3).
  Widget _bloqueEfectivo(BuildContext context, int total) {
    final colores = context.colores;
    final paga = _pagaEfectivoCentavos(total);
    final vuelto = vueltoCentavos(pagaCentavos: paga, totalCentavos: total);
    final atajos = atajosDeEfectivo(total);
    return Superficie(
      padding: const EdgeInsets.all(Espaciado.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Espaciado.sm,
            runSpacing: Espaciado.sm,
            children: [
              ChoiceChip(
                shape: _formaChip,
                side: BorderSide.none,
                showCheckmark: false,
                backgroundColor: colores.fondo,
                selectedColor: colores.acento,
                labelStyle: TextStyle(fontWeight: Pesos.fuerte, color: _pagaJusto ? colores.acentoTexto : colores.textoPrimario),
                label: const Text('Justo'),
                selected: _pagaJusto,
                onSelected: (_) => setState(() => _pagaJusto = true),
              ),
              for (final monto in atajos)
                ChoiceChip(
                  shape: _formaChip,
                  side: BorderSide.none,
                  showCheckmark: false,
                  backgroundColor: colores.fondo,
                  selectedColor: colores.acento,
                  labelStyle: TextStyle(
                    fontWeight: Pesos.fuerte,
                    color: !_pagaJusto && paga == monto ? colores.acentoTexto : colores.textoPrimario,
                  ),
                  label: Text(formatearARS(monto)),
                  selected: !_pagaJusto && paga == monto,
                  onSelected: (_) => setState(() {
                    _pagaJusto = false;
                    _pagaCentavos = monto;
                  }),
                ),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            vuelto < 0 ? 'Falta ${formatearARS(-vuelto)}' : 'Vuelto ${formatearARS(vuelto)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: vuelto < 0 ? colores.error : context.acentos.ganancia),
          ),
          if (vueltoEsCaramelo(vuelto))
            TextButton(onPressed: _agregarCaramelo, child: const Text('Agregar caramelo en vez del vuelto')),
        ],
      ),
    );
  }

  /// La venta ya asentada: total, cómo se cobró y, en efectivo, el vuelto.
  Widget _vistaCobrado(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final c = _cobrado!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.xl, Espaciado.lg, Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(color: colores.acento, shape: BoxShape.circle),
            child: Icon(IconosPlazoleta.check, color: colores.acentoTexto, size: 36),
          ),
          const SizedBox(height: Espaciado.lg),
          Text('Venta cobrada', style: textTheme.displaySmall),
          Text(formatearARS(c.totalCentavos), style: textTheme.displayMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            '${_nombreMedio(c.medio) == 'Efectivo' ? 'Efectivo' : _nombreMedio(c.medio)} · ${c.productos == 1 ? '1 producto' : '${c.productos} productos'}',
            style: textTheme.bodyLarge?.copyWith(color: colores.textoSecundario),
          ),
          if (c.medio == _MedioVenta.efectivo && c.vueltoCentavos > 0)
            Text('Vuelto ${formatearARS(c.vueltoCentavos)}', style: textTheme.titleLarge?.copyWith(color: context.acentos.ganancia)),
          const Spacer(),
          OutlinedButton(onPressed: () => _imprimirTicket(c.ventaId), child: const Text('Imprimir ticket')),
          const SizedBox(height: Espaciado.sm),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Listo')),
        ],
      ),
    );
  }

  /// [refrescarDialogo] es el `setState` del `StatefulBuilder` del diálogo
  /// de descuento (`_abrirDialogoDescuento`) — sin él, elegir "$"/"%" ahí
  /// adentro actualiza `_tipoDescuento` (el `setState` de esta pantalla,
  /// que vive en OTRA ruta) pero el diálogo ya dibujado no se entera solo.
  Widget _botonTipoDescuento(
    TipoDescuento tipo,
    String texto,
    bool deshabilitado, {
    StateSetter? refrescarDialogo,
  }) {
    final seleccionado = _tipoDescuento == tipo;
    void onPressed() {
      _elegirTipoDescuento(tipo);
      refrescarDialogo?.call(() {});
    }

    return seleccionado
        ? FilledButton(onPressed: deshabilitado ? null : onPressed, child: Text(texto))
        : OutlinedButton(onPressed: deshabilitado ? null : onPressed, child: Text(texto));
  }

  /// El `setState` final es lo que hace que el botón (que vive en la
  /// pantalla, no en la hoja) muestre el valor recién cargado apenas se
  /// cierra — cubre cerrar con "Listo", con "Quitar", o deslizando afuera.
  Future<void> _abrirHojaDescuento() async {
    await mostrarHojaVidrio<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, refrescarHoja) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Descuento', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Espaciado.lg),
            Row(
              children: [
                Expanded(
                  child: _botonTipoDescuento(
                    TipoDescuento.monto,
                    r'$',
                    false,
                    refrescarDialogo: refrescarHoja,
                  ),
                ),
                const SizedBox(width: Espaciado.sm),
                Expanded(
                  child: _botonTipoDescuento(
                    TipoDescuento.porcentaje,
                    '%',
                    false,
                    refrescarDialogo: refrescarHoja,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espaciado.sm),
            CampoPlata(
              controller: _descuentoCtrl,
              etiqueta: _tipoDescuento == TipoDescuento.monto
                  ? 'Monto del descuento'
                  : 'Porcentaje de descuento',
              onChanged: (_) => _recalcularSiHayMedio(),
            ),
            const SizedBox(height: Espaciado.lg),
            Row(
              children: [
                if (_valorDescuentoIngresado > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _descuentoCtrl.clear();
                        _recalcularSiHayMedio();
                        refrescarHoja(() {});
                        Navigator.of(context).pop();
                      },
                      child: const Text('Quitar'),
                    ),
                  ),
                  const SizedBox(width: Espaciado.sm),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Listo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}


/// Estilo común de los chips de esta pantalla (mock completo): píldora gris
/// sin borde y, la elegida, en tinta con letra clara.
OutlinedBorder get _formaChip => const StadiumBorder();

Color _fondoChip(BuildContext context) => context.colores.fondoBloque;

/// Una fila de la lista "¿Cómo paga?": píldora gris con un círculo de
/// selección; la elegida lleva borde de tinta.
class _OpcionMedio extends StatelessWidget {
  const _OpcionMedio({required this.texto, required this.elegido, required this.onTap});

  final String texto;
  final bool elegido;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Presionable(
      radio: 999,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        decoration: BoxDecoration(
          color: colores.fondoBloque,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: elegido ? colores.acento : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleMedium)),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: elegido ? colores.acento : colores.textoTenue, width: 2)),
              child: elegido ? Center(child: Container(width: 12, height: 12, decoration: BoxDecoration(color: colores.acento, shape: BoxShape.circle))) : null,
            ),
          ],
        ),
      ),
    );
  }
}
