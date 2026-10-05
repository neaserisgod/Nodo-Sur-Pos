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
import '../../data/repositorio_rentabilidad.dart' show nombreConceptoSueldo;
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
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
              _TarjetaEstadoDeResultados(),
              SizedBox(height: Espaciado.lg),
              _TarjetaMargenNecesario(),
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

/// Del bruto a lo que realmente se puede retirar: la cascada contable del mes
/// (`domain/rentabilidad.dart`). La ganancia bruta no es plata libre — primero
/// hay que pagar los gastos —, y esta tarjeta lo muestra de arriba hacia abajo.
class _TarjetaEstadoDeResultados extends StatelessWidget {
  const _TarjetaEstadoDeResultados();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EquilibrioControlador>();
    final e = c.estado!;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;

    Widget fila(String etiqueta, int centavos, {bool resta = false, bool fuerte = false}) {
      final estilo = textTheme.bodyMedium!.copyWith(fontWeight: fuerte ? Pesos.fuerte : null);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: estilo)),
            Text(
              '${resta && centavos > 0 ? '− ' : ''}${formatearARS(centavos)}',
              style: estilo.tabular,
            ),
          ],
        ),
      );
    }

    return TarjetaSeccion(
      titulo: 'Estado de resultados del mes',
      insignia: e.esCompleto
          ? const Insignia(texto: 'Completo', tono: Tono.ganancia)
          : const Insignia(texto: 'Incompleto', tono: Tono.alerta),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fila('Ventas', e.ventasNetasCentavos),
          fila('Costo de la mercadería', e.costoMercaderiaCentavos, resta: true),
          const Divider(),
          fila('Ganancia bruta${e.gananciaBrutaBp == null ? '' : ' (${(e.gananciaBrutaBp! / 100).round()}% de lo vendido)'}', e.gananciaBrutaCentavos, fuerte: true),
          fila('Gastos fijos', e.gastosFijosCentavos, resta: true),
          fila('Gastos variables', e.gastosVariablesCentavos, resta: true),
          const Divider(),
          fila('Resultado del negocio', e.resultadoOperativoCentavos, fuerte: true),
          fila('Sueldo objetivo del dueño', e.sueldoObjetivoCentavos, resta: true),
          const Divider(),
          fila('Queda para el negocio', e.resultadoDespuesDelSueldoCentavos, fuerte: true),
          const SizedBox(height: Espaciado.md),
          BloqueSuave(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fila('Ya retirado este mes', e.retirosDelMesCentavos),
                fila('Retirable hoy', e.retirableCentavos, fuerte: true),
              ],
            ),
          ),
          if (e.advertencias.isNotEmpty) ...[
            const SizedBox(height: Espaciado.md),
            for (final a in e.advertencias)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(a, style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario)),
              ),
          ],
          if (!c.tieneConceptoSueldo)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const IconoPlz(IconosPlazoleta.add),
                label: const Text('Agregar sueldo del dueño'),
                onPressed: () => c.agregarConcepto(nombreConceptoSueldo),
              ),
            ),
        ],
      ),
    );
  }
}

String _porcentaje(int bp) => '${(bp / 100).toStringAsFixed(1)}%';

/// Cuánto margen tienen que dejar las ventas para cubrir gastos, sueldo y la
/// ganancia que el dueño quiere retener, y qué productos hoy dejan menos que
/// eso. Todo es sugerencia: ningún precio se cambia desde acá (Regla 14).
class _TarjetaMargenNecesario extends StatefulWidget {
  const _TarjetaMargenNecesario();

  @override
  State<_TarjetaMargenNecesario> createState() => _TarjetaMargenNecesarioState();
}

class _TarjetaMargenNecesarioState extends State<_TarjetaMargenNecesario> {
  late final TextEditingController _ventaCtrl;
  late final TextEditingController _retenerCtrl;
  bool _sincronizado = false;

  static String _texto(int centavos) => centavos == 0 ? '' : formatearARS(centavos, conSigno: false);

  @override
  void initState() {
    super.initState();
    final c = context.read<EquilibrioControlador>();
    _ventaCtrl = TextEditingController(text: _texto(c.ventaObjetivoCentavos));
    _retenerCtrl = TextEditingController(text: _texto(c.gananciaARetenerCentavos));
  }

  @override
  void dispose() {
    _ventaCtrl.dispose();
    _retenerCtrl.dispose();
    super.dispose();
  }

  int _leer(TextEditingController ctrl) => ctrl.text.trim().isEmpty ? 0 : parsearARS(ctrl.text);

  void _aplicar() {
    final int venta;
    final int retener;
    try {
      venta = _leer(_ventaCtrl);
      retener = _leer(_retenerCtrl);
    } on FormatException {
      return; // se espera a que el texto sea un monto válido
    }
    context.read<EquilibrioControlador>().guardarObjetivo(ventaCentavos: venta, retenerCentavos: retener);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EquilibrioControlador>();
    // Lo guardado llega después de que la pantalla ya se mostró: se vuelca a los
    // campos una sola vez, sin pisar lo que el dueño haya empezado a tipear.
    if (c.objetivoCargado && !_sincronizado) {
      _sincronizado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_ventaCtrl.text.isEmpty) _ventaCtrl.text = _texto(c.ventaObjetivoCentavos);
        if (_retenerCtrl.text.isEmpty) _retenerCtrl.text = _texto(c.gananciaARetenerCentavos);
      });
    }
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final necesario = c.margenNecesario;
    final actual = c.estado!.gananciaBrutaBp;

    Widget fila(String etiqueta, String valor, {bool fuerte = false}) {
      final estilo = textTheme.bodyMedium!.copyWith(fontWeight: fuerte ? Pesos.fuerte : null);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(etiqueta, style: estilo)), Text(valor, style: estilo.tabular)]),
      );
    }

    return TarjetaSeccion(
      titulo: 'Margen necesario',
      insignia: necesario == null || actual == null
          ? null
          : actual >= necesario
              ? const Insignia(texto: 'Tu margen alcanza', tono: Tono.ganancia)
              : Insignia(texto: 'Te faltan ${((necesario - actual) / 100).toStringAsFixed(1)} puntos', tono: Tono.alerta),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cuánta ganancia sobre el precio tienen que dejar tus ventas para pagar los gastos, tu sueldo y lo que querés dejar en el negocio.',
            style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_venta_objetivo'),
                  controller: _ventaCtrl,
                  etiqueta: 'Venta que querés hacer en el mes',
                  onChanged: (_) => _aplicar(),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_ganancia_retener'),
                  controller: _retenerCtrl,
                  etiqueta: 'Ganancia que querés dejar en el negocio',
                  onChanged: (_) => _aplicar(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          if (necesario == null)
            Text(
              c.ventaObjetivoCentavos == 0
                  ? 'Cargá la venta que esperás hacer en el mes para ver el margen que necesitás.'
                  : 'Con esos números no hay precio que alcance: los gastos y la ganancia pedida igualan o superan la venta.',
              style: textTheme.bodyMedium,
            )
          else ...[
            fila('Margen necesario', _porcentaje(necesario), fuerte: true),
            fila('Margen que tenés hoy', actual == null ? 'sin ventas con costo' : _porcentaje(actual)),
            if (c.ventaNecesariaConMargenActualCentavos != null)
              fila('Venta del mes que haría falta con tu margen de hoy', formatearARS(c.ventaNecesariaConMargenActualCentavos!)),
            if (c.estado!.sueldoObjetivoCentavos == 0 || !c.estado!.esCompleto) ...[
              const SizedBox(height: Espaciado.sm),
              Text(
                'Ojo: sin sueldo cargado, fijos completos y costos de todo lo vendido, el margen necesario queda más bajo de lo real.',
                style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
              ),
            ],
            const SizedBox(height: Espaciado.md),
            if (c.productosBajoMargen.isEmpty)
              Text('Ningún producto con costo y precio cargados queda por debajo.', style: textTheme.bodyMedium)
            else ...[
              Text(
                c.productosBajoMargen.length == 1
                    ? '1 producto deja menos que ese margen:'
                    : '${c.productosBajoMargen.length} productos dejan menos que ese margen:',
                style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
              ),
              const SizedBox(height: Espaciado.xs),
              for (final p in c.productosBajoMargen.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(
                        '${formatearARS(p.precioCentavos)} → ${formatearARS(p.precioSugeridoCentavos)}${p.esPesable ? ' /kg' : ''}',
                        style: textTheme.bodySmall!.copyWith(color: colores.textoSecundario).tabular,
                      ),
                      const SizedBox(width: Espaciado.sm),
                      Insignia(texto: _porcentaje(p.gananciaBp), tono: Tono.alerta),
                    ],
                  ),
                ),
              if (c.productosBajoMargen.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: Espaciado.xs),
                  child: Text('y ${c.productosBajoMargen.length - 8} más…', style: textTheme.bodySmall),
                ),
              const SizedBox(height: Espaciado.xs),
              Text(
                'El precio de la derecha es una sugerencia: no se cambia nada solo.',
                style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
              ),
            ],
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
                    icon: const IconoPlz(IconosPlazoleta.edit, size: 18),
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
              icon: const IconoPlz(IconosPlazoleta.add),
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
