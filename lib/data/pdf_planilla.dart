// PDF de "Control diario de caja" (fase 9), réplica de la planilla de papel
// vigente — dos grillas (efectivo / Mercado Pago), apertura y cierre, y
// salidas/pagos — más tres bloques que vuelven de una versión anterior del
// papel porque el dueño los pidió de nuevo explícitamente (ítem 3,
// `DECISIONES.md`): reposición por proveedor (con costo real, no el
// porcentaje viejo), arqueo propio de la caja de cigarrillos, y el
// encabezado con el empleado del turno y sus horarios en vez de firmas.
// Sirve tanto para un día cargado históricamente como para uno operado
// normalmente por la app (planilla_dia.dart no distingue).
//
// El bloque RETIRO (retiro semanal, Regla 13 vieja) se eliminó entero: el
// retiro de ganancias ahora es un movimiento tipo `RETIRO` más, y aparece
// solo en "SALIDAS/PAGOS" como cualquier otro egreso (Regla 13 nueva).

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/dinero.dart';
import 'database.dart';
import 'planilla_dia.dart';
import 'repositorio_reposicion.dart';

/// [fechaApertura] va con hora y minuto, no solo la fecha: dos turnos del
/// mismo día (Regla 18, "un turno ES una sesión") generan cada uno su propia
/// planilla, y solo la fecha calendario los confundía en un mismo archivo —
/// el segundo cierre del día pisaba en silencio el PDF del primer turno.
String nombreArchivoPlanilla(DateTime fechaApertura) {
  String dos(int n) => n.toString().padLeft(2, '0');
  final f = fechaApertura;
  return 'control_caja_${f.year}-${dos(f.month)}-${dos(f.day)}_${dos(f.hour)}${dos(f.minute)}.pdf';
}

String _fecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

String _hora(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.hour)}:${dos(f.minute)}';
}

pw.Widget _grilla(String titulo, List<RenglonPlanillaCalculado> renglones, int totalCentavos) {
  return pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: PdfColors.grey300,
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(titulo, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(3), 3: pw.FlexColumnWidth(1)},
          children: [
            pw.TableRow(children: [
              _celda('MONTO', negrita: true),
              _celda('HORA', negrita: true),
              _celda('DETALLE', negrita: true),
              _celda('PROV', negrita: true),
            ]),
            for (final r in renglones)
              pw.TableRow(children: [
                _celda(formatearARS(r.montoCentavos)),
                _celda(_hora(r.hora)),
                _celda(r.detalle),
                _celda(r.letraProveedor ?? ''),
              ]),
          ],
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('TOTAL: ${formatearARS(totalCentavos)}', style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );
}

pw.Widget _celda(String texto, {bool negrita = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(2),
    child: pw.Text(texto, style: pw.TextStyle(fontSize: 8, fontWeight: negrita ? pw.FontWeight.bold : null)),
  );
}

pw.Widget _linea(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(etiqueta, style: const pw.TextStyle(fontSize: 8)), pw.Text(valor, style: const pw.TextStyle(fontSize: 8))],
    ),
  );
}

/// Reposición por proveedor (ítem 3): costo real y separado del ciclo
/// vigente de `calcularReposicion`/`separarProveedor` — nunca el porcentaje
/// del papel viejo (`VENDI × 0,65`), el dueño fue textual sobre eso. Es una
/// foto del estado actual, no de lo vendido específicamente este día — el
/// ciclo de reposición no se reinicia a diario (ítem 2).
///
/// VENDIDO es precio (lo que entró), A SEPARAR es costo real — El dueño fue
/// explícito en que confundirlos es un error de la planilla, no un dato
/// que falte, así que van en columnas separadas y con su nombre real.
/// Solo se listan los proveedores con algo que mostrar (vendido o
/// separado): a diferencia de la pantalla de Reposición, que sí muestra
/// los 15 siempre, acá una fila en cero es media página de ruido.
pw.Widget _tablaReposicion(List<ResumenReposicionProveedor> resumenes, int vendidoSinCostoCentavos) {
  final conMovimiento = resumenes.where((r) => r.vendidoCentavos > 0 || r.separadoCentavos > 0).toList();
  final totalASeparar = resumenes.fold<int>(0, (acc, r) => acc + r.sugeridoASepararCentavos);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        color: PdfColors.grey300,
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text('REPOSICIÓN POR PROVEEDOR', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      ),
      if (conMovimiento.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text('Sin movimiento.', style: const pw.TextStyle(fontSize: 8)),
        )
      else
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.2),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.4),
            4: pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(children: [
              _celda('PROVEEDOR', negrita: true),
              _celda('VENDIDO', negrita: true),
              _celda('A SEPARAR', negrita: true),
              _celda('SEPARADO', negrita: true),
              _celda('MEDIO', negrita: true),
            ]),
            for (final r in conMovimiento)
              pw.TableRow(children: [
                _celda(r.proveedor.nombre),
                _celda(formatearARS(r.vendidoCentavos)),
                _celda(formatearARS(r.costoRealCentavos)),
                _celda(formatearARS(r.separadoCentavos)),
                _celda(r.proveedor.medioPago),
              ]),
          ],
        ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text('TOTAL A SEPARAR: ${formatearARS(totalASeparar)}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ),
      if (vendidoSinCostoCentavos > 0)
        pw.Text(
          'Vendido sin costo cargado (no genera reposición): ${formatearARS(vendidoSinCostoCentavos)}',
          style: const pw.TextStyle(fontSize: 7),
        ),
    ],
  );
}

Future<Uint8List> generarPdfPlanilla(AppDatabase db, int sesionId) async {
  final datos = await armarDatosPlanilla(db, sesionId);
  final sesion = datos.sesion;

  final proveedores = await (db.select(db.proveedores)..where((pr) => pr.activo.equals(true))).get();
  final reposicion = await reposicionActual(db);

  // Guion simple, no raya "—": la fuente por default del PDF (Helvetica) no
  // tiene el glifo Unicode y lo dibuja en blanco.
  final encabezadoEmpleado = StringBuffer('Empleado: ${datos.nombreEmpleado}')
    ..write(' - abrió ${_hora(sesion.fechaApertura)}');
  if (sesion.fechaCierre != null) encabezadoEmpleado.write(', cerró ${_hora(sesion.fechaCierre!)}');
  if (datos.nombreCerro != null) encabezadoEmpleado.write(' (${datos.nombreCerro})');

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('CONTROL DIARIO DE CAJA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Fecha: ${_fecha(sesion.fechaApertura)}   $encabezadoEmpleado', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _grilla('VENTAS EN EFECTIVO', datos.renglonesEfectivo, datos.totalEfectivoCentavos),
                pw.SizedBox(width: 10),
                _grilla('VENTAS POR MERCADO PAGO', datos.renglonesMp, datos.totalMpCentavos),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text('APERTURA Y CIERRE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      _linea('Caja inicial NORMAL', formatearARS(sesion.fondoInicialCentavos)),
                      _linea('Caja inicial CIGARRILLOS', formatearARS(sesion.lataInicialCentavos)),
                      _linea('CAJA ESPERADA', formatearARS(sesion.efectivoEsperadoCentavos ?? 0)),
                      _linea('Efectivo REAL contado', formatearARS(sesion.efectivoContadoCentavos ?? 0)),
                      _linea('DIFERENCIA (+/-)', formatearARS(sesion.diferenciaCentavos ?? 0)),
                      _linea('(-) A caja cigarrillos', formatearARS(sesion.lataSeparadoCentavos ?? 0)),
                      _linea('QUEDA EN EL CAJON', formatearARS(datos.quedaEnCajonCentavos)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text('CAJA CIGARRILLOS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      _linea('Separado desde la caja normal', formatearARS(sesion.lataSeparadoCentavos ?? 0)),
                      _linea('(-) Pagos a Distribuidora de Cigarrillos', formatearARS(datos.pagosALataCentavos)),
                      _linea('Esperada', formatearARS(sesion.lataFinalCentavos ?? 0)),
                      _linea('Real contado', formatearARS(sesion.lataContadoCentavos ?? 0)),
                      _linea('Diferencia (+/-)', formatearARS(sesion.lataDiferenciaCentavos ?? 0)),
                      if ((sesion.lataPendienteCentavos ?? 0) > 0) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Cig. cobrados por QR — queda en MP, se le debe a la caja normal: '
                          '${formatearARS(sesion.lataPendienteCentavos!)}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            // "SALIDAS / PAGOS" — ya incluye los retiros de ganancia (Regla
            // 13, tipo `RETIRO` en `tiposEgresoDeCaja`) igual que cualquier
            // otro egreso: no hace falta un bloque aparte, cada uno se lista
            // con su propia nota ("Retiro de ganancia — <Proveedor>"). El
            // bloque de RETIRO que vivía acá (retiro semanal, Regla 13
            // vieja) se eliminó entero.
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('SALIDAS / PAGOS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                for (final g in datos.gastos)
                  _linea('${g.motivo}${g.deLata ? ' (lata)' : ''}', formatearARS(g.montoCentavos)),
              ],
            ),
            pw.SizedBox(height: 12),
            _tablaReposicion(reposicion, datos.vendidoSinCostoCentavos),
            pw.SizedBox(height: 10),
            pw.Text(
              '${[for (final pr in proveedores) '${pr.codigo} ${pr.nombre}'].join('  ')}. '
              'Cigarrillos: sin letra. Pago mixto: un renglón en cada grilla.',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

/// Genera el PDF y lo guarda en [carpetaDestino] — el llamador es
/// responsable de asegurarse de que haya una carpeta configurada antes de
/// llamar a esto (misma carpeta de tickets de la fase 10; no hace falta una
/// segunda carpeta solo para esta planilla).
Future<String> guardarPdfPlanilla(AppDatabase db, {required int sesionId, required String carpetaDestino}) async {
  final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
  final bytes = await generarPdfPlanilla(db, sesionId);

  await Directory(carpetaDestino).create(recursive: true);
  final ruta = p.join(carpetaDestino, nombreArchivoPlanilla(sesion.fechaApertura));
  await File(ruta).writeAsBytes(bytes);
  return ruta;
}
