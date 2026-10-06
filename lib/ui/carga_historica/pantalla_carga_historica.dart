// Carga histórica producto por producto (reemplaza a la de planilla, fase
// 9) — ver `carga_historica_controlador.dart`. Mismo espíritu que la
// pantalla de venta (buscar → carrito → cobrar) pero deliberadamente más
// simple: fecha elegida una sola vez, sin atajos de teclado, medios de pago
// como mock.
//
// Rediseño v4 (2026-10-06), desde cero como el mock (`SCR.cargaHist`): todo en una pantalla. Arriba a la izquierda el
// calendario del mes (cargado / falta cargar / ya tiene caja) con la hora; debajo el buscador y los productos que
// coinciden como chips; a la derecha, como un ticket, el carrito de la venta que se está cargando, la tanda del día, el
// total, el medio, "Agregar venta" y "Guardar día". El día queda fijo una vez que la tanda tiene ventas (todas son de
// ese día).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/medio_pago.dart';
import '../../domain/venta.dart';
import '../comun/armazon_gestion.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import '../venta/dialogo_editar_cantidad.dart';
import '../venta/dialogo_mixto.dart';
import '../venta/dialogo_monto_varios.dart';
import 'carga_historica_controlador.dart';

class PantallaCargaHistorica extends StatefulWidget {
  const PantallaCargaHistorica({super.key, required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<PantallaCargaHistorica> createState() => _PantallaCargaHistoricaState();
}

class _PantallaCargaHistoricaState extends State<PantallaCargaHistorica> {
  late final CargaHistoricaControlador _c;
  final _horaCtrl = TextEditingController(text: '12:00');
  DateTime? _dia;
  late DateTime _mes;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mes = DateTime(hoy.year, hoy.month);
    _c = CargaHistoricaControlador(widget.db, usuarioId: widget.usuarioId);
    _c.cargarTodo().then((_) {
      if (mounted) _c.focoCampoPrincipal.requestFocus();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _horaCtrl.dispose();
    super.dispose();
  }

  /// Día o hora cambiados: la fecha del controlador es el día elegido a esa hora (si la hora se lee).
  void _aplicarFecha() {
    final dia = _dia;
    final hora = _parsearHora(_horaCtrl.text);
    if (dia == null || hora == null) return;
    _c.elegirFecha(DateTime(dia.year, dia.month, dia.day, hora.$1, hora.$2));
  }

  void _elegirDia(DateTime dia) {
    setState(() => _dia = dia);
    _aplicarFecha();
    _c.focoCampoPrincipal.requestFocus();
  }

  Future<void> _guardarDia() async {
    final sesionId = await _c.guardarDia();
    if (sesionId != null && mounted) Navigator.of(context).pop();
  }

  Future<void> _agregarProducto(Producto producto) async {
    if (producto.esVarios) {
      final monto = await mostrarDialogoMontoVarios(context);
      if (monto != null) _c.agregarProducto(producto, montoVariosCentavos: monto);
    } else {
      _c.agregarProducto(producto);
    }
    _c.focoCampoPrincipal.requestFocus();
  }

  Future<void> _elegirMedio(ComposicionPago medio) async {
    if (medio != ComposicionPago.mixto) {
      _c.elegirMedio(medio);
      return;
    }
    if (_c.carrito.isEmpty) return;
    _c.elegirMedio(ComposicionPago.mixto);
    final confirmado = await mostrarDialogoMixto(context, totalCentavos: _c.resultado!.totalCentavos);
    if (confirmado != null) _c.confirmarMixto(confirmado.monto);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CargaHistoricaControlador>.value(
      value: _c,
      child: Consumer<CargaHistoricaControlador>(
        builder: (context, c, _) {
          final ancho = MediaQuery.sizeOf(context).width;
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'historial',
            usuarioId: widget.usuarioId,
            titulo: 'Cargar un día histórico',
            subtitulo: 'Pasá al sistema las ventas que anotaste en el cuaderno, día por día.',
            acciones: [Btn('Volver', variante: VarBtn.ton, icono: Ic.back, onTap: () => Navigator.of(context).maybePop())],
            child: c.cargando
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          // Ventana baja (1366×768): el calendario ocupa casi todo el alto; la columna scrollea y el
                          // buscador queda con un alto fijo debajo.
                          builder: (context, caja) => caja.maxHeight < 640
                              ? SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _calendario(c),
                                      const SizedBox(height: 14),
                                      SizedBox(height: 280, child: _Busqueda(c: c, onAgregar: _agregarProducto)),
                                    ],
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _calendario(c),
                                    const SizedBox(height: 14),
                                    Expanded(child: _Busqueda(c: c, onAgregar: _agregarProducto)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: ancho >= 1700 ? 560 : 440,
                        child: _Ticket(c: c, onMedio: _elegirMedio, onGuardarDia: _guardarDia),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _calendario(CargaHistoricaControlador c) => _Calendario(
    mes: _mes,
    elegido: _dia,
    diasConCaja: c.diasConCaja,
    ultimoDiaCargado: c.ultimoDiaCargado,
    bloqueado: c.ventasCargadas.isNotEmpty,
    horaCtrl: _horaCtrl,
    onHora: (_) => _aplicarFecha(),
    onElegir: _elegirDia,
    onMes: (m) => setState(() => _mes = m),
  );
}

(int, int)? _parsearHora(String texto) {
  final partes = texto.split(':');
  if (partes.length != 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (h, m);
}

String _fechaCorta(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

String _capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

enum _EstadoDia { conCaja, falta, futuro }

_EstadoDia _estadoDe(DateTime dia, Set<DateTime> diasConCaja) {
  final hoy = DateTime.now();
  if (diasConCaja.contains(dia)) return _EstadoDia.conCaja;
  if (!dia.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) return _EstadoDia.futuro;
  return _EstadoDia.falta;
}

class _Calendario extends StatelessWidget {
  const _Calendario({
    required this.mes,
    required this.elegido,
    required this.diasConCaja,
    required this.ultimoDiaCargado,
    required this.bloqueado,
    required this.horaCtrl,
    required this.onHora,
    required this.onElegir,
    required this.onMes,
  });

  final DateTime mes;
  final DateTime? elegido;
  final Set<DateTime> diasConCaja;
  final DateTime? ultimoDiaCargado;

  /// Con ventas en la tanda, el día ya no se cambia: todas son de ese día.
  final bool bloqueado;
  final TextEditingController horaCtrl;
  final ValueChanged<String> onHora;
  final ValueChanged<DateTime> onElegir;
  final ValueChanged<DateTime> onMes;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final diasDelMes = DateUtils.getDaysInMonth(mes.year, mes.month);
    final vacios = DateTime(mes.year, mes.month).weekday - 1;
    final hoy = DateTime.now();
    final esteMes = mes.year == hoy.year && mes.month == hoy.month;
    final celdas = <Widget>[
      for (var i = 0; i < vacios; i++) const SizedBox.shrink(),
      for (var d = 1; d <= diasDelMes; d++) _celda(context, DateTime(mes.year, mes.month, d)),
    ];
    final filas = <List<Widget>>[];
    for (var i = 0; i < celdas.length; i += 7) {
      filas.add([...celdas.sublist(i, i + 7 > celdas.length ? celdas.length : i + 7)]);
    }

    Widget punto(Color c) => Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    Widget referencia(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [punto(c), const SizedBox(width: 6), Text(t, style: estilo(13, 400, color: p.mute))],
    );

    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Sec('Elegí un día')),
              BotonCirculo(
                icono: Ic.back,
                etiqueta: 'Mes anterior',
                diametro: 40,
                tamanioIcono: 14,
                fondo: p.papel,
                onTap: () => onMes(DateTime(mes.year, mes.month - 1)),
              ),
              SizedBox(
                width: 150,
                child: Text(
                  '${_capitalizar(meses[mes.month - 1])} ${mes.year}',
                  textAlign: TextAlign.center,
                  style: estilo(16, 600, color: p.tinta),
                ),
              ),
              BotonCirculo(
                icono: Ic.arrow,
                etiqueta: 'Mes siguiente',
                diametro: 40,
                tamanioIcono: 14,
                fondo: p.papel,
                onTap: esteMes ? null : () => onMes(DateTime(mes.year, mes.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final l in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(child: Text(l, textAlign: TextAlign.center, style: estilo(12, 600, color: p.soft))),
            ],
          ),
          const SizedBox(height: 6),
          for (final f in filas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: i < f.length ? f[i] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            children: [
              referencia(p.w, 'Falta cargar'),
              referencia(p.soft, 'Ya tiene caja'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 200,
                child: Campo(
                  etiqueta: 'Hora (HH:MM)',
                  controller: horaCtrl,
                  campoKey: const Key('campo_hora_carga_historica'),
                  color: p.papel,
                  onChanged: onHora,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  [
                    bloqueado ? 'El día queda fijo mientras haya ventas cargadas.' : 'Se elige una vez; después se agregan las ventas de ese día con el carrito.',
                    if (ultimoDiaCargado != null) 'Último día cargado: ${_fechaCorta(ultimoDiaCargado!)}.',
                  ].join(' '),
                  style: estilo(13.5, 400, color: p.mute),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, DateTime dia) {
    final p = context.p;
    final estado = _estadoDe(dia, diasConCaja);
    final esElegido = elegido != null && DateUtils.isSameDay(elegido, dia);
    final (fondo, texto) = esElegido
        ? (p.tinta, p.papel)
        : switch (estado) {
            _EstadoDia.conCaja => (p.s2, p.soft),
            _EstadoDia.falta => (p.wbg, p.w),
            _EstadoDia.futuro => (Colors.transparent, p.linea),
          };
    final habilitado = !bloqueado && (estado != _EstadoDia.futuro || DateUtils.isSameDay(dia, DateTime.now()));
    return Tocable(
      onTap: habilitado ? () => onElegir(dia) : null,
      radio: 14,
      etiqueta: '${fechaLarga(dia)}${estado == _EstadoDia.conCaja ? ', ya tiene caja' : (estado == _EstadoDia.falta ? ', falta cargar' : '')}',
      seleccionado: esElegido,
      child: AnimatedContainer(
        duration: ms(200),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(14)),
        child: Text('${dia.day}', style: estilo(15, 600, color: texto, num: true)),
      ),
    );
  }
}

class _Busqueda extends StatelessWidget {
  const _Busqueda({required this.c, required this.onAgregar});

  final CargaHistoricaControlador c;
  final ValueChanged<Producto> onAgregar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final estiloTexto = estilo(19, 450, color: p.tinta, em: -.02);
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(color: p.papel, borderRadius: BorderRadius.circular(999)),
            child: Row(
              children: [
                Icono(Ic.search, size: 20, color: p.tinta),
                const SizedBox(width: 16),
                Expanded(
                  child: AreaMinimaToque(
                    child: TextField(
                      key: const Key('campo_busqueda_carga_historica'),
                      controller: c.campoTexto,
                      focusNode: c.focoCampoPrincipal,
                      style: estiloTexto,
                      cursorColor: p.azul,
                      decoration: decoracionSinBorde('Buscar producto (código, nombre o “200 queso”)', estiloTexto.copyWith(color: p.mute)),
                      onSubmitted: (_) {
                        if (c.coincidencias.isNotEmpty) onAgregar(c.coincidencias.first);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.avisoBusqueda != null) ...[
            const SizedBox(height: 8),
            Text(c.avisoBusqueda!, style: estilo(15, 500, color: p.b)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: c.mostrarSinCoincidencias
                ? Text('Sin productos que coincidan. Cargalo primero en Proveedores.', style: estilo(15, 400, color: p.mute))
                : !c.hayTexto
                ? Text('Escribí para buscar; Enter agrega el primero.', style: estilo(15, 400, color: p.mute))
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final x in c.coincidencias.take(24))
                          ChipMock(
                            x.esPesable ? '${x.nombre} · ${pesos(x.precioPorKiloCentavos ?? 0)}/kg' : x.nombre,
                            chico: true,
                            icono: Ic.plus,
                            onTap: () => onAgregar(x),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// `.ticket` del mock: el carrito de la venta que se carga, la tanda del día y los botones.
class _Ticket extends StatelessWidget {
  const _Ticket({required this.c, required this.onMedio, required this.onGuardarDia});

  final CargaHistoricaControlador c;
  final ValueChanged<ComposicionPago> onMedio;
  final VoidCallback onGuardarDia;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fecha = c.fecha;
    final total = c.resultado?.totalCentavos ?? c.subtotalCentavos;
    final n = c.ventasCargadas.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(36)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sec(fecha == null ? 'Elegí un día en el calendario' : 'Cargando el ${_fechaCorta(fecha)} · ${horaCorta(fecha)}'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (c.carrito.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text('Carrito vacío — buscá un producto a la izquierda.', textAlign: TextAlign.center, style: estilo(17, 400, color: p.mute)),
                  ),
                for (final (i, l) in c.carrito.indexed) ...[
                  _LineaCarrito(c: c, indice: i, linea: l),
                  const SizedBox(height: 6),
                ],
                if (n > 0) ...[
                  const SizedBox(height: 12),
                  Sec('Ventas cargadas — total ${pesos(c.totalTandaCentavos)}'),
                  const SizedBox(height: 8),
                  for (final (i, v) in c.ventasCargadas.indexed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                      decoration: BoxDecoration(color: p.papel, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Expanded(child: Text(v.descripcion, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(15, 400, color: p.tinta))),
                          Text(pesos(v.totalCentavos), style: estilo(15, 600, color: p.tinta, num: true)),
                          const SizedBox(width: 4),
                          BotonCirculo(
                            icono: Ic.x,
                            etiqueta: 'Quitar de la tanda',
                            diametro: 34,
                            tamanioIcono: 14,
                            fondo: Colors.transparent,
                            onTap: () => c.quitarVentaDeLaTanda(i),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          Container(height: 2, margin: const EdgeInsets.symmetric(vertical: 8), color: p.linea),
          Row(
            children: [
              Expanded(child: Text('Total', style: estilo(30, 450, color: p.tinta, em: -.04))),
              Text(pesos(total), style: estilo(30, 450, color: p.tinta, em: -.04, num: true)),
            ],
          ),
          const SizedBox(height: 8),
          Seg<ComposicionPago?>(
            llenar: true,
            opciones: const [
              (ComposicionPago.efectivo, 'Efectivo'),
              (ComposicionPago.virtual, 'Mercado Pago'),
              (ComposicionPago.mixto, 'Mixto'),
            ],
            valor: c.medioElegido,
            onCambio: (m) => onMedio(m!),
          ),
          const SizedBox(height: 8),
          Btn('Agregar venta', variante: VarBtn.out, tam: TamBtn.lg, ancho: true, onTap: c.carrito.isEmpty ? null : () => c.agregarVentaALaTanda()),
          if (c.error != null) ...[
            const SizedBox(height: 8),
            Text(c.error!, style: estilo(15, 500, color: p.b)),
          ],
          const SizedBox(height: 6),
          Btn(
            c.guardando ? 'Guardando…' : 'Guardar día ($n)',
            variante: VarBtn.blue,
            tam: TamBtn.lg,
            ancho: true,
            onTap: c.guardando ? null : onGuardarDia,
          ),
        ],
      ),
    );
  }
}

class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({required this.c, required this.indice, required this.linea});

  final CargaHistoricaControlador c;
  final int indice;
  final LineaVenta linea;

  Future<void> _editarExacto(BuildContext context) async {
    final esUnidad = linea is LineaVentaPorUnidad;
    final valorActual = switch (linea) {
      LineaVentaPorUnidad(:final cantidad) => cantidad,
      LineaVentaPesable(:final gramos) => gramos,
    };
    final nuevo = await mostrarDialogoEditarCantidad(context, titulo: esUnidad ? 'Cantidad' : 'Gramos', valorActual: valorActual, linea: linea);
    if (nuevo == null) return;
    if (esUnidad) {
      c.editarCantidadExacta(indice, nuevo);
    } else {
      c.editarGramosExacto(indice, nuevo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final l = linea;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
      decoration: BoxDecoration(color: p.papel, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Expanded(child: Text(l.nombreProducto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(17, 500, color: p.tinta))),
          if (l is LineaVentaPorUnidad)
            Container(
              height: 40,
              decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Paso(icono: Ic.minus, etiqueta: 'Restar uno', onTap: () => c.ajustarCantidad(indice, -1)),
                  Tocable(
                    onTap: () => _editarExacto(context),
                    radio: 10,
                    etiqueta: 'Cambiar la cantidad',
                    child: SizedBox(width: 34, child: Text('${l.cantidad}', textAlign: TextAlign.center, style: estilo(16, 600, color: p.tinta, num: true))),
                  ),
                  _Paso(icono: Ic.plus, etiqueta: 'Sumar uno', onTap: () => c.ajustarCantidad(indice, 1)),
                ],
              ),
            )
          else if (l is LineaVentaPesable)
            Tocable(
              onTap: () => _editarExacto(context),
              radio: 10,
              etiqueta: 'Cambiar los gramos',
              child: Padding(padding: const EdgeInsets.all(6), child: Text('${l.gramos} g', style: estilo(16, 600, color: p.tinta, num: true))),
            ),
          SizedBox(
            width: 110,
            child: Text(pesos(l.subtotalCentavos), textAlign: TextAlign.right, style: estilo(17, 600, color: p.tinta, num: true)),
          ),
          BotonCirculo(
            icono: Ic.trash,
            etiqueta: 'Quitar la línea',
            diametro: 38,
            tamanioIcono: 18,
            fondo: Colors.transparent,
            onTap: () => c.eliminarLinea(indice),
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.icono, required this.etiqueta, required this.onTap});
  final Ic icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tocable(
    onTap: onTap,
    radio: 999,
    etiqueta: etiqueta,
    child: SizedBox(width: 38, height: 40, child: Center(child: Icono(icono, size: 14, grosor: 2.6, color: context.p.tinta))),
  );
}
