import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../comun/aviso_superior.dart';
import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/venta.dart';
import '../tema/acentos.dart';
import '../comun/tarjetas.dart';
import '../comun/fechas.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'editor_venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/esqueleto.dart';
import 'devolucion_mp_dialogo.dart';

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
  final _busquedaCtrl = TextEditingController();
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
    _busquedaCtrl.dispose();
    _efectivoMixtoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final motivo = await _pedirMotivo();
    if (motivo == null || motivo.trim().isEmpty) return;
    final ok = await _c.guardar(motivo: motivo);
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<String?> _pedirMotivo() {
    final ctrl = TextEditingController();
    return mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: '¿Por qué se edita esta venta?',
        contenido: CampoTexto(controller: ctrl, etiqueta: 'Motivo', autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Confirmar', onPressed: () => Navigator.of(context).pop(ctrl.text)),
        ],
      ),
    );
  }

  Future<void> _agregarLineaLibre() async {
    final detalleCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    final resultado = await mostrarModal<bool>(
      context,
      builder: (context) => Modal(
        titulo: 'Renglón libre',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CampoTexto(controller: detalleCtrl, etiqueta: 'Detalle', autofocus: true),
            const SizedBox(height: Espaciado.md),
            CampoPlata(controller: montoCtrl, etiqueta: 'Monto'),
          ],
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
          BotonPrimario(texto: 'Agregar', onPressed: () => Navigator.of(context).pop(true)),
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
    final ctrl = TextEditingController();
    final motivo = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: '¿Anular esta venta?',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Se repone el stock y se revierte la caja. La venta sigue viéndose en el historial, marcada como anulada.'),
            const SizedBox(height: Espaciado.md),
            CampoTexto(controller: ctrl, etiqueta: 'Motivo', autofocus: true),
          ],
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Anular', onPressed: () => Navigator.of(context).pop(ctrl.text.trim())),
        ],
      ),
    );
    ctrl.dispose();
    if (motivo == null || motivo.isEmpty) return;
    try {
      await _c.anular(motivo: motivo);
      if (mounted) await ofrecerDevolucionMp(context, widget.db, widget.ventaId);
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) mostrarAviso(context, e.message.toString());
    }
  }

  // "Lenguaje de diseño" (El dueño, 2026-09-28, mock `EditorVenta`): a la
  // izquierda, buscar y las líneas (las que cambiaron o son nuevas, en azul
  // con su marca); a la derecha, el total nuevo contra el de antes, el
  // medio de pago y "Qué se va a ajustar" (stock, separaciones, ganancia)
  // antes de guardar — nada se toca hasta "Guardar cambios", que pide el
  // motivo (Regla 9).
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
            titulo: 'Historial',
            child: c.cargando ? const EsqueletoLista() : _contenido(context, c),
          );
        },
      ),
    );
  }

  Widget _contenido(BuildContext context, EditorVentaControlador c) {
    final textTheme = Theme.of(context).textTheme;
    final v = c.ventaOriginal!;
    final medioAntes = switch (c.medioElegido) {
      ComposicionPago.efectivo => 'en efectivo',
      ComposicionPago.virtual => 'en Mercado Pago',
      _ => 'mixto',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ActionChip(
              avatar: const IconoPlz(IconosPlazoleta.arrowBackRounded, size: 18),
              label: const Text('Volver'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Espaciado.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Editar venta #${widget.ventaId}', style: textTheme.headlineMedium),
                  Text(
                    '${fechaLarga(v.fecha)} · ${horaCorta(v.fecha)} · cobrada $medioAntes',
                    style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario),
                  ),
                ],
              ),
            ),
            const Insignia(texto: 'Editando: no se guarda hasta que confirmes', tono: Tono.alerta),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Lineas(c: c, busquedaCtrl: _busquedaCtrl, alAgregarLibre: _agregarLineaLibre),
              ),
              const SizedBox(width: Espaciado.lg),
              SizedBox(
                width: 470,
                child: _Resumen(c: c, efectivoMixtoCtrl: _efectivoMixtoCtrl, alGuardar: _guardar, alAnular: _anular),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lineas extends StatelessWidget {
  const _Lineas({required this.c, required this.busquedaCtrl, required this.alAgregarLibre});

  final EditorVentaControlador c;
  final TextEditingController busquedaCtrl;
  final VoidCallback alAgregarLibre;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CampoTexto(
                controller: busquedaCtrl,
                pista: 'Agregar un producto a esta venta',
                prefixIcon: const IconoPlz(IconosPlazoleta.search),
                sobreElFondo: true,
                onChanged: c.buscar,
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            BotonSecundario(texto: '+ Renglón libre', onPressed: alAgregarLibre),
          ],
        ),
        if (c.resultadosBusqueda.isNotEmpty) ...[
          const SizedBox(height: Espaciado.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Superficie(
              padding: const EdgeInsets.all(Espaciado.sm),
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final producto in c.resultadosBusqueda)
                      ListTile(
                        dense: true,
                        title: Text(producto.nombre),
                        trailing: Text(
                          formatearARS((producto.esPesable ? producto.precioPorKiloCentavos : producto.precioCentavos) ?? 0),
                          style: textTheme.bodyMedium?.tabular,
                        ),
                        onTap: () {
                          busquedaCtrl.clear();
                          c.agregarProducto(producto);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: Superficie(
            padding: const EdgeInsets.all(Espaciado.sm),
            child: c.lineas.isEmpty
                ? Center(child: Text('La venta quedó sin productos', style: textTheme.bodySmall))
                : ListView.separated(
                    itemCount: c.lineas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Espaciado.xs),
                    itemBuilder: (context, i) => _FilaLinea(c: c, indice: i),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilaLinea extends StatelessWidget {
  const _FilaLinea({required this.c, required this.indice});

  final EditorVentaControlador c;
  final int indice;

  @override
  Widget build(BuildContext context) {
    final l = c.lineas[indice];
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final cambio = c.cambioDeLinea(l);
    final porUnidad = l is LineaVentaPorUnidad && !l.esVarios;
    final unitario = l is LineaVentaPorUnidad
        ? '${formatearARS(l.precioUnitarioCentavos)} c/u'
        : '${formatearARS((l as LineaVentaPesable).precioPorKiloCentavos)}/kg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm),
      decoration: BoxDecoration(
        color: cambio == null ? colores.fondoBloque : colores.acento.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radioControlEscritorio + 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l.nombreProducto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte),
                      ),
                    ),
                    if (cambio != null) ...[
                      const SizedBox(width: Espaciado.sm),
                      Insignia(texto: cambio, tono: cambio == 'Nuevo' ? Tono.ganancia : Tono.acento),
                    ],
                  ],
                ),
                Text(unitario, style: textTheme.bodySmall),
              ],
            ),
          ),
          if (porUnidad)
            Container(
              decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(radioControlEscritorio)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(tooltip: 'Restar uno', icon: const IconoPlz(IconosPlazoleta.remove), onPressed: () => c.sumarUnidad(indice, -1)),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${l.cantidad}',
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
                    ),
                  ),
                  IconButton(tooltip: 'Sumar uno', icon: const IconoPlz(IconosPlazoleta.add), onPressed: () => c.sumarUnidad(indice, 1)),
                ],
              ),
            )
          else if (l is LineaVentaPesable)
            Text('${l.gramos} g', style: textTheme.titleMedium?.tabular),
          SizedBox(
            width: 120,
            child: Text(
              formatearARS(l.subtotalCentavos),
              textAlign: TextAlign.right,
              style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
            ),
          ),
          IconButton(
            tooltip: 'Quitar ${l.nombreProducto}',
            icon: const IconoPlz(IconosPlazoleta.deleteOutline),
            onPressed: () => c.quitarLinea(indice),
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.c, required this.efectivoMixtoCtrl, required this.alGuardar, required this.alAnular});

  final EditorVentaControlador c;
  final TextEditingController efectivoMixtoCtrl;
  final VoidCallback alGuardar;
  final VoidCallback alAnular;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final acentos = context.acentosPlazoleta;
    final antes = c.ventaOriginal!.totalCentavos;
    final total = c.resultado?.totalCentavos ?? c.subtotalCentavos;
    final delta = total - antes;
    final stock = c.ajustesDeStock;
    final separar = c.ajustesDeSeparacion;
    final sobre = acentos.textoSobreColor;

    String signo(int n) => n > 0 ? '+ ${formatearARS(n)}' : '− ${formatearARS(-n)}';

    Widget renglon(String etiqueta, String valor) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: textTheme.bodyMedium)),
          Text(valor, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              Superficie(
                degrade: acentos.gradienteAcento,
                padding: const EdgeInsets.all(Espaciado.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total nuevo',
                      style: textTheme.bodyMedium?.copyWith(color: sobre.withValues(alpha: 0.75), fontWeight: Pesos.medium),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(formatearARS(total), style: textTheme.displayLarge?.copyWith(color: sobre).tabular),
                    ),
                    const SizedBox(height: Espaciado.xs),
                    Row(
                      children: [
                        Text('Antes ${formatearARS(antes)}', style: textTheme.bodyMedium?.copyWith(color: sobre.withValues(alpha: 0.75))),
                        if (delta != 0) ...[
                          const SizedBox(width: Espaciado.sm),
                          Insignia(texto: signo(delta), tono: delta > 0 ? Tono.ganancia : Tono.alerta),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espaciado.md),
              TarjetaSeccion(
                titulo: 'Medio de pago',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: GrupoPildoras<ComposicionPago?>(
                          opciones: const [
                            (ComposicionPago.efectivo, 'Efectivo'),
                            (ComposicionPago.virtual, 'Mercado Pago'),
                            (ComposicionPago.mixto, 'Mixto'),
                          ],
                          elegida: c.medioElegido,
                          onElegir: (m) => c.elegirMedio(m!),
                        ),
                      ),
                    ),
                    if (c.medioElegido == ComposicionPago.mixto) ...[
                      const SizedBox(height: Espaciado.md),
                      CampoPlata(
                        controller: efectivoMixtoCtrl,
                        etiqueta: 'Parte en efectivo',
                        onChanged: (v) {
                          try {
                            c.fijarMontoEfectivoMixto(parsearARS(v));
                          } on FormatException {
                            // se sigue escribiendo
                          }
                        },
                      ),
                    ],
                    if (delta != 0 && c.medioElegido != ComposicionPago.efectivo) ...[
                      const SizedBox(height: Espaciado.sm),
                      Text(
                        delta > 0
                            ? 'Si sube el total, cobrá la diferencia de ${formatearARS(delta)} aparte.'
                            : 'Si baja el total, devolvé ${formatearARS(-delta)}.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Espaciado.md),
              TarjetaSeccion(
                titulo: 'Qué se va a ajustar',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stock.isEmpty && separar.isEmpty)
                      Text('Nada todavía: cambiá una cantidad o agregá un producto.', style: textTheme.bodySmall),
                    for (final a in stock)
                      renglon('Stock · ${a.nombre}', '${a.delta > 0 ? '+' : '−'} ${a.delta.abs()}${a.pesable ? ' g' : ' u.'}'),
                    for (final a in separar) renglon('A separar · ${a.proveedor}', signo(a.deltaCentavos)),
                    const Divider(),
                    renglon('Ganancia de la venta', formatearARS(c.gananciaNuevaCentavos)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.md),
        BotonPrimario(texto: 'Guardar cambios', onPressed: c.lineas.isEmpty ? null : alGuardar),
        const SizedBox(height: Espaciado.sm),
        Row(
          children: [
            Expanded(
              child: BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).maybePop()),
            ),
            if (c.sesionAbierta) ...[
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: BotonSecundario(texto: 'Anular venta', onPressed: alAnular),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
