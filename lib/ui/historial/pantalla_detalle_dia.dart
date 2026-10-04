// Detalle de un día cerrado — se entra desde Historial → Cierres ("Ver las
// ventas de ese día").
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-28, mock
// `DetalleDia`): volver a Cierres, el día en grande con si cuadró; cuatro
// cifras (vendido en la tarjeta oscura, efectivo, Mercado Pago, ganancia);
// la tabla de ventas con reimprimir / editar / anular por fila; y al
// costado lo vendido por proveedor y las anuladas. "Generar PDF" (la
// planilla del día) arriba a la derecha.
//
// Anular (El dueño, 2026-09-13): solo mientras esta sesión siga abierta —
// revierte stock y caja, nunca borra la venta (Regla 6).

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/pdf_planilla.dart';
import '../../data/repositorio_edicion_venta.dart';
import '../../data/repositorio_historial.dart';
import '../../data/repositorio_ticket.dart';
import '../../domain/dinero.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fechas.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../../data/repositorio_arqueo_intermedio.dart' show ArqueoDelTurno, arqueosDelTurno;
import '../cierre/arqueos_del_turno.dart';
import 'pantalla_editor_venta.dart';
import '../tema/esqueleto.dart';
import 'devolucion_mp_dialogo.dart';

class PantallaDetalleDia extends StatefulWidget {
  const PantallaDetalleDia({super.key, required this.db, required this.sesionId, required this.usuarioId});

  final AppDatabase db;
  final int sesionId;
  final int usuarioId;

  @override
  State<PantallaDetalleDia> createState() => _PantallaDetalleDiaState();
}

class _PantallaDetalleDiaState extends State<PantallaDetalleDia> {
  DetalleDelDia? _detalle;
  List<ArqueoDelTurno> _arqueos = const [];
  bool _generandoPdf = false;
  bool _verAnuladas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final d = await detalleDelDia(widget.db, widget.sesionId);
    final arqueos = await arqueosDelTurno(widget.db, widget.sesionId);
    if (mounted) {
      setState(() {
        _detalle = d;
        _arqueos = arqueos;
      });
    }
  }

  Future<void> _editarVenta(int ventaId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PantallaEditorVenta(db: widget.db, ventaId: ventaId, usuarioId: widget.usuarioId)),
    );
    await _cargar();
  }

  Future<void> _anularVenta(FilaVenta venta) async {
    final motivoCtrl = TextEditingController();
    final motivo = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: '¿Anular la venta de ${formatearARS(venta.totalCentavos)}?',
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Se repone el stock y se revierte la caja. La venta sigue viéndose acá, marcada como anulada.'),
            const SizedBox(height: Espaciado.md),
            CampoTexto(etiqueta: 'Motivo', controller: motivoCtrl, autofocus: true),
          ],
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Anular', onPressed: () => Navigator.of(context).pop(motivoCtrl.text.trim())),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null || motivo.isEmpty) return;
    try {
      await anularVenta(widget.db, ventaId: venta.id, usuarioId: widget.usuarioId, motivo: motivo);
      await _cargar();
      if (mounted) await ofrecerDevolucionMp(context, widget.db, venta.id);
    } on ArgumentError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message.toString())));
    }
  }

  // Único camino para reimprimir un ticket viejo desde que "Imprimir
  // ticket" dejó de ser una acción permanente de la pantalla de venta.
  Future<void> _imprimirVenta(int ventaId) => mostrarDialogoImprimirTicket(context, db: widget.db, ventaId: ventaId);

  Future<void> _generarPdf() async {
    final config = await widget.db.select(widget.db.configuracionTabla).getSingle();
    var carpeta = config.rutaTicketsCarpeta;
    if (carpeta == null) {
      // Bug real (El dueño: "doy a imprimir y no sale nada de seleccionar"): la
      // primera vez que hace falta, se pregunta la carpeta acá mismo.
      carpeta = await getDirectoryPath();
      if (carpeta == null) return;
      await configurarCarpetaTickets(widget.db, carpeta);
      if (!mounted) return;
    }
    setState(() => _generandoPdf = true);
    try {
      final ruta = await guardarPdfPlanilla(widget.db, sesionId: widget.sesionId, carpetaDestino: carpeta);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Guardado en $ruta')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _generandoPdf = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle;
    return PantallaGestion(
      db: widget.db,
      claveActiva: 'historial',
      usuarioId: widget.usuarioId,
      titulo: 'Historial',
      accion: BotonSecundario(texto: _generandoPdf ? 'Generando…' : 'Generar PDF', onPressed: _generandoPdf ? null : _generarPdf),
      child: d == null ? const EsqueletoLista() : _contenido(context, d),
    );
  }

  Widget _contenido(BuildContext context, DetalleDelDia d) {
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final s = d.sesion;
    final validas = d.validas;
    final diferencia = s.diferenciaCentavos ?? 0;
    final abierta = s.estado == 'ABIERTA';
    final dia = fechaLarga(s.fechaApertura);
    final visibles = _verAnuladas ? d.ventas : validas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ActionChip(
              avatar: const Icon(IconosPlazoleta.arrowBackRounded, size: 18),
              label: const Text('Cierres de caja'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Espaciado.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dia[0].toUpperCase() + dia.substring(1), style: textTheme.headlineMedium),
                  Text(
                    [
                      '${validas.length} venta${validas.length == 1 ? '' : 's'}',
                      if (d.nombreEmpleado.isNotEmpty) d.nombreEmpleado,
                      abierta
                          ? 'caja abierta'
                          : (s.fechaCierre == null ? 'caja cerrada' : 'caja cerrada a las ${horaCorta(s.fechaCierre!)}'),
                    ].join(' · '),
                    style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario),
                  ),
                ],
              ),
            ),
            if (!abierta)
              Insignia(
                texto: diferencia == 0
                    ? 'Cuadró justo'
                    : '${diferencia > 0 ? 'Sobraron' : 'Faltaron'} ${formatearARS(diferencia.abs())}',
                tono: diferencia == 0 ? Tono.ganancia : (diferencia < 0 ? Tono.error : Tono.alerta),
              ),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 13,
                child: TarjetaIndicador(
                  etiqueta: 'Vendido',
                  valor: formatearARS(d.vendidoCentavos),
                  nota: validas.isEmpty ? null : 'Promedio ${formatearARS(d.vendidoCentavos ~/ validas.length)} por venta',
                  destacada: true,
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: _Cifra(color: acentos.dinero, etiqueta: 'Efectivo', valor: d.efectivoCentavos, nota: _ventas(d.ventasEfectivo)),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: _Cifra(color: acentos.qr, etiqueta: 'Mercado Pago', valor: d.mpCentavos, nota: _ventas(d.ventasMp)),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                flex: 10,
                child: _Cifra(
                  color: acentos.ganancia,
                  etiqueta: 'Ganancia',
                  valor: d.gananciaCentavos,
                  nota: d.vendidoSinCostoCentavos > 0
                      ? 'Costo ${formatearARS(d.costoCentavos)} · sin costo ${formatearARS(d.vendidoSinCostoCentavos)}'
                      : 'Costo ${formatearARS(d.costoCentavos)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.lg),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Superficie(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _EncabezadoTabla(),
                      Expanded(
                        child: visibles.isEmpty
                            ? Center(child: Text('No hubo ventas este día', style: textTheme.bodySmall))
                            : ListView.builder(
                                itemCount: visibles.length,
                                itemBuilder: (context, i) {
                                  final v = visibles[i];
                                  return _FilaVentaDelDia(
                                    v: v,
                                    puedeAnular: abierta && !v.anulada,
                                    alImprimir: () => _imprimirVenta(v.venta.id),
                                    alEditar: () => _editarVenta(v.venta.id),
                                    alAnular: () => _anularVenta(v.venta),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.md),
                        child: Text('${visibles.length} ventas · más nuevas primero', style: textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Espaciado.lg),
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TarjetaSeccion(
                        titulo: 'Vendido por proveedor',
                        child: Expanded(
                          child: d.porProveedor.isEmpty
                              ? Text('Sin ventas', style: textTheme.bodySmall)
                              : ListView.separated(
                                  itemCount: d.porProveedor.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: Espaciado.md),
                                  itemBuilder: (_, i) {
                                    final p = d.porProveedor[i];
                                    return FilaRanking(
                                      nombre: p.nombre,
                                      valor: formatearARS(p.vendidoCentavos),
                                      proporcion: p.vendidoCentavos / d.porProveedor.first.vendidoCentavos,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                    if (d.anuladas.isNotEmpty) ...[
                      const SizedBox(height: Espaciado.md),
                      Superficie(
                        child: Row(
                          children: [
                            Icon(IconosPlazoleta.errorOutline, color: context.colores.error),
                            const SizedBox(width: Espaciado.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${d.anuladas.length} venta${d.anuladas.length == 1 ? '' : 's'} anulada${d.anuladas.length == 1 ? '' : 's'}',
                                    style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte),
                                  ),
                                  Text(
                                    '${formatearARS(d.anuladas.fold(0, (a, v) => a + v.venta.totalCentavos))} · no suman',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _verAnuladas = !_verAnuladas),
                              child: Text(_verAnuladas ? 'Ocultar' : 'Ver'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Los arqueos opcionales del turno, como registro (El dueño,
                    // 2026-09-28: "que se guarden esos datos en algún lado").
                    if (_arqueos.isNotEmpty) ...[
                      const SizedBox(height: Espaciado.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(child: ArqueosDelTurno(arqueos: _arqueos)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _ventas(int n) => '$n venta${n == 1 ? '' : 's'}';

class _Cifra extends StatelessWidget {
  const _Cifra({required this.color, required this.etiqueta, required this.valor, required this.nota});

  final Color color;
  final String etiqueta;
  final int valor;
  final String nota;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tinta = Color.lerp(color, context.colores.textoPrimario, 0.35);
    return Superficie(
      relleno: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.all(Espaciado.xl - Espaciado.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: textTheme.bodyMedium?.copyWith(color: tinta, fontWeight: Pesos.medium)),
          const SizedBox(height: Espaciado.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatearARS(valor), style: textTheme.headlineMedium?.tabular),
          ),
          const SizedBox(height: Espaciado.xs),
          Text(nota, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

const double _anchoHora = 64;
const double _anchoNumero = 76;
const double _anchoMedio = 92;
const double _anchoTotal = 120;
const double _anchoAcciones = 156;

class _EncabezadoTabla extends StatelessWidget {
  const _EncabezadoTabla();

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: Pesos.medium);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg + 2, vertical: Espaciado.md + 2),
      child: Row(
        children: [
          SizedBox(width: _anchoHora, child: Text('Hora', style: estilo)),
          SizedBox(width: _anchoNumero, child: Text('Venta', style: estilo)),
          Expanded(child: Text('Detalle', style: estilo)),
          SizedBox(width: _anchoMedio, child: Text('Medio', style: estilo)),
          SizedBox(width: _anchoTotal, child: Text('Total', textAlign: TextAlign.right, style: estilo)),
          const SizedBox(width: _anchoAcciones),
        ],
      ),
    );
  }
}

class _FilaVentaDelDia extends StatelessWidget {
  const _FilaVentaDelDia({
    required this.v,
    required this.puedeAnular,
    required this.alImprimir,
    required this.alEditar,
    required this.alAnular,
  });

  final VentaDelDia v;
  final bool puedeAnular;
  final VoidCallback alImprimir;
  final VoidCallback alEditar;
  final VoidCallback alAnular;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final apagado = v.anulada ? colores.textoTenue : null;
    final colorMedio = switch (v.medio) {
      'Ef' => acentos.dinero,
      'MP' => acentos.qr,
      _ => acentos.mixto,
    };
    final editada = v.venta.editadaEn != null;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.only(bottom: Espaciado.sm),
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg + 2),
      decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(26)),
      child: Row(
        children: [
          SizedBox(
            width: _anchoHora,
            child: Text(horaCorta(v.venta.fecha), style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte, color: apagado).tabular),
          ),
          SizedBox(
            width: _anchoNumero,
            child: Text('#${v.venta.id}', style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium, color: apagado)),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    v.detalle.isEmpty ? 'Venta #${v.venta.id}' : v.detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: apagado,
                      decoration: v.anulada ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (v.anulada) ...[const SizedBox(width: Espaciado.sm), const Insignia(texto: 'Anulada', tono: Tono.error)],
                if (editada && !v.anulada) ...[const SizedBox(width: Espaciado.sm), const Insignia(texto: 'Editada', tono: Tono.alerta)],
              ],
            ),
          ),
          SizedBox(width: _anchoMedio, child: Align(alignment: Alignment.centerLeft, child: FilaMedioCompacta(color: colorMedio, etiqueta: v.medio))),
          SizedBox(
            width: _anchoTotal,
            child: Text(
              formatearARS(v.venta.totalCentavos),
              textAlign: TextAlign.right,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: Pesos.fuerte,
                color: apagado,
                decoration: v.anulada ? TextDecoration.lineThrough : null,
              ).tabular,
            ),
          ),
          SizedBox(
            width: _anchoAcciones,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(tooltip: 'Reimprimir', icon: const Icon(IconosPlazoleta.printOutlined), onPressed: alImprimir),
                if (!v.anulada) IconButton(tooltip: 'Editar', icon: const Icon(IconosPlazoleta.editOutlined), onPressed: alEditar),
                if (puedeAnular) IconButton(tooltip: 'Anular', icon: const Icon(IconosPlazoleta.deleteOutline), onPressed: alAnular),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
