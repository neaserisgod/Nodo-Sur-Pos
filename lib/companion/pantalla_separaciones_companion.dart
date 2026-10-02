// Separaciones en el celular ("Lenguaje de diseño", el dueño 2026-09-26, mock
// `MovilSeparaciones.dc.html`): el mismo cálculo que la pantalla de la PC —
// reusa `SeparacionesControlador` tal cual (Regla 3) contra la base local,
// que se sincroniza sola con la PC por Supabase. Tildar un proveedor acá es
// lo mismo que tildarlo allá.
//
// Distribución del mock: período arriba; una tarjeta oscura con cuánto
// separar (de efectivo y de MP) y lo que queda; "Qué separar" (avance y una
// tarjeta por proveedor con su tilde) y "Lo vendido" (vendido, costo y
// ganancia por proveedor).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../data/repositorio_reposicion.dart' show SeparacionDelDia;
import '../data/repositorio_ventas.dart' show sesionAbierta;
import '../domain/dinero.dart';
import '../domain/periodo.dart';
import '../ui/comun/tarjetas.dart';
import '../ui/separaciones/separaciones_controlador.dart';
import '../ui/tema/acentos.dart';
import '../ui/tema/tokens.dart';
import '../ui/tema/iconos.dart';
import 'cambios_companion.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';

class PantallaSeparacionesCompanion extends StatefulWidget {
  const PantallaSeparacionesCompanion({super.key, required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<PantallaSeparacionesCompanion> createState() => _PantallaSeparacionesCompanionState();
}

class _PantallaSeparacionesCompanionState extends State<PantallaSeparacionesCompanion> {
  SeparacionesControlador? _c;
  StreamSubscription<void>? _avisos;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final sesion = await sesionAbierta(widget.db);
    final c = SeparacionesControlador(widget.db, usuarioId: widget.usuarioId, sesionCajaId: sesion?.id);
    await c.cargarTodo();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => _c = c);
    // Una venta o una separación hecha en la PC aparece sola.
    _avisos = avisosCambiosCompanion.listen((_) => _c?.cargarTodo());
  }

  @override
  void dispose() {
    _avisos?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Separaciones')),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ChangeNotifierProvider<SeparacionesControlador>.value(
              value: c,
              child: Consumer<SeparacionesControlador>(
                builder: (context, c, _) => RefreshIndicator(
                  onRefresh: c.cargarTodo,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.sm, Espaciado.lg, Espaciado.xxl),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GrupoPildoras<PeriodoResumen>(
                          opciones: const [
                            (PeriodoResumen.hoy, 'Hoy'),
                            (PeriodoResumen.semana, 'Semana'),
                            (PeriodoResumen.mes, 'Mes'),
                          ],
                          elegida: c.periodo,
                          onElegir: c.cambiarPeriodo,
                        ),
                      ),
                      const SizedBox(height: Espaciado.md),
                      const _Resumen(),
                      const SizedBox(height: Espaciado.lg),
                      GrupoPildoras<VistaSeparaciones>(
                        opciones: const [
                          (VistaSeparaciones.queSeparar, 'Qué separar'),
                          (VistaSeparaciones.loVendido, 'Lo vendido'),
                        ],
                        elegida: c.vista,
                        oscura: true,
                        onElegir: c.cambiarVista,
                      ),
                      const SizedBox(height: Espaciado.md),
                      if (c.vista == VistaSeparaciones.queSeparar) ...[
                        if (c.tarjetas.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Espaciado.xl),
                            child: Text('Hoy no hay nada para separar', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                          )
                        else ...[
                          const _Avance(),
                          for (final t in c.tarjetas) ...[const SizedBox(height: Espaciado.md), _TarjetaProveedor(tarjeta: t)],
                        ],
                      ] else
                        for (final f in c.vendidos) ...[_TarjetaVendido(fila: f), const SizedBox(height: Espaciado.md)],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

String _plata(int c) => formatearARS(c);

class _Resumen extends StatelessWidget {
  const _Resumen();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final acentos = context.acentosPlazoleta;
    final texto = acentos.textoSobreColor;
    final textTheme = Theme.of(context).textTheme;
    final separar = c.separarEfectivoCentavos + c.separarMpCentavos;
    final cobrado = c.cobrado.efectivoCentavos + c.cobrado.mpCentavos;
    final queda = c.quedaEfectivoCentavos + c.quedaMpCentavos;

    Widget fila(Color punto, String etiqueta, int monto) => Padding(
          padding: const EdgeInsets.only(top: Espaciado.sm),
          child: Row(
            children: [
              PuntoColor(color: punto),
              const SizedBox(width: Espaciado.sm),
              Expanded(child: Text(etiqueta, style: textTheme.bodyMedium?.copyWith(color: texto))),
              Text(_plata(monto), style: textTheme.titleMedium?.copyWith(color: texto, fontWeight: Pesos.fuerte).tabular),
            ],
          ),
        );

    return BloqueHero(
      animar: false,
      padding: const EdgeInsets.all(Espaciado.xl - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Separar para proveedores · hoy', style: textTheme.bodyMedium?.copyWith(color: texto.withValues(alpha: 0.75), fontWeight: Pesos.medium)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_plata(separar), style: textTheme.displayLarge?.copyWith(color: texto).tabular),
          ),
          fila(const Color(0xFFF6A55A), 'De efectivo', c.separarEfectivoCentavos),
          fila(const Color(0xFF7CACF8), 'De Mercado Pago', c.separarMpCentavos),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Expanded(child: Text('Cobrado ${_plata(cobrado)}', style: textTheme.bodySmall?.copyWith(color: texto.withValues(alpha: 0.75)))),
              Text('Te queda ${_plata(queda)}', style: textTheme.bodySmall?.copyWith(color: const Color(0xFF6DD58C), fontWeight: Pesos.fuerte)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avance extends StatelessWidget {
  const _Avance();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final total = c.tarjetas.length;
    final hechas = c.cantidadSeparadas;
    return Superficie(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('$hechas de $total separados', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte))),
              if (c.hayParaDesmarcar) TextButton(onPressed: c.desmarcarTodo, child: const Text('Desmarcar')),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : hechas / total,
              minHeight: 10,
              backgroundColor: context.colores.fondo,
              valueColor: AlwaysStoppedAnimation(acentos.ganancia),
            ),
          ),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Text('Falta', style: textTheme.bodySmall),
              const Spacer(),
              PuntoColor(color: acentos.dinero, tamanio: 8),
              const SizedBox(width: Espaciado.xs),
              Text(_plata(c.faltaEfectivoCentavos), style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
              const SizedBox(width: Espaciado.lg),
              PuntoColor(color: acentos.qr, tamanio: 8),
              const SizedBox(width: Espaciado.xs),
              Text(_plata(c.faltaMpCentavos), style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaProveedor extends StatelessWidget {
  const _TarjetaProveedor({required this.tarjeta});

  final TarjetaSeparacion tarjeta;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SeparacionesControlador>();
    final procesando = context.select<SeparacionesControlador, bool>((c) => c.procesando.contains(tarjeta.proveedorId));
    final t = tarjeta;
    final acentos = context.acentosPlazoleta;
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: t.separada ? 0.55 : 1,
      child: Superficie(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.fila.nombre, style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
                      Text(
                        _plata(t.totalCentavos),
                        style: textTheme.headlineMedium?.copyWith(color: t.separada ? colores.textoSecundario : null).tabular,
                      ),
                    ],
                  ),
                ),
                // Tilde grande (44 px): separar / destildar, como en la PC.
                Presionable(
                  radio: 12,
                  etiqueta: t.separada ? 'Destildar ${t.fila.nombre}' : 'Marcar ${t.fila.nombre} como separado',
                  onTap: procesando || t.bloqueada ? null : () => c.alternar(t),
                  color: t.separada ? acentos.ganancia : Colors.transparent,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: t.separada ? null : Border.all(color: colores.textoTenue, width: 2),
                    ),
                    child: t.separada ? Icon(IconosPlazoleta.check, color: acentos.textoSobreColor) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espaciado.md),
            Row(
              children: [
                Expanded(child: FilaMedio(color: acentos.dinero, etiqueta: 'Efectivo', monto: _plata(t.efectivoCentavos))),
                const SizedBox(width: Espaciado.sm),
                Expanded(child: FilaMedio(color: acentos.qr, etiqueta: 'MP', monto: _plata(t.mpCentavos))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaVendido extends StatelessWidget {
  const _TarjetaVendido({required this.fila});

  final SeparacionDelDia fila;

  @override
  Widget build(BuildContext context) {
    final f = fila;
    final textTheme = Theme.of(context).textTheme;
    final vendido = f.vendidoCentavos;
    final costo = f.costoCentavos;
    final ganancia = f.gananciaCentavos;
    final conCosto = vendido - f.vendidoSinCostoCentavos;
    return Superficie(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(f.nombre, style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte))),
              if (conCosto > 0) Insignia(texto: '${(ganancia * 100 / conCosto).round()}%', tono: Tono.ganancia),
            ],
          ),
          const SizedBox(height: Espaciado.xs),
          Text('Vendido', style: textTheme.bodySmall),
          Text(_plata(vendido), style: textTheme.headlineMedium?.tabular),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Expanded(child: CajaCifra(etiqueta: 'Costo', valor: _plata(costo))),
              const SizedBox(width: Espaciado.sm),
              Expanded(child: CajaCifra(etiqueta: 'Ganancia', valor: _plata(ganancia), tono: Tono.ganancia)),
            ],
          ),
        ],
      ),
    );
  }
}
