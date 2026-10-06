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

// Rediseño v4 (2026-10-06), desde cero como el mock (`SCR.detalleDia`): el día como título, con cómo cuadró, "Generar
// PDF" y "Volver a Cierres" arriba; cuatro bloques (vendido, efectivo, Mercado Pago, ganancia); la tabla de ventas
// con reimprimir/editar/anular; y a la derecha lo vendido por proveedor, las anuladas y los arqueos del turno.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/pdf_planilla.dart';
import '../../data/repositorio_arqueo_intermedio.dart' show ArqueoDelTurno, arqueosDelTurno;
import '../../data/repositorio_edicion_venta.dart';
import '../../data/repositorio_historial.dart';
import '../../data/repositorio_ticket.dart';
import '../cierre/arqueos_del_turno.dart';
import '../comun/armazon_gestion.dart';
import '../comun/aviso_superior.dart';
import '../comun/fechas.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../kit/kit.dart';
import 'devolucion_mp_dialogo.dart';
import 'pantalla_editor_venta.dart';

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
  bool _ocultarProveedores = false;

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
    final motivo = await mostrarModalMock<String>(
      context,
      builder: (context) => ModalMock(
        titulo: 'Anular venta #${venta.id}',
        subtitulo: 'Revierte el stock y la caja. Nunca borra la venta: queda anotada como anulada.',
        ancho: AnchoModal.angosto,
        cuerpo: [
          Nota(texto: 'Se anula la venta de ${pesos(venta.totalCentavos)}.', tono: TonoMock.w),
          Campo(etiqueta: 'Motivo (obligatorio)', controller: motivoCtrl, autofocus: true),
        ],
        pie: [
          Btn('Anular venta', variante: VarBtn.red, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(motivoCtrl.text.trim())),
          Btn('Cancelar', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop()),
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
      if (mounted) mostrarAviso(context, e.message.toString());
    }
  }

  Future<void> _imprimirVenta(int ventaId) => mostrarDialogoImprimirTicket(context, db: widget.db, ventaId: ventaId);

  Future<void> _generarPdf() async {
    final config = await widget.db.select(widget.db.configuracionTabla).getSingle();
    var carpeta = config.rutaTicketsCarpeta;
    // Sin carpeta configurada, se pregunta en el momento (antes solo avisaba y había que ir a Configuración).
    if (carpeta == null) {
      carpeta = await getDirectoryPath();
      if (carpeta == null) return;
      await configurarCarpetaTickets(widget.db, carpeta);
      if (!mounted) return;
    }
    setState(() => _generandoPdf = true);
    try {
      final ruta = await guardarPdfPlanilla(widget.db, sesionId: widget.sesionId, carpetaDestino: carpeta);
      if (mounted) mostrarAviso(context, 'Guardado en $ruta');
    } catch (e) {
      if (mounted) mostrarAviso(context, 'Error: $e');
    }
    if (mounted) setState(() => _generandoPdf = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle;
    final s = d?.sesion;
    final dia = s == null ? 'Historial' : fechaLarga(s.fechaApertura);
    final diferencia = s?.diferenciaCentavos ?? 0;
    final abierta = s?.estado == 'ABIERTA';
    return PantallaGestion(
      db: widget.db,
      claveActiva: 'historial',
      usuarioId: widget.usuarioId,
      titulo: dia[0].toUpperCase() + dia.substring(1),
      subtitulo: d == null
          ? null
          : [
              '${d.validas.length} venta${d.validas.length == 1 ? '' : 's'}',
              if (d.nombreEmpleado.isNotEmpty) d.nombreEmpleado,
              abierta ? 'caja abierta' : (s!.fechaCierre == null ? 'caja cerrada' : 'caja cerrada a las ${horaCorta(s.fechaCierre!)}'),
            ].join(' · '),
      acciones: [
        if (s != null && !abierta)
          Etiqueta(
            diferencia == 0 ? 'Cuadró justo' : '${diferencia > 0 ? 'Sobraron' : 'Faltaron'} ${pesos(diferencia.abs())}',
            tono: diferencia == 0 ? TonoMock.g : (diferencia < 0 ? TonoMock.b : TonoMock.w),
            alto: 38,
            tamanioTexto: 15,
            padding: 18,
          ),
        Btn(_generandoPdf ? 'Generando…' : 'Generar PDF', variante: VarBtn.ton, icono: Ic.file, onTap: _generandoPdf ? null : _generarPdf),
        Btn('Volver a Cierres', variante: VarBtn.ton, icono: Ic.back, onTap: () => Navigator.of(context).maybePop()),
      ],
      child: d == null ? const SizedBox.shrink() : _contenido(context, d),
    );
  }

  Widget _contenido(BuildContext context, DetalleDelDia d) {
    final p = context.p;
    final validas = d.validas;
    final abierta = d.sesion.estado == 'ABIERTA';
    final visibles = _verAnuladas ? d.ventas : validas;
    final ancho = MediaQuery.sizeOf(context).width;

    Widget bloque(String titulo, int valor, {String? nota, TonoMock? tono}) => Tarjeta(
      tono: tono,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo, style: estilo(14, 600, color: tono == null ? p.mute : tono.colores(p).$2)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroQueCuenta(valor: valor, formato: pesos, estilo: estilo(36, 550, color: tono == null ? p.tinta : tono.colores(p).$2, em: -.04, num: true)),
          ),
          if (nota != null) ...[
            const SizedBox(height: 4),
            Text(nota, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(13.5, 400, color: p.mute)),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Aparecer.revelar(
                  child: BloqueHero(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vendido', style: estilo(14, 600, color: p.heroSub)),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: NumeroQueCuenta(valor: d.vendidoCentavos, formato: pesos, estilo: estilo(44, 550, color: p.sobreHero, em: -.04, num: true)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          validas.isEmpty
                              ? 'Sin ventas'
                              : '${validas.length} venta${validas.length == 1 ? '' : 's'} · promedio ${pesos(d.vendidoCentavos ~/ validas.length)}',
                          style: estilo(14, 400, color: p.heroSub),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Aparecer.revelar(orden: 1, child: bloque('Efectivo', d.efectivoCentavos, nota: _ventas(d.ventasEfectivo)))),
              const SizedBox(width: 14),
              Expanded(child: Aparecer.revelar(orden: 2, child: bloque('Mercado Pago', d.mpCentavos, nota: _ventas(d.ventasMp)))),
              const SizedBox(width: 14),
              Expanded(
                child: Aparecer.revelar(
                  orden: 3,
                  child: bloque(
                    'Ganancia',
                    d.gananciaCentavos,
                    tono: TonoMock.g,
                    nota: d.vendidoSinCostoCentavos > 0
                        ? 'Costo ${pesos(d.costoCentavos)} · sin costo ${pesos(d.vendidoSinCostoCentavos)}'
                        : 'Costo ${pesos(d.costoCentavos)}',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Tabla(
                  radio: 28,
                  encogerse: false,
                  columnas: const [
                    ColumnaTabla('#', ancho: 90),
                    ColumnaTabla('Hora', ancho: 90),
                    ColumnaTabla('Detalle', flex: 5),
                    ColumnaTabla('Medio', flex: 2),
                    ColumnaTabla('Total', flex: 2, derecha: true),
                    ColumnaTabla('', ancho: 270, derecha: true),
                  ],
                  cantidad: visibles.length,
                  vacio: const Vacio(texto: 'No hubo ventas este día', icono: null, padding: EdgeInsets.symmetric(vertical: 36)),
                  celdas: (context, i) {
                    final v = visibles[i];
                    final apagado = v.anulada ? p.mute : p.tinta;
                    final tachado = v.anulada ? TextDecoration.lineThrough : null;
                    final (medio, tono) = switch (v.medio) {
                      'Ef' => ('Efectivo', TonoMock.g),
                      'MP' => ('Mercado Pago', TonoMock.i),
                      _ => ('Mixto', TonoMock.w),
                    };
                    return [
                      celda(context, '${v.venta.id}', peso: 600, color: apagado),
                      celda(context, horaCorta(v.venta.fecha), color: p.mute, num: true),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              v.detalle.isEmpty ? 'Venta #${v.venta.id}' : v.detalle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: estilo(16, 400, color: apagado).copyWith(decoration: tachado),
                            ),
                          ),
                          if (v.anulada) ...[const SizedBox(width: 8), const Etiqueta('Anulada', tono: TonoMock.b)],
                          if (v.venta.editadaEn != null && !v.anulada) ...[const SizedBox(width: 8), const Etiqueta('Editada', tono: TonoMock.w)],
                        ],
                      ),
                      Etiqueta(medio, tono: tono),
                      Text(pesos(v.venta.totalCentavos), style: estilo(16, 600, color: apagado, num: true).copyWith(decoration: tachado)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BotonCirculo(icono: Ic.print, etiqueta: 'Reimprimir', diametro: 40, tamanioIcono: 17, fondo: p.papel, onTap: () => _imprimirVenta(v.venta.id)),
                          if (!v.anulada) ...[
                            const SizedBox(width: 6),
                            Btn('Editar', tam: TamBtn.xs, variante: VarBtn.ton, sobreGris: true, tooltip: 'Editar', onTap: () => _editarVenta(v.venta.id)),
                          ],
                          if (abierta && !v.anulada) ...[
                            const SizedBox(width: 6),
                            Btn('Anular', tam: TamBtn.xs, variante: VarBtn.red, tooltip: 'Anular', onTap: () => _anularVenta(v.venta)),
                          ],
                        ],
                      ),
                    ];
                  },
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: ancho >= 1700 ? 440 : 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Tarjeta(
                        padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Sec('Vendido por proveedor')),
                                Btn(
                                  _ocultarProveedores ? 'Ver' : 'Ocultar',
                                  tam: TamBtn.xs,
                                  variante: VarBtn.ton,
                                  sobreGris: true,
                                  onTap: () => setState(() => _ocultarProveedores = !_ocultarProveedores),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _ocultarProveedores
                                  ? Text('Oculto: se muestra con “Ver”.', style: estilo(15, 400, color: p.mute))
                                  : d.porProveedor.isEmpty
                                  ? Text('Sin ventas', style: estilo(15, 400, color: p.mute))
                                  : ListView.separated(
                                      itemCount: d.porProveedor.length,
                                      separatorBuilder: (_, _) => ColoredBox(color: p.pelo, child: const SizedBox(height: 1)),
                                      itemBuilder: (_, i) {
                                        final x = d.porProveedor[i];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          child: Row(
                                            children: [
                                              Expanded(child: Text(x.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(16, 400, color: p.tinta))),
                                              Text(pesos(x.vendidoCentavos), style: estilo(16, 600, color: p.tinta, num: true)),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (d.anuladas.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Tarjeta(
                        linea: true,
                        padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Sec('Anuladas'),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${d.anuladas.length} venta${d.anuladas.length == 1 ? '' : 's'} · ${pesos(d.anuladas.fold(0, (a, v) => a + v.venta.totalCentavos))} · no suman',
                                    style: estilo(15, 400, color: p.mute),
                                  ),
                                ],
                              ),
                            ),
                            Btn(_verAnuladas ? 'Ocultar' : 'Ver', tam: TamBtn.xs, variante: VarBtn.ton, onTap: () => setState(() => _verAnuladas = !_verAnuladas)),
                          ],
                        ),
                      ),
                    ],
                    if (_arqueos.isNotEmpty) ...[
                      const SizedBox(height: 14),
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
