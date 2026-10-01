// Equilibrio — desde 2026-09-26 es la mitad "del mes" de Inicio, no un
// apartado propio del menú (El dueño: "que apartados podemos resumir,
// agrupar" — el Dashboard ya repetía una versión chica de esto). Este
// widget es solo el contenido; lo monta `pantalla_dashboard.dart`. El punto
// de equilibrio va primero: es lo que se mira; la carga de fijos, después.
//
// Rentabilidad y equilibrio (fase 7). Una columna de tarjetas, con la carga
// mínima de fijos metida acá mismo (fase 8 — Configuración — todavía no
// existe): cada tarjeta que depende de los fijos del mes muestra un aviso en
// vez de un número si falta cargar algún concepto (Regla 12).
//
// Pantalla de muestra del sistema de diseño (fase 11): pantalla de gestión,
// prioriza aire y jerarquía por sobre densidad — lo opuesto a la pantalla de
// venta.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';
import 'dialogo_cargar_monto_fijo.dart';
import 'dialogo_nuevo_concepto_fijo.dart';
import 'dialogo_registrar_pago_fijo.dart';
import 'equilibrio_controlador.dart';
import '../tema/iconos.dart';

class ContenidoEquilibrio extends StatefulWidget {
  const ContenidoEquilibrio({super.key, required this.db, required this.usuarioId, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<ContenidoEquilibrio> createState() => _ContenidoEquilibrioState();
}

class _ContenidoEquilibrioState extends State<ContenidoEquilibrio> {
  late final EquilibrioControlador _c;

  @override
  void initState() {
    super.initState();
    _c = EquilibrioControlador(widget.db, usuarioId: widget.usuarioId, sesionCajaId: widget.sesionCajaId);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EquilibrioControlador>.value(
      value: _c,
      child: Consumer<EquilibrioControlador>(
        builder: (context, c, _) {
          // "Lenguaje de diseño" (2026-09-26): la misma distribución que la
          // vista Hoy de Inicio — fila de indicadores arriba, tarjetas de
          // detalle abajo — en vez de la columna de tarjetas de texto.
          if (c.cargando) return const SizedBox.shrink();
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilaIndicadoresMes(),
              SizedBox(height: Espaciado.lg),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _TarjetaFijosDelMes()),
                    SizedBox(width: Espaciado.lg),
                    Expanded(child: _TarjetaFijosPendientes()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaIndicadoresMes extends StatelessWidget {
  const _FilaIndicadoresMes();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EquilibrioControlador>();
    final ganancia = c.ganancia!;
    final margen = ganancia.margenPonderado;
    final equilibrio = c.equilibrio;
    final faltan = c.fijos!.faltantes;
    final sinFijos = faltan.isEmpty ? null : 'Falta cargar: ${faltan.join(', ')}';

    final tarjetas = [
      TarjetaIndicador(
        etiqueta: 'Ganancia bruta del mes',
        valor: formatearARS(ganancia.gananciaBrutaCentavos),
        tonoValor: Tono.ganancia,
        nota: [
          if (margen != null) 'Ganancia ${(margen * 100).round()}%',
          if (ganancia.vendidoSinCostoCentavos > 0) 'sin costo ${formatearARS(ganancia.vendidoSinCostoCentavos)}',
        ].join(' · '),
      ),
      TarjetaIndicador(
        etiqueta: equilibrio == null || !equilibrio.cubierto ? 'Falta para cubrir los fijos' : 'Fijos cubiertos',
        valor: equilibrio == null
            ? 'Sin fijos'
            : formatearARS(equilibrio.cubierto ? equilibrio.gananciaNetaCentavos : equilibrio.faltanteCentavos),
        tonoValor: equilibrio != null && equilibrio.cubierto ? Tono.ganancia : null,
        nota: equilibrio == null ? sinFijos : 'Avance del mes ${equilibrio.pctAvance}%',
        tonoNota: equilibrio == null ? Tono.alerta : Tono.neutro,
      ),
      TarjetaIndicador(
        etiqueta: 'Venta diaria de equilibrio',
        valor: c.ventaDiariaEquilibrio == null ? '—' : formatearARS(c.ventaDiariaEquilibrio!),
        nota: c.reservaDiariaCentavos == null
            ? (c.ventaDiariaEquilibrio == null ? 'Falta ganancia o fijos para estimarla' : null)
            : 'Ganancia a generar por día: ${formatearARS(c.reservaDiariaCentavos!)}',
      ),
      TarjetaIndicador(
        etiqueta: 'Fijos pendientes de pago',
        valor: c.fijosPendientesCentavos == null ? '—' : formatearARS(c.fijosPendientesCentavos!),
        nota: c.fijosPagadosCentavos == null || c.fijos!.total == null
            ? sinFijos
            : 'Pagado ${formatearARS(c.fijosPagadosCentavos!)} de ${formatearARS(c.fijos!.total!)}',
        destacada: true,
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i > 0) const SizedBox(width: Espaciado.lg),
            Expanded(child: tarjetas[i]),
          ],
        ],
      ),
    );
  }
}

class _AvisoFijosIncompletos extends StatelessWidget {
  const _AvisoFijosIncompletos({required this.faltantes});

  final List<String> faltantes;

  @override
  Widget build(BuildContext context) {
    // Dato incompleto, no un error: se resuelve con texto + tono
    // secundario, no con un color de advertencia aparte (el único color con
    // significado en la app es el acento, reservado para otras tres cosas).
    return Text(
      'Sin cargar este mes: ${faltantes.join(', ')}.',
      style: TextStyle(color: context.colores.textoSecundario),
    );
  }
}

class _TarjetaFijosDelMes extends StatelessWidget {
  const _TarjetaFijosDelMes();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EquilibrioControlador>();
    final fijos = c.fijos!;
    return TarjetaSeccion(
      titulo: 'Fijos del mes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fijos.faltantes.isNotEmpty) _AvisoFijosIncompletos(faltantes: fijos.faltantes),
          for (final item in fijos.conceptos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
              child: Row(
                children: [
                  Expanded(child: Text(item.concepto.nombre)),
                  Text(
                    item.montoCentavos == null ? 'sin cargar' : formatearARS(item.montoCentavos!),
                    style: Theme.of(context).textTheme.bodyMedium!.tabular,
                  ),
                  IconButton(
                    icon: const Icon(IconosPlazoleta.edit, size: 18),
                    tooltip: 'Cargar / corregir monto de este mes',
                    onPressed: () => mostrarDialogoCargarMontoFijo(
                      context,
                      concepto: item.concepto,
                      montoActualCentavos: item.montoCentavos,
                      controlador: c,
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(IconosPlazoleta.add),
              label: const Text('Nuevo concepto'),
              onPressed: () => mostrarDialogoNuevoConceptoFijo(context, c),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaFijosPendientes extends StatelessWidget {
  const _TarjetaFijosPendientes();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EquilibrioControlador>();
    final pendientes = c.fijosPendientesCentavos;
    return TarjetaSeccion(
      titulo: 'Pagos de fijos',
      child: pendientes == null
          ? _AvisoFijosIncompletos(faltantes: c.fijos!.faltantes)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Presupuestado: ${formatearARS(c.fijos!.total!)}', style: Theme.of(context).textTheme.bodyMedium!.tabular),
                Text('Pagado: ${formatearARS(c.fijosPagadosCentavos!)}', style: Theme.of(context).textTheme.bodyMedium!.tabular),
                Text(
                  'Pendiente: ${formatearARS(pendientes)}',
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: Pesos.medium).tabular,
                ),
                const SizedBox(height: Espaciado.sm),
                for (final item in c.fijos!.conceptos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.concepto.nombre)),
                        BotonSecundario(
                          texto: 'Registrar pago',
                          onPressed: c.sesionCajaId == null
                              ? null
                              : () => mostrarDialogoRegistrarPagoFijo(
                                    context,
                                    concepto: item.concepto,
                                    sugeridoCentavos: item.montoCentavos ?? 0,
                                    controlador: c,
                                  ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// El retiro semanal (Regla 13 vieja) se eliminó entero — la separación de
// ganancia pasó a ser diaria, parte del ritual de apertura, revisando el
// cierre anterior por proveedor (Regla 13 nueva) — fuera de esta pantalla.
// "Fijos pendientes este mes" (arriba) sigue siendo el dato que esa
// pantalla nueva muestra al lado del total a retirar.
