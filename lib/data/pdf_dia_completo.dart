// Exportación del día completo (El dueño, 2026-10-03: "que en móvil pueda
// exportar un día, con su historial"): un solo PDF con todo lo que pasó en una
// sesión de caja — arqueo de las tres cajas, cada venta con sus líneas y
// pagos (las anuladas marcadas, nunca omitidas: Regla 6), cada movimiento de
// caja (gastos, pagos a proveedores, retiros, ingresos) y los arqueos
// intermedios. Distinto de la planilla "Control diario de caja"
// (`pdf_planilla.dart`), que es la réplica del papel: esta es el registro
// completo para revisar un día número por número, con la misma base que lee
// el resto de la app (Regla 3: no recalcula nada, solo vuelca lo guardado).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/dinero.dart';
import 'database.dart';

String nombreArchivoDiaCompleto(DateTime fechaApertura) {
  String dos(int n) => n.toString().padLeft(2, '0');
  final f = fechaApertura;
  return 'dia_completo_${f.year}-${dos(f.month)}-${dos(f.day)}_${dos(f.hour)}${dos(f.minute)}.pdf';
}

String _dos(int n) => n.toString().padLeft(2, '0');
String _fecha(DateTime f) => '${_dos(f.day)}/${_dos(f.month)}/${f.year}';
String _hora(DateTime f) => '${_dos(f.hour)}:${_dos(f.minute)}';
String _plata(int? c) => c == null ? '-' : formatearARS(c);

String _cantidadDe(FilaLineaVenta l) {
  if (l.esPesable && l.gramos != null) return '${l.gramos} g';
  return '${l.cantidad ?? 1}';
}

pw.Widget _titulo(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
  child: pw.Text(texto, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
);

pw.Widget _tabla(List<String> encabezado, List<List<String>> filas, {Map<int, pw.TableColumnWidth>? anchos}) {
  return pw.TableHelper.fromTextArray(
    headers: encabezado,
    data: filas,
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    cellAlignment: pw.Alignment.centerLeft,
    columnWidths: anchos,
    border: pw.TableBorder.all(width: 0.4),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  );
}

/// Arma el PDF del día [sesionId] (cerrado o todavía abierto).
Future<Uint8List> generarPdfDiaCompleto(AppDatabase db, int sesionId) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final usuarios = {for (final u in await db.select(db.usuarios).get()) u.id: u.nombre};
  final medios = {for (final m in await db.select(db.mediosDePago).get()) m.id: m};
  final cajas = {for (final c in await db.select(db.cajas).get()) c.id: c};
  final proveedores = {for (final pr in await db.select(db.proveedores).get()) pr.id: pr.nombre};

  final ventas = await (db.select(db.ventas)
        ..where((v) => v.sesionCajaId.equals(sesionId))
        ..orderBy([(v) => OrderingTerm.asc(v.fecha)]))
      .get();
  final ids = ventas.map((v) => v.id).toList();
  final lineas = ids.isEmpty ? <FilaLineaVenta>[] : await (db.select(db.lineasDeVenta)..where((l) => l.ventaId.isIn(ids))).get();
  final pagos = ids.isEmpty ? <Pago>[] : await (db.select(db.pagos)..where((x) => x.ventaId.isIn(ids))).get();
  final movimientos = await (db.select(db.movimientosDeCaja)
        ..where((m) => m.sesionCajaId.equals(sesionId))
        ..orderBy([(m) => OrderingTerm.asc(m.fecha), (m) => OrderingTerm.asc(m.id)]))
      .get();
  final arqueos = await (db.select(db.arqueosIntermedios)
        ..where((a) => a.sesionCajaId.equals(sesionId))
        ..orderBy([(a) => OrderingTerm.asc(a.fecha)]))
      .get();

  final vigentes = ventas.where((v) => v.anuladaEn == null).toList();
  final anuladas = ventas.length - vigentes.length;
  final totalVendido = vigentes.fold<int>(0, (a, v) => a + v.totalCentavos);
  final idsVigentes = {for (final v in vigentes) v.id};
  var cobradoEfectivo = 0;
  var cobradoVirtual = 0;
  for (final pg in pagos) {
    if (!idsVigentes.contains(pg.ventaId)) continue;
    if (medios[pg.medioPagoId]?.esEfectivo ?? false) {
      cobradoEfectivo += pg.montoCentavos;
    } else {
      cobradoVirtual += pg.montoCentavos;
    }
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7)),
      ),
      build: (ctx) {
        final apertura = sesion.fechaApertura;
        return [
          pw.Text('Día completo - ${_fecha(apertura)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Abrió ${usuarios[sesion.usuarioAbrioId] ?? '-'} a las ${_hora(apertura)}'
            '${sesion.fechaCierre == null ? ' - la caja sigue ABIERTA' : ' - cerró ${usuarios[sesion.usuarioCerroId] ?? '-'} a las ${_hora(sesion.fechaCierre!)}'}'
            ' (estado: ${sesion.estado})',
            style: const pw.TextStyle(fontSize: 9),
          ),
          _titulo('Resumen'),
          _tabla(
            ['Concepto', 'Monto'],
            [
              ['Vendido (sin anuladas)', _plata(totalVendido)],
              ['Ventas válidas / anuladas', '${vigentes.length} / $anuladas'],
              ['Cobrado en efectivo', _plata(cobradoEfectivo)],
              ['Cobrado por medios virtuales', _plata(cobradoVirtual)],
              ['Fondo inicial (caja normal)', _plata(sesion.fondoInicialCentavos)],
              ['Lata inicial', _plata(sesion.lataInicialCentavos)],
              ['Mercado Pago inicial', _plata(sesion.saldoMpInicialCentavos)],
            ],
            anchos: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1.5)},
          ),
          _titulo('Arqueo del cierre'),
          if (sesion.estado != 'CERRADA')
            pw.Text('Todavía no se cerró la caja.', style: const pw.TextStyle(fontSize: 9))
          else
            _tabla(
              ['Caja', 'Contado', 'Esperado', 'Diferencia'],
              [
                ['Efectivo', _plata(sesion.efectivoContadoCentavos), _plata(sesion.efectivoEsperadoCentavos), _plata(sesion.diferenciaCentavos)],
                ['Mercado Pago', _plata(sesion.mpContadoCentavos), _plata(sesion.mpEsperadoCentavos), _plata(sesion.mpDiferenciaCentavos)],
                ['Lata', _plata(sesion.lataContadoCentavos), _plata(sesion.lataFinalCentavos), _plata(sesion.lataDiferenciaCentavos)],
              ],
            ),
          if (sesion.nota != null && sesion.nota!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Nota del cierre: ${sesion.nota}', style: const pw.TextStyle(fontSize: 9)),
          ],
          if (arqueos.isNotEmpty) ...[
            _titulo('Arqueos intermedios'),
            _tabla(
              ['Hora', 'Quién', 'Efectivo contado (dif.)', 'MP contado (dif.)', 'Lata contada (dif.)'],
              [
                for (final a in arqueos)
                  [
                    _hora(a.fecha),
                    usuarios[a.usuarioId] ?? '-',
                    '${_plata(a.efectivoContadoCentavos)} (${_plata(a.diferenciaCentavos)})',
                    '${_plata(a.mpContadoCentavos)} (${_plata(a.mpDiferenciaCentavos)})',
                    '${_plata(a.lataContadoCentavos)} (${_plata(a.lataDiferenciaCentavos)})',
                  ],
              ],
            ),
          ],
          _titulo('Movimientos de caja (${movimientos.length})'),
          if (movimientos.isEmpty)
            pw.Text('Sin movimientos.', style: const pw.TextStyle(fontSize: 9))
          else
            _tabla(
              ['Hora', 'Tipo', 'Caja / medio', 'Monto', 'Detalle'],
              [
                for (final m in movimientos)
                  [
                    _hora(m.fecha),
                    m.tipo,
                    (m.medioPagoId != null && !(medios[m.medioPagoId]?.esEfectivo ?? true))
                        ? 'Mercado Pago'
                        : (cajas[m.cajaId]?.esLata ?? false)
                            ? 'Lata'
                            : 'Cajón',
                    _plata(m.montoCentavos),
                    [
                      if (m.ventaId != null) 'venta #${m.ventaId}',
                      if (m.proveedorId != null) proveedores[m.proveedorId] ?? 'proveedor',
                      if (m.nota != null && m.nota!.isNotEmpty) m.nota!,
                      usuarios[m.usuarioId] ?? '',
                    ].where((t) => t.isNotEmpty).join(' - '),
                  ],
              ],
              anchos: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(1.3),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(3.5),
              },
            ),
          _titulo('Ventas (${ventas.length})'),
          if (ventas.isEmpty) pw.Text('Sin ventas.', style: const pw.TextStyle(fontSize: 9)),
          for (final v in ventas) ..._bloqueVenta(v, lineas, pagos, medios, usuarios),
        ];
      },
    ),
  );
  return doc.save();
}

List<pw.Widget> _bloqueVenta(
  FilaVenta v,
  List<FilaLineaVenta> lineas,
  List<Pago> pagos,
  Map<int, MedioDePago> medios,
  Map<int, String> usuarios,
) {
  final deLaVenta = lineas.where((l) => l.ventaId == v.id).toList();
  final pagosVenta = pagos.where((x) => x.ventaId == v.id).toList();
  final anulada = v.anuladaEn != null;
  final extras = [
    if (v.descuentoCentavos != 0) 'descuento ${_plata(v.descuentoCentavos)}',
    if (v.recargoCigarrillosCentavos != 0) 'recargo ${_plata(v.recargoCigarrillosCentavos)}',
    if (v.redondeoCentavos != 0) 'redondeo ${_plata(v.redondeoCentavos)}',
    if (v.esFiado) 'FIADO',
    if (v.editadaEn != null) 'editada',
  ];
  return [
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: anulada ? PdfColors.red100 : PdfColors.grey200,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '#${v.id}  ${_hora(v.fecha)}  ${usuarios[v.usuarioId] ?? ''}'
            '${anulada ? '  - ANULADA${v.motivoAnulacion == null ? '' : ' (${v.motivoAnulacion})'}' : ''}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(_plata(v.totalCentavos), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ),
    _tabla(
      ['Producto', 'Cant.', 'Precio unit.'],
      [for (final l in deLaVenta) [l.nombreProductoFoto, _cantidadDe(l), _plata(l.precioUnitarioCentavos)]],
      anchos: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.5)},
    ),
    pw.Text(
      'Pagos: ${pagosVenta.map((x) => '${medios[x.medioPagoId]?.nombre ?? 'medio'}${x.canal == null ? '' : ' (${x.canal})'} ${_plata(x.montoCentavos)}').join(' + ')}'
      '${extras.isEmpty ? '' : '  |  ${extras.join(', ')}'}',
      style: const pw.TextStyle(fontSize: 8),
    ),
  ];
}

/// Genera el PDF y lo guarda en [carpetaDestino]; devuelve la ruta.
Future<String> guardarPdfDiaCompleto(AppDatabase db, {required int sesionId, required String carpetaDestino}) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final bytes = await generarPdfDiaCompleto(db, sesionId);
  await Directory(carpetaDestino).create(recursive: true);
  final ruta = p.join(carpetaDestino, nombreArchivoDiaCompleto(sesion.fechaApertura));
  await File(ruta).writeAsBytes(bytes);
  return ruta;
}
