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
import '../../domain/equilibrio.dart';
import '../kit/kit.dart';
import 'dialogo_cargar_monto_fijo.dart';
import 'dialogo_nuevo_concepto_fijo.dart';
import 'dialogo_registrar_pago_fijo.dart';
import 'equilibrio_controlador.dart';

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
          if (c.cargando) return const SizedBox.shrink();
          // `inicioMes` del mock v4: tres cifras arriba (150 px) y tres tarjetas que scrollean cada una por su cuenta.
          return LayoutBuilder(
            builder: (context, limites) {
              // Sin alto acotado (adentro de otro scroll) no hay "resto" que repartir: va con alto fijo y sin scroll propio.
              final acotado = limites.hasBoundedHeight;
              final entra = acotado && limites.maxHeight >= 560;
              const abajo = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: Aparecer(demora: Duration(milliseconds: 80), child: _TarjetaEstadoDeResultados())),
                  SizedBox(width: 14),
                  Expanded(child: Aparecer(demora: Duration(milliseconds: 120), child: _TarjetaMargenNecesario())),
                  SizedBox(width: 14),
                  Expanded(child: Aparecer(demora: Duration(milliseconds: 160), child: _TarjetaFijosDelMes())),
                ],
              );
              final contenido = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 150, child: _FilaIndicadoresMes()),
                  const SizedBox(height: 14),
                  if (entra) const Expanded(child: abajo) else const SizedBox(height: 560, child: abajo),
                ],
              );
              return entra || !acotado ? contenido : SingleChildScrollView(child: contenido);
            },
          );
        },
      ),
    );
  }
}

/// Las tres cifras del mes: ganancia bruta (bloque oscuro), cuánto de los fijos ya se cubrió y la venta diaria de
/// equilibrio. Sin todos los fijos cargados no se inventa: se dice qué falta.
class _FilaIndicadoresMes extends StatelessWidget {
  const _FilaIndicadoresMes();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<EquilibrioControlador>();
    final ganancia = c.ganancia!;
    final margen = ganancia.margenPonderado;
    final equilibrio = c.equilibrio;
    final faltan = c.fijos!.faltantes;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Aparecer.revelar(
            child: BloqueHero(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Ganancia bruta del mes', style: estilo(14, 600, color: p.heroSub)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: NumeroQueCuenta(valor: ganancia.gananciaBrutaCentavos, formato: pesos, estilo: Tipos.fig(p.sobreHero, tamanio: 40)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (margen != null) '${(margen * 100).round()} % de lo vendido',
                          if (ganancia.vendidoSinCostoCentavos > 0) 'sin costo ${pesos(ganancia.vendidoSinCostoCentavos)}',
                        ].join(' · '),
                        style: estilo(13.5, 400, color: p.heroSub),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Aparecer.revelar(
            orden: 1,
            child: Tarjeta(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(equilibrio == null || !equilibrio.cubierto ? 'Falta para cubrir los fijos' : 'Fijos cubiertos', style: estilo(14, 600, color: p.mute)),
                  if (equilibrio == null)
                    Text('Falta cargar: ${faltan.join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: estilo(15, 500, color: p.w))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${equilibrio.pctAvance} %', style: Tipos.fig(p.tinta, tamanio: 40)),
                            const SizedBox(width: 12),
                            if (!equilibrio.cubierto)
                              Expanded(child: Text('faltan ${pesos(equilibrio.faltanteCentavos)}', style: estilo(14, 500, color: p.mute))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        BarraTramos(alto: 10, tramos: [(equilibrio.pctAvance / 100, p.azul)]),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Aparecer.revelar(
            orden: 2,
            child: Tarjeta(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Venta diaria de equilibrio', style: estilo(14, 600, color: p.mute)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.ventaDiariaEquilibrio == null ? '—' : pesos(c.ventaDiariaEquilibrio!), style: Tipos.fig(p.tinta, tamanio: 40)),
                      const SizedBox(height: 4),
                      Text(
                        c.reservaDiariaCentavos == null
                            ? 'Falta ganancia o fijos para estimarla'
                            : 'Ganancia a generar por día: ${pesos(c.reservaDiariaCentavos!)}',
                        style: estilo(13.5, 400, color: p.mute),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fila de cuenta (`.ln`): etiqueta y monto, con línea finísima arriba; las de resultado van fuertes.
Widget _ln(BuildContext context, String etiqueta, String valor, {bool fuerte = false, Color? colorValor}) {
  final p = context.p;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: p.pelo))),
    child: Row(
      children: [
        Expanded(child: Text(etiqueta, style: estilo(15.5, fuerte ? 600 : 400, color: fuerte ? p.tinta : p.mute))),
        const SizedBox(width: 12),
        Text(valor, style: estilo(15.5, fuerte ? 600 : 400, color: colorValor ?? (fuerte ? p.tinta : p.mute), num: true)),
      ],
    ),
  );
}

String _resta(int centavos) => centavos > 0 ? '−${pesos(centavos)}' : pesos(centavos);

class _CabeceraTarjeta extends StatelessWidget {
  const _CabeceraTarjeta(this.titulo, {this.derecha = const []});
  final String titulo;
  final List<Widget> derecha;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Sec(titulo)),
          for (final (i, w) in derecha.indexed) ...[if (i > 0) const SizedBox(width: 6), w],
        ]),
      );
}

class _TarjetaEstadoDeResultados extends StatelessWidget {
  const _TarjetaEstadoDeResultados();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<EquilibrioControlador>();
    final e = c.estado!;
    return Tarjeta(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CabeceraTarjeta('Estado de resultados', derecha: [
              e.esCompleto ? const Etiqueta('Completo', tono: TonoMock.g) : const Etiqueta('Incompleto', tono: TonoMock.w),
            ]),
            _ln(context, 'Ventas del mes', pesos(e.ventasNetasCentavos)),
            _ln(context, 'Costo de la mercadería', _resta(e.costoMercaderiaCentavos)),
            _ln(context, 'Ganancia bruta${e.gananciaBrutaBp == null ? '' : ' (${(e.gananciaBrutaBp! / 100).round()} %)'}', pesos(e.gananciaBrutaCentavos), fuerte: true),
            _ln(context, 'Gastos fijos', _resta(e.gastosFijosCentavos)),
            _ln(context, 'Gastos variables', _resta(e.gastosVariablesCentavos)),
            _ln(context, 'Resultado del negocio', pesos(e.resultadoOperativoCentavos), fuerte: true),
            _ln(context, 'Sueldo objetivo del dueño', _resta(e.sueldoObjetivoCentavos)),
            _ln(context, 'Queda para el negocio', pesos(e.resultadoDespuesDelSueldoCentavos), fuerte: true),
            _ln(context, 'Ya retirado este mes', pesos(e.retirosDelMesCentavos)),
            _ln(context, 'Retirable hoy', pesos(e.retirableCentavos), fuerte: true, colorValor: p.g),
            for (final a in e.advertencias) Padding(padding: const EdgeInsets.only(top: 8), child: Text(a, style: estilo(13.5, 400, color: p.mute))),
            if (!c.tieneConceptoSueldo) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Btn('Agregar sueldo del dueño', variante: VarBtn.ton, sobreGris: true, tam: TamBtn.sm, icono: Ic.plus, onTap: () => c.agregarConcepto(nombreConceptoSueldo)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _porcentaje(int bp) => '${(bp / 100).toStringAsFixed(1).replaceAll('.', ',')} %';

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
    final p = context.p;
    final c = context.watch<EquilibrioControlador>();
    if (c.objetivoCargado && !_sincronizado) {
      _sincronizado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_ventaCtrl.text.isEmpty) _ventaCtrl.text = _texto(c.ventaObjetivoCentavos);
        if (_retenerCtrl.text.isEmpty) _retenerCtrl.text = _texto(c.gananciaARetenerCentavos);
      });
    }
    final necesario = c.margenNecesario;
    final actual = c.estado!.gananciaBrutaBp;
    final bajos = c.productosBajoMargen;
    return Tarjeta(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CabeceraTarjeta('Margen necesario', derecha: [
              if (necesario != null && actual != null)
                actual >= necesario
                    ? const Etiqueta('Tu margen alcanza', tono: TonoMock.g)
                    : Etiqueta('Te faltan ${((necesario - actual) / 100).toStringAsFixed(1).replaceAll('.', ',')} puntos', tono: TonoMock.w),
            ]),
            Campo(
              key: const Key('campo_venta_objetivo'),
              etiqueta: 'Venta que querés hacer en el mes',
              controller: _ventaCtrl,
              pista: r'$ 0',
              color: p.papel,
              teclado: TextInputType.number,
              onChanged: (_) => _aplicar(),
            ),
            const SizedBox(height: 12),
            Campo(
              key: const Key('campo_ganancia_retener'),
              etiqueta: 'Ganancia que querés dejar',
              controller: _retenerCtrl,
              pista: r'$ 0',
              color: p.papel,
              teclado: TextInputType.number,
              onChanged: (_) => _aplicar(),
            ),
            const SizedBox(height: 12),
            if (necesario == null)
              Nota(
                texto: c.ventaObjetivoCentavos == 0
                    ? 'Cargá la venta que esperás hacer en el mes para ver el margen que necesitás.'
                    : 'Con esos números no hay precio que alcance: los gastos y la ganancia pedida igualan o superan la venta.',
              )
            else ...[
              Lista(color: p.papel, filas: [
                Kv('Margen necesario', _porcentaje(necesario)),
                Kv('Margen que tenés hoy', actual == null ? 'sin ventas con costo' : _porcentaje(actual)),
                if (c.ventaNecesariaConMargenActualCentavos != null) Kv('Venta que haría falta con tu margen', pesos(c.ventaNecesariaConMargenActualCentavos!)),
              ]),
              const SizedBox(height: 12),
              Nota(
                tono: bajos.isEmpty ? null : TonoMock.w,
                texto: bajos.isEmpty
                    ? 'Ningún producto con costo y precio cargados queda por debajo.'
                    : '${bajos.length} ${bajos.length == 1 ? 'producto está' : 'productos están'} por debajo del margen necesario. '
                        'El precio sugerido es solo una sugerencia: no se cambia nada solo.',
              ),
              for (final b in bajos.take(8))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text(b.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(15, 500, color: p.tinta))),
                    Text('${pesos(b.precioCentavos)} → ${pesos(b.precioSugeridoCentavos)}${b.esPesable ? ' /kg' : ''}', style: estilo(13.5, 400, color: p.mute, num: true)),
                    const SizedBox(width: 8),
                    Etiqueta(_porcentaje(b.gananciaBp), tono: TonoMock.w),
                  ]),
                ),
              if (c.estado!.sueldoObjetivoCentavos == 0 || !c.estado!.esCompleto)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Ojo: sin sueldo cargado, fijos completos y costos de todo lo vendido, el margen necesario queda más bajo de lo real.',
                    style: estilo(13.5, 400, color: p.mute),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fijos del mes: lo presupuestado, lo pagado y lo pendiente arriba; cada concepto con su monto, su estado y "Pagar"
/// (con caja abierta) o "Cargar" si falta el monto de este mes.
class _TarjetaFijosDelMes extends StatelessWidget {
  const _TarjetaFijosDelMes();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = context.watch<EquilibrioControlador>();
    final fijos = c.fijos!;
    final pendientes = c.fijosPendientesCentavos;
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CabeceraTarjeta('Fijos del mes', derecha: [
            if (pendientes != null && pendientes > 0) Etiqueta('Faltan ${pesos(pendientes)}', tono: TonoMock.w),
            Btn('Nuevo', variante: VarBtn.ton, sobreGris: true, tam: TamBtn.xs, icono: Ic.plus, onTap: () => mostrarDialogoNuevoConceptoFijo(context, c)),
          ]),
          if (fijos.total != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(spacing: 14, runSpacing: 4, children: [
                Text.rich(TextSpan(text: 'Presupuestado ', style: estilo(13.5, 400, color: p.mute), children: [TextSpan(text: pesos(fijos.total!), style: estilo(13.5, 600, color: p.tinta, num: true))])),
                Text.rich(TextSpan(text: 'Pagado ', style: estilo(13.5, 400, color: p.mute), children: [TextSpan(text: pesos(c.fijosPagadosCentavos ?? 0), style: estilo(13.5, 600, color: p.g, num: true))])),
                Text.rich(TextSpan(text: 'Pendiente ', style: estilo(13.5, 400, color: p.mute), children: [TextSpan(text: pesos(pendientes ?? 0), style: estilo(13.5, 600, color: p.w, num: true))])),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Sin cargar este mes: ${fijos.faltantes.join(', ')}.', style: estilo(13.5, 400, color: p.w)),
            ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: fijos.conceptos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 1),
                itemBuilder: (context, i) {
                  final item = fijos.conceptos[i];
                  final estado = estadoDelFijo(montoCentavos: item.montoCentavos, pagadoCentavos: c.pagadoPorConcepto[item.concepto.id] ?? 0);
                  final (texto, tono) = switch (estado) {
                    EstadoFijo.pagado => ('Pagado', TonoMock.g),
                    EstadoFijo.pendiente => ('Pendiente', TonoMock.w),
                    EstadoFijo.faltaCargar => ('Falta cargar', TonoMock.b),
                  };
                  return Container(
                    color: p.papel,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    child: Row(
                      children: [
                        Expanded(
                          child: Tocable(
                            onTap: () => mostrarDialogoCargarMontoFijo(context, concepto: item.concepto, montoActualCentavos: item.montoCentavos, controlador: c),
                            radio: 8,
                            tooltip: 'Cargar o corregir el monto de este mes',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.concepto.nombre, style: estilo(15.5, 500, color: p.tinta)),
                                Text(item.montoCentavos == null ? 'sin cargar' : pesos(item.montoCentavos!), style: estilo(13, 400, color: p.mute, num: true)),
                              ],
                            ),
                          ),
                        ),
                        Etiqueta(texto, tono: tono),
                        if (estado != EstadoFijo.pagado) ...[
                          const SizedBox(width: 8),
                          estado == EstadoFijo.faltaCargar
                              ? Btn('Cargar', variante: VarBtn.ton, tam: TamBtn.xs, onTap: () => mostrarDialogoCargarMontoFijo(context, concepto: item.concepto, montoActualCentavos: item.montoCentavos, controlador: c))
                              : Btn(
                                  'Pagar',
                                  variante: VarBtn.ton,
                                  tam: TamBtn.xs,
                                  tooltip: c.sesionCajaId == null ? 'Hace falta la caja abierta para registrar un pago' : null,
                                  onTap: c.sesionCajaId == null
                                      ? null
                                      : () => mostrarDialogoRegistrarPagoFijo(context, concepto: item.concepto, sugeridoCentavos: item.montoCentavos ?? 0, controlador: c),
                                ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
