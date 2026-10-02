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

import '../domain/descuento.dart';
import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'dialogo_cobro_posnet_companion.dart';
import 'fila_linea_carrito.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';
import 'sesion_abierta_gate.dart';
import 'tema/chip_icono.dart';
import 'tema/colores_companion.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import 'tema/tema_companion.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';
import 'tema/app_bar_companion.dart';

enum _MedioVenta { efectivo, qr, debito }

class PantallaCarritoVenta extends StatefulWidget {
  const PantallaCarritoVenta({
    super.key,
    required this.cliente,
    required this.servicio,
    required this.usuarioId,
    required this.carrito,
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

  /// Une elegir el medio y cobrar en un solo toque (El dueño, 2026-09-18:
  /// "para seleccionar si es efectivo, qr o débito se hace al momento de
  /// tocar y confirmar la venta") — antes eran dos pasos: tocar un medio
  /// (solo calculaba el total) y recién ahí tocar "Cobrar" aparte. Ahora
  /// cada botón de medio ES la acción de cobrar; `_elegirMedio` sigue
  /// existiendo tal cual para cuando cambia el descuento con un medio ya
  /// elegido (`_recalcularSiHayMedio`), que sí necesita recalcular sin
  /// volver a cobrar.
  Future<void> _elegirYCobrar(_MedioVenta medio) async {
    await _elegirMedio(medio);
    if (!mounted || _resultado == null) return;
    await _confirmar();
  }

  void _eliminarLinea(int index) => _actualizarLinea(index, null);

  /// `nueva` null = eliminar la línea (mismo criterio que el escritorio:
  /// restar por debajo de 1 saca la línea entera, el dueño, 2026-09-07: "no
  /// puedo agregar más de 1 unidad a la vez... misma funcionalidad que
  /// carrito").
  void _actualizarLinea(int index, LineaVenta? nueva) {
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

  /// Mantener presionado QR/Débito (El dueño, 2026-09-18: el paso previo de
  /// "elegir y después Cobrar" que sostenía este atajo desapareció al
  /// unificar los botones) llama directo a esto, sin pasar por
  /// `_elegirMedio` — no hace falta calcular el total con Point de por
  /// medio para algo que nunca lo va a tocar.
  Future<void> _elegirYCobrarAMano(_MedioVenta medio) async {
    setState(() => _medio = medio);
    await _cobrarAMano();
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
      );
      await _ventaCobrada(r.ventaId, r.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _ventaCobrada(int ventaId, int totalCentavos) async {
    widget.carrito.clear();
    _tipoDescuento = TipoDescuento.monto;
    _descuentoCtrl.clear();
    if (!mounted) return;
    final imprimir = await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(IconosPlazoleta.checkCircle, color: context.colores.acento),
              const SizedBox(width: Espaciado.sm),
              Text('Venta cobrada', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Venta #$ventaId — ${formatearARS(totalCentavos)}',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cerrar'),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Imprimir ticket'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (imprimir == true) {
      final cliente = widget.cliente;
      if (cliente == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Para imprimir hace falta estar emparejado con la PC.'),
            ),
          );
        }
        return;
      }
      try {
        await cliente.imprimirTicket(ventaId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo imprimir: ${mensajeDeError(e)}'),
            ),
          );
        }
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final buscando = _busquedaCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: const AppBarCompanion(titulo: 'Carrito', etiquetaSalida: 'Cerrar'),
      body: SafeArea(
        child: _sesionCajaId == null
            ? SesionAbiertaGate(
                cliente: widget.servicio,
                usuarioId: widget.usuarioId,
                onLista: (id) => setState(() => _sesionCajaId = id),
              )
            : Column(
                children: [
                  _campoBuscador(context),
                  // Mientras se busca, el carrito queda oculto detrás de
                  // los resultados (no entran los dos juntos en la
                  // pantalla) — esta franja chica es la única señal de que
                  // lo que ya se agregó sigue ahí, sin tener que borrar la
                  // búsqueda para confirmarlo (El dueño, 2026-09-14: "no hay
                  // espacio").
                  if (buscando && widget.carrito.isNotEmpty)
                    _resumenCarritoCompacto(context),
                  Expanded(
                    child: buscando
                        ? _listaResultadosBusqueda(context)
                        : _listaLineas(context),
                  ),
                  if (!buscando) _panelTotal(context),
                ],
              ),
      ),
    );
  }

  Widget _campoBuscador(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.sm,
      ),
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
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
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

  /// Reducido a fondo (El dueño, 2026-09-18: "el carrito ocupa demasiado
  /// espacio con los botones y poco para los productos") — el descuento
  /// pasó de ser una fila propia (botón de 56px + su separación) a un ícono
  /// chico arriba a la derecha de la tarjeta del total; los botones de
  /// medio de pago bajaron de 56 a 44px (son un selector, no el CTA
  /// principal); los huecos entre secciones bajaron de `md` a `sm`. Solo
  /// "Cobrar" conserva el alto completo — es la única acción que tiene que
  /// pesar.
  Widget _panelTotal(BuildContext context) {
    final subtotal = Venta(lineas: widget.carrito).subtotalCentavos;
    final sinCarrito = widget.carrito.isEmpty || _calculando || _cobrando;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorEnLinea(_error!),
            const SizedBox(height: Espaciado.sm),
          ],
          // La tarjeta del precio ES el botón de cobrar (El dueño, 2026-09-18:
          // "no entendiste, quiero que el botón del precio sea COBRAR") —
          // no una tarjeta con el total y, aparte, un botón separado abajo:
          // tocar el precio directamente abre el menú de medios, y elegir
          // uno ahí calcula y cobra. El único control que queda aparte
          // adentro de la tarjeta es el ícono de descuento (tiene su propio
          // toque, no dispara el menú de cobro).
          _tarjetaCobrar(context, subtotal: subtotal, deshabilitado: sinCarrito),
        ],
      ),
    );
  }

  /// La tarjeta del precio ES el botón de cobrar (El dueño, 2026-09-18: "quiero
  /// que el botón del precio sea COBRAR") — un solo elemento, no una
  /// tarjeta con el total y un botón separado debajo. Tocarla abre una hoja
  /// con Efectivo/QR/Débito (cada uno con su color propio) más, separado
  /// por una línea, "cobrar a mano" para QR/Débito (saltar la terminal
  /// Point directo). Elegir cualquier ítem calcula el total con ese medio y
  /// cobra en el mismo gesto. El ícono de descuento sigue siendo un control
  /// propio adentro, con su toque independiente del resto de la tarjeta.
  ///
  /// Antes esto abría un `PopupMenuButton` (el desplegable nativo de
  /// Android) — El dueño, 2026-09-19: "está bug el dropdown del método de
  /// pago". Ese widget está pensado para un ícono chico como disparador;
  /// acá el disparador es la tarjeta entera (bien ancha, cerca del borde
  /// inferior de la pantalla), y su cálculo de posición no está pensado
  /// para eso — además quedaba como el único menú "de fábrica" en una app
  /// que ya convirtió todo lo demás a hojas de vidrio. Una hoja
  /// (`mostrarHojaVidrio`) es consistente con el resto Y no depende de la
  /// geometría del botón que la abre.
  Widget _tarjetaCobrar(BuildContext context, {required int subtotal, required bool deshabilitado}) {
    final acentos = context.acentos;
    final textoSobre = acentos.textoSobreColor;
    final procesando = _calculando || _cobrando;
    final resultado = _resultado;
    final hayDesglose = resultado != null &&
        (resultado.recargoCigarrillosCentavos > 0 ||
            resultado.descuentoCentavos > 0 ||
            resultado.redondeoCentavos > 0);

    return BloqueHero(
      animar: false,
      padding: EdgeInsets.zero,
      child: Presionable(
        radio: radioSuperficieCompanion,
        onTap: deshabilitado ? null : () => _abrirHojaCobrar(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.md, Espaciado.sm, Espaciado.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatearARS(resultado?.totalCentavos ?? subtotal),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: textoSobre),
                    ),
                    Text(
                      hayDesglose
                          ? [
                              if (resultado.recargoCigarrillosCentavos > 0)
                                'Recargo ${formatearARS(resultado.recargoCigarrillosCentavos)}',
                              if (resultado.descuentoCentavos > 0)
                                'Desc. -${formatearARS(resultado.descuentoCentavos)}',
                              if (resultado.redondeoCentavos > 0)
                                'Redondeo ${formatearARS(resultado.redondeoCentavos)}',
                            ].join(' · ')
                          : 'Tocá para cobrar',
                      style: TextStyle(
                        color: textoSobre.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: hayDesglose ? Pesos.regular : Pesos.medium,
                      ),
                    ),
                  ],
                ),
              ),
              _botonDescuento(context, deshabilitado: deshabilitado),
              if (procesando)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espaciado.sm),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: textoSobre),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: Espaciado.sm),
                  child: Icon(IconosPlazoleta.arrowForwardIosRounded, size: 16, color: textoSobre.withValues(alpha: 0.85)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirHojaCobrar(BuildContext context) async {
    final colores = context.colores;
    final acentos = context.acentos;
    await mostrarHojaVidrio<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cobrar', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Espaciado.md),
          _filaMedio(
            context,
            'Efectivo',
            colores.acento,
            IconosPlazoleta.paymentsOutlined,
            () => _elegirYCobrar(_MedioVenta.efectivo),
          ),
          _filaMedio(
            context,
            'QR',
            acentos.qr,
            IconosPlazoleta.qrCode,
            () => _elegirYCobrar(_MedioVenta.qr),
          ),
          _filaMedio(
            context,
            'Débito',
            acentos.debito,
            IconosPlazoleta.creditCard,
            () => _elegirYCobrar(_MedioVenta.debito),
          ),
          Divider(color: colores.borde, height: Espaciado.xl),
          _filaMedioAMano(context, 'QR sin terminal', () => _elegirYCobrarAMano(_MedioVenta.qr)),
          _filaMedioAMano(context, 'Débito sin terminal', () => _elegirYCobrarAMano(_MedioVenta.debito)),
        ],
      ),
    );
  }

  Widget _filaMedio(
    BuildContext context,
    String texto,
    Color color,
    IconData icono,
    VoidCallback onTap,
  ) {
    return Presionable(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
        child: Row(
          children: [
            ChipIcono(icono: icono, color: color),
            const SizedBox(width: Espaciado.md),
            Text(texto, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _filaMedioAMano(BuildContext context, String texto, VoidCallback onTap) {
    final colores = context.colores;
    return Presionable(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
        child: Row(
          children: [
            ChipIcono(icono: IconosPlazoleta.editNote, color: colores.textoTenue),
            const SizedBox(width: Espaciado.md),
            Text(texto, style: TextStyle(color: colores.textoSecundario)),
          ],
        ),
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

  /// Ícono chico con el valor cargado si ya hay uno — antes era un
  /// `OutlinedButton.icon` de ancho completo en su propia fila (El dueño,
  /// 2026-09-18: "el carrito ocupa demasiado espacio con los botones");
  /// ahora vive adentro de la tarjeta del total, a la derecha del número.
  Widget _botonDescuento(BuildContext context, {required bool deshabilitado}) {
    final valor = _valorDescuentoIngresado;
    return IconButton(
      onPressed: deshabilitado ? null : _abrirHojaDescuento,
      icon: Icon(
        valor > 0 ? IconosPlazoleta.sellActivo : IconosPlazoleta.sellOutlined,
        color: context.acentos.textoSobreColor,
      ),
      tooltip: 'Descuento',
    );
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
