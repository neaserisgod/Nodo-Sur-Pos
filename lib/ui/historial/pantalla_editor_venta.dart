// Editor de una venta ya cobrada (fase 9), hecho desde cero como el mock v4 (`SCR.editorVenta`, 2026-10-06): a la
// izquierda las líneas (con lo que cambió marcado) y el medio de pago; a la derecha el total nuevo contra el de antes,
// "Qué se va a ajustar" (stock, separaciones, ganancia) y Guardar / Anular / Descartar. Nada se toca hasta "Guardar
// cambios", que pide el motivo (Regla 9).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/venta.dart';
import '../comun/armazon_gestion.dart';
import '../comun/aviso_superior.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import 'devolucion_mp_dialogo.dart';
import 'editor_venta_controlador.dart';

class PantallaEditorVenta extends StatefulWidget {
  const PantallaEditorVenta({super.key, required this.db, required this.ventaId, required this.usuarioId});

  final AppDatabase db;
  final int ventaId;
  final int usuarioId;

  @override
  State<PantallaEditorVenta> createState() => _PantallaEditorVentaState();
}

class _PantallaEditorVentaState extends State<PantallaEditorVenta> {
  late final EditorVentaControlador _c;
  final _efectivoMixtoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = EditorVentaControlador(widget.db, ventaId: widget.ventaId, usuarioId: widget.usuarioId);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    _efectivoMixtoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final motivo = await _pedirTexto(
      titulo: '¿Por qué se edita esta venta?',
      subtitulo: 'Queda registrado quién la editó, cuándo y por qué.',
      etiqueta: 'Motivo',
      boton: 'Confirmar',
    );
    if (motivo == null || motivo.trim().isEmpty) return;
    final ok = await _c.guardar(motivo: motivo);
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<String?> _pedirTexto({required String titulo, String? subtitulo, required String etiqueta, required String boton, bool rojo = false}) {
    final ctrl = TextEditingController();
    return mostrarModalMock<String>(
      context,
      builder: (context) => ModalMock(
        titulo: titulo,
        subtitulo: subtitulo,
        ancho: AnchoModal.angosto,
        cuerpo: [Campo(etiqueta: etiqueta, controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v))],
        pie: [
          Btn(boton, variante: rojo ? VarBtn.red : VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(ctrl.text.trim())),
          Btn('Cancelar', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  Future<void> _agregarLineaLibre() async {
    final detalleCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    final resultado = await mostrarModalMock<bool>(
      context,
      builder: (context) => ModalMock(
        titulo: 'Renglón libre',
        subtitulo: 'Un monto suelto, sin producto del catálogo.',
        ancho: AnchoModal.angosto,
        cuerpo: [
          Campo(etiqueta: 'Detalle', controller: detalleCtrl, pista: 'Ej: Envío a domicilio', autofocus: true),
          Campo(etiqueta: 'Monto', controller: montoCtrl, pista: r'$ 0', grande: true, teclado: TextInputType.number),
        ],
        pie: [
          Btn('Agregar', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(true)),
          Btn('Cancelar', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
    if (resultado != true) return;
    if (detalleCtrl.text.trim().isEmpty) return;
    final int monto;
    try {
      monto = parsearARS(montoCtrl.text);
    } on FormatException {
      return;
    }
    if (monto <= 0) return;
    _c.agregarLineaLibre(detalle: detalleCtrl.text.trim(), montoCentavos: monto);
  }

  Future<void> _anular() async {
    final motivo = await _pedirTexto(
      titulo: 'Anular venta #${widget.ventaId}',
      subtitulo: 'Revierte el stock y la caja. Nunca borra la venta: queda anotada como anulada.',
      etiqueta: 'Motivo (obligatorio)',
      boton: 'Anular venta',
      rojo: true,
    );
    if (motivo == null || motivo.isEmpty) return;
    try {
      await _c.anular(motivo: motivo);
      if (mounted) await ofrecerDevolucionMp(context, widget.db, widget.ventaId);
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) mostrarAviso(context, e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EditorVentaControlador>.value(
      value: _c,
      child: Consumer<EditorVentaControlador>(
        builder: (context, c, _) {
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'historial',
            usuarioId: widget.usuarioId,
            titulo: 'Editar venta #${widget.ventaId}',
            subtitulo: c.cargando ? null : _subtitulo(c),
            acciones: [
              Btn('Volver al historial', variante: VarBtn.ton, icono: Ic.back, onTap: () => Navigator.of(context).maybePop()),
            ],
            child: c.cargando ? const SizedBox.shrink() : _contenido(context, c),
          );
        },
      ),
    );
  }

  String _subtitulo(EditorVentaControlador c) {
    final v = c.ventaOriginal!;
    final medio = switch (c.medioElegido) {
      ComposicionPago.efectivo => 'en efectivo',
      ComposicionPago.virtual => 'en Mercado Pago',
      _ => 'mixto',
    };
    return '${fechaLarga(v.fecha)} · ${horaCorta(v.fecha)} · cobrada $medio';
  }

  Widget _contenido(BuildContext context, EditorVentaControlador c) {
    final ancho = MediaQuery.sizeOf(context).width;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Lineas(c: c, alAgregarLibre: _agregarLineaLibre)),
              const SizedBox(height: 14),
              _MedioDePago(c: c, efectivoMixtoCtrl: _efectivoMixtoCtrl),
            ],
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: ancho >= 1700 ? 480 : 400,
          child: _Resumen(c: c, alGuardar: _guardar, alAnular: _anular),
        ),
      ],
    );
  }
}

/// `.card` de la izquierda: "Productos", buscar para agregar, las líneas como en el carrito de Venta y los dos botones
/// de agregar.
class _Lineas extends StatelessWidget {
  const _Lineas({required this.c, required this.alAgregarLibre});

  final EditorVentaControlador c;
  final VoidCallback alAgregarLibre;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Sec('Productos'),
              const Spacer(),
              Text('Editando: no se guarda hasta que confirmes', style: estilo(13.5, 400, color: p.mute)),
            ],
          ),
          const SizedBox(height: 12),
          BuscadorPagina(pista: 'Agregar un producto a esta venta', alto: 50, fondo: p.papel, onCambio: c.buscar),
          if (c.resultadosBusqueda.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: p.papel,
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final producto in c.resultadosBusqueda)
                        Kv(
                          producto.nombre,
                          pesos((producto.esPesable ? producto.precioPorKiloCentavos : producto.precioCentavos) ?? 0),
                          colorValor: p.tinta,
                          onTap: () => c.agregarProducto(producto),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: c.lineas.isEmpty
                ? const Nota(texto: 'La venta quedó sin productos: anulala en lugar de dejarla vacía.', tono: TonoMock.w)
                : ListView.separated(
                    itemCount: c.lineas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _FilaLinea(c: c, indice: i),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Btn('Renglón libre', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, icono: Ic.plus, onTap: alAgregarLibre),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una línea como `.cl` del carrito: nombre, precio unitario y qué cambió; el "−/+" (por unidad), el subtotal y el
/// tacho.
class _FilaLinea extends StatelessWidget {
  const _FilaLinea({required this.c, required this.indice});

  final EditorVentaControlador c;
  final int indice;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final l = c.lineas[indice];
    final cambio = c.cambioDeLinea(l);
    final porUnidad = l is LineaVentaPorUnidad && !l.esVarios;
    final unitario = l is LineaVentaPorUnidad
        ? (l.esVarios ? 'Renglón libre' : '${pesos(l.precioUnitarioCentavos)} c/u')
        : '${pesos((l as LineaVentaPesable).precioPorKiloCentavos)} el kilo';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
      decoration: BoxDecoration(
        color: cambio == null ? p.papel : p.azulClaro,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nombreProducto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(17, 550, color: p.tinta)),
                Text(unitario, style: estilo(14, 400, color: p.mute)),
                if (cambio != null) Text(cambio, style: estilo(12.5, 500, color: cambio == 'Nuevo' ? p.g : p.w)),
              ],
            ),
          ),
          if (porUnidad)
            Container(
              height: 44,
              decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BotonPaso(icono: Ic.minus, tooltip: 'Restar uno', onTap: () => c.sumarUnidad(indice, -1)),
                  SizedBox(
                    width: 36,
                    child: Text('${l.cantidad}', textAlign: TextAlign.center, style: estilo(17, 600, color: p.tinta, num: true)),
                  ),
                  _BotonPaso(icono: Ic.plus, tooltip: 'Sumar uno', onTap: () => c.sumarUnidad(indice, 1)),
                ],
              ),
            )
          else if (l is LineaVentaPesable)
            Text('${l.gramos} g', style: estilo(17, 500, color: p.tinta, num: true)),
          SizedBox(
            width: 130,
            child: Text(pesos(l.subtotalCentavos), textAlign: TextAlign.right, style: estilo(18, 600, color: p.tinta, num: true)),
          ),
          const SizedBox(width: 6),
          BotonCirculo(
            icono: Ic.trash,
            etiqueta: 'Quitar ${l.nombreProducto}',
            diametro: 40,
            tamanioIcono: 19,
            fondo: Colors.transparent,
            onTap: () => c.quitarLinea(indice),
          ),
        ],
      ),
    );
  }
}

class _BotonPaso extends StatelessWidget {
  const _BotonPaso({required this.icono, required this.tooltip, required this.onTap});
  final Ic icono;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Tocable(
      onTap: onTap,
      radio: 999,
      etiqueta: tooltip,
      child: SizedBox(width: 40, height: 44, child: Center(child: Icono(icono, size: 14, grosor: 2.6, color: context.p.tinta))),
    ),
  );
}

class _MedioDePago extends StatelessWidget {
  const _MedioDePago({required this.c, required this.efectivoMixtoCtrl});

  final EditorVentaControlador c;
  final TextEditingController efectivoMixtoCtrl;

  @override
  Widget build(BuildContext context) {
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Sec('Medio de pago'),
          const SizedBox(height: 12),
          Seg<ComposicionPago>(
            llenar: true,
            opciones: const [
              (ComposicionPago.efectivo, 'Efectivo'),
              (ComposicionPago.virtual, 'Mercado Pago'),
              (ComposicionPago.mixto, 'Mixto'),
            ],
            valor: c.medioElegido ?? ComposicionPago.efectivo,
            onCambio: c.elegirMedio,
          ),
          if (c.medioElegido == ComposicionPago.mixto) ...[
            const SizedBox(height: 12),
            Campo(
              etiqueta: 'Parte en efectivo',
              controller: efectivoMixtoCtrl,
              pista: r'$ 0',
              teclado: TextInputType.number,
              onChanged: (v) {
                try {
                  c.fijarMontoEfectivoMixto(parsearARS(v));
                } on FormatException {
                  // se sigue escribiendo
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.c, required this.alGuardar, required this.alAnular});

  final EditorVentaControlador c;
  final VoidCallback alGuardar;
  final VoidCallback alAnular;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final antes = c.ventaOriginal!.totalCentavos;
    final total = c.resultado?.totalCentavos ?? c.subtotalCentavos;
    final delta = total - antes;
    final stock = c.ajustesDeStock;
    final separar = c.ajustesDeSeparacion;

    Widget renglon(String etiqueta, String valor, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo(15, 400, color: p.mute))),
          Text(valor, style: estilo(15, 600, color: color ?? p.tinta, num: true)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BloqueHero(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total nuevo', style: estilo(15, 600, color: p.heroSub)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: NumeroQueCuenta(valor: total, formato: pesos, estilo: estilo(52, 550, color: p.sobreHero, em: -.04, num: true)),
              ),
              const SizedBox(height: 6),
              Text(
                delta == 0 ? 'Antes ${pesos(antes)}' : 'Antes ${pesos(antes)} · diferencia ${pesosConSigno(delta)}',
                style: estilo(15.5, 400, color: p.heroSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Tarjeta(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            child: ListView(
              children: [
                const Sec('Qué se va a ajustar'),
                const SizedBox(height: 8),
                if (stock.isEmpty && separar.isEmpty)
                  Text('Nada todavía: cambiá una cantidad o agregá un producto.', style: estilo(15, 400, color: p.mute)),
                for (final a in stock) renglon('Stock · ${a.nombre}', '${a.delta > 0 ? '+' : '−'} ${a.delta.abs()}${a.pesable ? ' g' : ' u.'}'),
                for (final a in separar) renglon('A separar · ${a.proveedor}', pesosConSigno(a.deltaCentavos)),
                Container(height: 1, color: p.pelo, margin: const EdgeInsets.symmetric(vertical: 4)),
                renglon('Ganancia de la venta', pesos(c.gananciaNuevaCentavos), color: p.g),
                if (delta != 0 && c.medioElegido != ComposicionPago.efectivo) ...[
                  const SizedBox(height: 10),
                  Nota(
                    texto: delta > 0
                        ? 'Si sube el total, cobrá la diferencia de ${pesos(delta)} aparte.'
                        : 'Si baja el total, devolvé ${pesos(-delta)}.',
                    tono: TonoMock.w,
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Al guardar se revierten el stock y la caja de la venta original y se aplican de nuevo. Queda registrado quién y cuándo.',
                  style: estilo(13, 400, color: p.mute),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Btn('Guardar cambios', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: c.lineas.isEmpty ? null : alGuardar),
        const SizedBox(height: 8),
        Row(
          children: [
            if (c.sesionAbierta) ...[
              Expanded(child: Btn('Anular venta', variante: VarBtn.out, ancho: true, onTap: alAnular)),
              const SizedBox(width: 8),
            ],
            Expanded(child: Btn('Descartar cambios', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).maybePop())),
          ],
        ),
      ],
    );
  }
}
