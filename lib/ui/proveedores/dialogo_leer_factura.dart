// "Leer una factura (prueba)" (El dueño, 2026-10-05): elegís fotos o PDF de facturas de compra, la IA las transcribe y ves el costo real
// de cada producto y si la factura cierra con su total. TODAVÍA NO GUARDA NADA: sirve para probar la lectura con la clave y las facturas
// reales, y "Copiar lectura" deja el JSON de la IA en el portapapeles para ver qué leyó. Plan en `docs/PLAN-FACTURAS.md`.

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../domain/dinero.dart';
import '../../domain/factura_compra.dart';
import '../../domain/lectura_factura.dart';
import '../../servicios/gemini.dart';
import '../../servicios/lector_facturas.dart';
import '../../servicios/preparar_imagen.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';

/// [clienteIa] y [adjuntosIniciales] son solo para tests: el selector de archivos es nativo y no se puede manejar desde un test.
Future<void> mostrarDialogoLeerFactura(BuildContext context, {http.Client? clienteIa, List<AdjuntoGemini> adjuntosIniciales = const []}) {
  return mostrarModal<void>(context, builder: (_) => _DialogoLeerFactura(clienteIa: clienteIa, adjuntosIniciales: adjuntosIniciales));
}

class _DialogoLeerFactura extends StatefulWidget {
  const _DialogoLeerFactura({this.clienteIa, this.adjuntosIniciales = const []});

  final http.Client? clienteIa;
  final List<AdjuntoGemini> adjuntosIniciales;

  @override
  State<_DialogoLeerFactura> createState() => _DialogoLeerFacturaState();
}

class _DialogoLeerFacturaState extends State<_DialogoLeerFactura> {
  late final List<AdjuntoGemini> _adjuntos = [...widget.adjuntosIniciales];
  late final List<String> _nombres = [for (var i = 0; i < widget.adjuntosIniciales.length; i++) 'archivo ${i + 1}'];
  bool _leyendo = false;
  String? _error;
  ResultadoDeLectura? _resultado;
  List<FacturaNormalizada> _facturas = const [];

  Future<void> _elegir() async {
    final archivos = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Fotos y PDF', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf']),
      ],
    );
    if (archivos.isEmpty) return;
    setState(() {
      _error = null;
      _leyendo = true;
    });
    final nuevos = <AdjuntoGemini>[];
    final nombres = <String>[];
    for (final f in archivos) {
      final adjunto = await prepararArchivoDeFactura(f.name, await f.readAsBytes());
      if (adjunto == null) {
        _error = 'No pude abrir "${f.name}": tiene que ser una foto o un PDF.';
        continue;
      }
      nuevos.add(adjunto);
      nombres.add('${f.name} (${(adjunto.bytes.length / 1024).round()} KB)');
    }
    if (!mounted) return;
    setState(() {
      _adjuntos
        ..clear()
        ..addAll(nuevos);
      _nombres
        ..clear()
        ..addAll(nombres);
      _resultado = null;
      _facturas = const [];
      _leyendo = false;
    });
  }

  Future<void> _leer() async {
    setState(() {
      _leyendo = true;
      _error = null;
      _resultado = null;
    });
    try {
      final r = await leerFacturasConGemini(_adjuntos, client: widget.clienteIa);
      if (!mounted) return;
      setState(() {
        _resultado = r;
        _facturas = [for (final f in r.lectura.facturas) normalizarFactura(f)];
      });
    } on ErrorGemini catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _copiar() async {
    final r = _resultado;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(r.json)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lectura copiada al portapapeles')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    return Modal(
      titulo: 'Leer una factura (prueba)',
      subtitulo: 'Elegí fotos o PDF. La IA las transcribe y ves el costo de cada producto. Todavía no guarda nada.',
      ancho: 900,
      contenido: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!ClaveGemini.configurada)
                Text('Falta la clave de la IA: cargala en Configuración › Asistente IA.', style: textTheme.bodyMedium?.copyWith(color: colores.error)),
              if (_nombres.isEmpty && ClaveGemini.configurada)
                Text('Todavía no elegiste nada.', style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
              for (final n in _nombres) Text(n, style: textTheme.bodySmall),
              if (_leyendo)
                const Padding(padding: EdgeInsets.only(top: Espaciado.md), child: LinearProgressIndicator()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.md),
                  child: Text(_error!, style: textTheme.bodyMedium?.copyWith(color: colores.error)),
                ),
              if (_resultado != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.md),
                  child: Text('Leído con ${_resultado!.modelo}', style: textTheme.bodySmall?.copyWith(color: colores.textoTenue)),
                ),
                for (final a in _resultado!.lectura.advertencias) Text(a, style: textTheme.bodySmall),
                // El Modal admite 3 botones como máximo: esta acción va acá y no abajo.
                Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _copiar, child: const Text('Copiar lectura'))),
                for (final f in _facturas) _TarjetaFactura(f),
              ],
            ],
          ),
        ),
      ),
      botones: [
        BotonSecundario(texto: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        BotonSecundario(texto: 'Elegir archivos', onPressed: _leyendo ? null : _elegir),
        BotonPrimario(
          texto: _leyendo ? 'Leyendo…' : 'Leer con IA',
          onPressed: _leyendo || _adjuntos.isEmpty || !ClaveGemini.configurada ? null : _leer,
        ),
      ],
    );
  }
}

String _nombreDelModo(ModoImportes m) => switch (m) {
  ModoImportes.neto => 'importes sin IVA',
  ModoImportes.conIva => 'importes con el IVA adentro',
  ModoImportes.conIvaEInternos => 'importes con IVA e impuestos internos adentro',
};

class _TarjetaFactura extends StatelessWidget {
  const _TarjetaFactura(this.n);

  final FacturaNormalizada n;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final f = n.leida;
    List<CostoDeLinea>? costos;
    try {
      costos = costosDeFactura(n.factura);
    } on ArgumentError {
      costos = null; // por ejemplo, un descuento mayor que la factura: está mal leído
    }
    final control = n.control;
    final cabecera = [
      if (f.proveedorNombre != null) f.proveedorNombre!,
      if (f.tipo != null) 'Factura ${f.tipo}',
      if (f.numero != null) f.numero!,
      if (f.fecha != null) '${f.fecha!.day}/${f.fecha!.month}/${f.fecha!.year}',
      if (f.condicionPago != null) f.condicionPago == 'contado' ? 'contado' : 'cuenta corriente',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.lg),
      child: Container(
        padding: const EdgeInsets.all(Espaciado.md),
        decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(Bento.radio)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cabecera.isEmpty ? 'Factura' : cabecera, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte)),
            const SizedBox(height: Espaciado.xs),
            Wrap(
              spacing: Espaciado.sm,
              runSpacing: Espaciado.xs,
              children: [
                if (control == null)
                  const Insignia(texto: 'Sin total impreso: no se puede controlar', tono: Tono.alerta)
                else if (n.cierra)
                  const Insignia(texto: 'Cierra con el total impreso', tono: Tono.ganancia)
                else
                  Insignia(
                    texto: 'No cierra: diferencia de ${formatearARS(control.diferenciaCentavos.abs())} — revisá',
                    tono: Tono.error,
                  ),
                Insignia(texto: _nombreDelModo(n.modo)),
              ],
            ),
            for (final a in f.advertencias) Padding(padding: const EdgeInsets.only(top: Espaciado.xs), child: Text(a, style: textTheme.bodySmall)),
            const SizedBox(height: Espaciado.sm),
            if (costos == null)
              Text('No se pudieron calcular los costos: revisá los importes de la factura.', style: textTheme.bodySmall?.copyWith(color: colores.error))
            else
              for (var i = 0; i < costos.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${n.lineasSospechosas.contains(i) ? '⚠ ' : ''}${n.lineas[i].descripcion}',
                          style: textTheme.bodySmall?.copyWith(color: n.lineasSospechosas.contains(i) ? colores.error : null),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 56, child: Text('× ${n.factura.lineas[i].unidades}', textAlign: TextAlign.right, style: textTheme.bodySmall)),
                      SizedBox(
                        width: 110,
                        child: Text(formatearARS(costos[i].totalCentavos), textAlign: TextAlign.right, style: textTheme.bodySmall),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${formatearARS(costos[i].costoUnitarioCentavos)} c/u',
                          textAlign: TextAlign.right,
                          style: textTheme.bodySmall?.copyWith(fontWeight: Pesos.fuerte),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: Espaciado.sm),
            Text(
              [
                if (f.pie.descuentoGlobalCentavos > 0) 'Descuento ${formatearARS(f.pie.descuentoGlobalCentavos)}',
                if (f.pie.percepcionesCentavos > 0) 'Percepciones ${formatearARS(f.pie.percepcionesCentavos)}',
                if (f.pie.internosCentavos > 0) 'Impuestos internos ${formatearARS(f.pie.internosCentavos)}',
                if (control != null) 'Total calculado ${formatearARS(control.totalCalculadoCentavos)}',
                if (f.pie.totalCentavos != null) 'impreso ${formatearARS(f.pie.totalCentavos!)}',
              ].join(' · '),
              style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
            ),
            Text(
              'El costo por unidad incluye IVA e impuestos y lo repartido del pie. Si la factura cuenta por bultos, la cantidad todavía no se convierte en unidades.',
              style: textTheme.bodySmall?.copyWith(color: colores.textoTenue),
            ),
          ],
        ),
      ),
    );
  }
}
