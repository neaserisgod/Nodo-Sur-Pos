// "Separaciones", hecha desde cero como el mock v4 (`SCR.separaciones`, 2026-10-06):
//
// - Arriba, cuatro bloques: a separar del cajón (negro), a separar de Mercado Pago (azul), la reserva diaria de fijos
//   (amarillo) y lo que te queda (verde).
// - Debajo, "A separar por proveedor": una fila por proveedor con su tilde, de dónde sale la plata, el monto y "Pagar".
//   El tilde lo marca separado; destildarlo lo deshace (salvo que ya esté pagado). Arriba a la derecha, el avance.
//
// "Qué separar" es siempre de hoy: la separación es diaria. Semana y Mes (y "Ganancia" para hoy) muestran lo vendido
// por proveedor — vendido, reposición y ganancia —, que es lo que el mock llama "Ganancia". "Retirar plata" lleva a la
// ganancia sin revisar de cada proveedor (Regla 13: se retira por proveedor, no un monto suelto).
//
// "Pagar" vuelve a estar en cada fila (el mock v4 del dueño, 2026-10-05, es más nuevo que el "innecesario" del
// 2026-09-26): abre el pago rápido con el proveedor ya elegido.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_reposicion.dart' show SeparacionDelDia;
import '../../domain/modulos.dart';
import '../../domain/periodo.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/armazon_gestion.dart';
import '../kit/kit.dart';
import '../navegacion/refresco_por_celular.dart';
import '../navegacion/route_observer.dart';
import '../venta/dialogo_pagar_proveedor_rapido.dart';
import 'dialogo_ganancia_proveedor.dart';
import 'dialogo_sin_costo.dart';
import 'separaciones_controlador.dart';

/// Cada cuánto se recarga sola mientras está abierta — las ventas y cambios
/// que llegan del celular por la sincronización no avisan a las pantallas
/// del escritorio (El dueño, 2026-09-26: "como si tuviese que abrir y cerrar
/// para que aparezca"). La base es chica: recargar cuesta nada.
const _intervaloRecarga = Duration(seconds: 15);

class PantallaSeparaciones extends StatefulWidget {
  const PantallaSeparaciones({
    super.key,
    required this.db,
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<PantallaSeparaciones> createState() => _PantallaSeparacionesState();
}

class _PantallaSeparacionesState extends State<PantallaSeparaciones> with RouteAware, RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _c.cargarTodo();

  late final _c = SeparacionesControlador(
    widget.db,
    usuarioId: widget.usuarioId,
    sesionCajaId: widget.sesionCajaId,
  )..cargarTodo();
  late final Timer _recarga = Timer.periodic(_intervaloRecarga, (_) => _c.cargarTodo());

  @override
  void initState() {
    super.initState();
    _recarga; // arranca el timer
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ruta = ModalRoute.of(context);
    if (ruta is PageRoute<dynamic>) routeObserver.subscribe(this, ruta);
  }

  /// Volver desde otra pantalla (ej. Proveedores, después de cargar un costo)
  /// recarga en el momento, sin esperar el timer.
  @override
  void didPopNext() => _c.cargarTodo();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _recarga.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Hoy = qué separar; Semana y Mes = lo vendido en ese período.
  Future<void> _elegirPeriodo(PeriodoResumen p) async {
    _c.cambiarVista(p == PeriodoResumen.hoy ? VistaSeparaciones.queSeparar : VistaSeparaciones.loVendido);
    await _c.cambiarPeriodo(p);
  }

  /// "Ganancia": lo vendido de hoy (o volver a qué separar si ya se está mirando).
  Future<void> _alternarGanancia() async {
    if (_c.vista == VistaSeparaciones.loVendido && _c.periodo == PeriodoResumen.hoy) {
      _c.cambiarVista(VistaSeparaciones.queSeparar);
      return;
    }
    _c.cambiarVista(VistaSeparaciones.loVendido);
    await _c.cambiarPeriodo(PeriodoResumen.hoy);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SeparacionesControlador>.value(
      value: _c,
      child: Consumer<SeparacionesControlador>(
        builder: (context, c, _) {
          final viendoGanancia = c.vista == VistaSeparaciones.loVendido && c.periodo == PeriodoResumen.hoy;
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'separaciones',
            usuarioId: widget.usuarioId,
            sesionCajaId: widget.sesionCajaId,
            titulo: 'Separaciones',
            subtitulo: _subtitulo(c),
            acciones: [
              Seg<PeriodoResumen>(
                opciones: const [
                  (PeriodoResumen.hoy, 'Hoy'),
                  (PeriodoResumen.semana, 'Semana'),
                  (PeriodoResumen.mes, 'Mes'),
                ],
                valor: c.vista == VistaSeparaciones.queSeparar ? PeriodoResumen.hoy : c.periodo,
                onCambio: _elegirPeriodo,
              ),
              Btn(
                'Ganancia',
                key: const Key('boton_ganancia'),
                variante: viendoGanancia ? VarBtn.dark : VarBtn.ton,
                onTap: _alternarGanancia,
              ),
              if (moduloActivo(Modulo.retiroGanancias))
                Btn('Retirar plata', key: const Key('boton_retirar_plata'), variante: VarBtn.dark, onTap: () => _retirarPlata(context, c)),
            ],
            child: c.cargando
                ? const SizedBox.shrink()
                : c.vista == VistaSeparaciones.queSeparar
                ? const _VistaQueSeparar()
                : const _VistaLoVendido(),
          );
        },
      ),
    );
  }
}

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _fechaLarga(DateTime f) => '${_dias[f.weekday - 1]} ${f.day} de ${_meses[f.month - 1]}';

/// Solo para lectores de pantalla (el mock no muestra subtítulo).
String _subtitulo(SeparacionesControlador c) {
  final hoy = DateTime.now();
  if (c.vista == VistaSeparaciones.queSeparar || c.periodo == PeriodoResumen.hoy) {
    return 'Hoy · ${_fechaLarga(hoy)}';
  }
  final inicio = inicioDePeriodo(c.periodo, hoy)!;
  return c.periodo == PeriodoResumen.semana
      ? 'Esta semana · desde el ${_fechaLarga(inicio)}'
      : 'Este mes · ${_meses[hoy.month - 1]}';
}

/// "Retirar plata": la ganancia sin revisar de cada proveedor; elegir uno abre su ganancia (retener o retirar).
Future<void> _retirarPlata(BuildContext context, SeparacionesControlador c) {
  final pendientes = c.gananciaSinRevisar.values.where((g) => g.gananciaCentavos > 0).toList()
    ..sort((a, b) => b.gananciaCentavos.compareTo(a.gananciaCentavos));
  return mostrarModalMock<void>(
    context,
    builder: (contextoModal) => ModalMock(
      titulo: 'Retirar plata',
      subtitulo: 'La ganancia se retira por proveedor: elegí de cuál.',
      ancho: AnchoModal.angosto,
      cuerpo: [
        if (pendientes.isEmpty)
          const Vacio(texto: 'No hay ganancia sin revisar')
        else
          Lista(filas: [
            for (final g in pendientes)
              Kv(
                g.proveedor.nombre,
                pesos(g.gananciaCentavos),
                colorValor: contextoModal.p.g,
                onTap: () {
                  Navigator.of(contextoModal).pop();
                  mostrarDialogoGananciaProveedor(context, controlador: c, proveedorId: g.proveedor.id);
                },
              ),
          ]),
        const Nota(texto: 'Lo que no se retira se puede retener como colchón del proveedor. Todo queda anotado.'),
      ],
    ),
  );
}

void _verSinCosto(BuildContext context, SeparacionesControlador c, {required DateTime desde, required String periodo, String? soloProveedor}) {
  mostrarDialogoSinCosto(
    context,
    usuarioId: c.usuarioId,
    alGuardar: c.cargarTodo,
    db: c.db,
    desde: desde,
    periodo: periodo,
    soloProveedor: soloProveedor,
  );
}

// ─── Bloques de arriba ─────────────────────────────────────────────────────

/// Un bloque de cifra del mock (`.hero` / `.hero.blue` / `.card.w` / `.card`): título chico y el número grande.
class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.valor, required this.tipo, this.pie});

  final String titulo;
  final int valor;
  final _EstiloBloque tipo;
  final String? pie;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (fondo, colorTitulo, colorValor) = switch (tipo) {
      _EstiloBloque.negro => (p.hero, p.heroSub, p.sobreHero),
      // Título en blanco pleno: al 75 % quedaba en 3,4:1 sobre el azul (contraste medido, DISENO.md).
      _EstiloBloque.azul => (p.azul, Colors.white, Colors.white),
      _EstiloBloque.amarillo => (p.wbg, p.w, p.w),
      _EstiloBloque.verde => (p.s, p.mute, valor < 0 ? p.b : p.g),
      _EstiloBloque.gris => (p.s, p.mute, p.tinta),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 22, 30, 22),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(34)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: _e(14, 600, colorTitulo)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroQueCuenta(
              valor: valor,
              formato: pesos,
              estilo: estilo(42, 550, color: colorValor, em: -.04, num: true),
            ),
          ),
          if (pie != null) ...[
            const SizedBox(height: 4),
            Text(pie!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _e(13.5, 400, colorTitulo)),
          ],
        ],
      ),
    );
  }
}

TextStyle _e(double tamanio, double peso, Color color) => estilo(tamanio, peso, color: color);

enum _EstiloBloque { negro, azul, amarillo, verde, gris }

Widget _filaDeBloques(List<Widget> bloques) => IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, b) in bloques.indexed) ...[
        if (i > 0) const SizedBox(width: 14),
        Expanded(child: Aparecer.revelar(orden: i, child: b)),
      ],
    ],
  ),
);

/// `.list` del mock, pero con filas a demanda (lista larga: `ListView`).
class _ListaFilas extends StatelessWidget {
  const _ListaFilas({required this.cantidad, required this.fila});

  final int cantidad;
  final Widget Function(BuildContext context, int i) fila;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: ColoredBox(
        color: p.s,
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: cantidad,
          separatorBuilder: (_, _) => ColoredBox(color: p.pelo, child: const SizedBox(height: 1)),
          itemBuilder: (context, i) => Aparecer.tarjeta(orden: i, child: fila(context, i)),
        ),
      ),
    );
  }
}

// ─── Qué separar ───────────────────────────────────────────────────────────

class _VistaQueSeparar extends StatelessWidget {
  const _VistaQueSeparar();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final p = context.p;
    final tarjetas = c.tarjetasVisibles;
    final total = c.tarjetas.fold(0, (a, t) => a + t.totalCentavos);
    final separado = c.tarjetas.where((t) => t.separada).fold(0, (a, t) => a + t.totalCentavos);
    final avisos = <(String, TonoMock, Key?)>[
      if (c.ajuste.corridoAMpCentavos > 0)
        ('No alcanza el efectivo del cajón: ${pesos(c.ajuste.corridoAMpCentavos)} se separan de Mercado Pago.', TonoMock.i, null),
      if (c.ajuste.corridoAMpCentavos < 0)
        ('No alcanza Mercado Pago: ${pesos(-c.ajuste.corridoAMpCentavos)} se separan del cajón.', TonoMock.i, null),
      if (c.ajuste.faltanteCentavos > 0)
        ('No alcanza entre las dos cajas: faltan ${pesos(c.ajuste.faltanteCentavos)}.', TonoMock.b, const Key('aviso_faltante')),
    ];
    final lata = c.cobrado.cigarrillosCentavos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filaDeBloques([
          _Bloque(
            titulo: 'A separar del cajón',
            valor: c.separarEfectivoCentavos,
            tipo: _EstiloBloque.negro,
            pie: lata > 0 ? 'Aparte, la lata se lleva ${pesos(lata)}' : null,
          ),
          _Bloque(titulo: 'A separar de Mercado Pago', valor: c.separarMpCentavos, tipo: _EstiloBloque.azul),
          if (c.reservaDiariaCentavos != null)
            _Bloque(titulo: 'Reserva diaria de fijos', valor: c.reservaDiariaCentavos!, tipo: _EstiloBloque.amarillo),
          _Bloque(
            titulo: 'Te queda',
            valor: c.quedaEfectivoCentavos + c.quedaMpCentavos,
            tipo: _EstiloBloque.verde,
            pie: 'Efectivo ${pesos(c.quedaEfectivoCentavos)} · MP ${pesos(c.quedaMpCentavos)}',
          ),
        ]),
        for (final (texto, tono, clave) in avisos) ...[
          const SizedBox(height: 10),
          Nota(key: clave, texto: texto, tono: tono, icono: Ic.warn),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            const Sec('A separar por proveedor'),
            if (c.vendidoSinCostoHoyCentavos > 0) ...[
              const SizedBox(width: 14),
              Flexible(
                child: _ChipSinCosto(
                  texto: '${pesos(c.vendidoSinCostoHoyCentavos)} vendidos sin costo',
                  onTap: () => _verSinCosto(context, c, desde: c.inicioDeHoy, periodo: 'hoy'),
                ),
              ),
            ],
            const Spacer(),
            if (c.tarjetas.isNotEmpty) ...[
              Text(
                '${c.cantidadSeparadas} de ${c.tarjetas.length} separados',
                key: const Key('progreso_separados'),
                style: estilo(15, 600, color: p.mute),
              ),
              // A 1366 no entra todo en la fila: queda la cuenta de separados.
              if (MediaQuery.sizeOf(context).width >= 1700) ...[
                const SizedBox(width: 6),
                Text('· Separaste ${pesos(separado)} de ${pesos(total)}', style: estilo(15, 600, color: p.mute)),
              ],
              const SizedBox(width: 14),
              Btn('Marcar todo', tam: TamBtn.xs, variante: VarBtn.ton, onTap: c.procesando.isEmpty && c.hayPorSeparar ? c.marcarTodo : null),
              const SizedBox(width: 6),
              Btn('Desmarcar todo', tam: TamBtn.xs, variante: VarBtn.ton, onTap: c.procesando.isEmpty && c.hayParaDesmarcar ? c.desmarcarTodo : null),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: tarjetas.isEmpty
              ? Vacio(texto: c.busqueda.isEmpty ? 'Hoy no hay nada para separar' : 'Ningún proveedor coincide con "${c.busqueda}"')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: _ListaFilas(
                        cantidad: tarjetas.length,
                        fila: (context, i) => _FilaSeparar(tarjeta: tarjetas[i], total: total),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// El chip amarillo "N sin costo" del mock: abre qué se vendió sin costo cargado.
class _ChipSinCosto extends StatelessWidget {
  const _ChipSinCosto({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tocable(
      key: const Key('aviso_sin_costo'),
      onTap: onTap,
      radio: 999,
      etiqueta: '$texto. Ver cuáles',
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: p.wbg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icono(Ic.warn, size: 16, color: p.w),
            const SizedBox(width: 8),
            Flexible(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(14.5, 500, color: p.w))),
          ],
        ),
      ),
    );
  }
}

/// Una fila del mock: tilde redondo, nombre (tachado si ya está separado), días y de qué caja sale, la etiqueta de la
/// caja, el monto y "Pagar". Tocar la fila (o el tilde) la marca o desmarca.
class _FilaSeparar extends StatelessWidget {
  const _FilaSeparar({required this.tarjeta, required this.total});

  final TarjetaSeparacion tarjeta;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SeparacionesControlador>();
    final procesando = context.select<SeparacionesControlador, bool>((c) => c.procesando.contains(tarjeta.proveedorId));
    final p = context.p;
    final t = tarjeta;
    final prov = t.fila.proveedor!;
    final deuda = c.deudaPorProveedor[prov.id] ?? 0;
    final estado = t.bloqueada ? 'Separado — ya pagado' : (t.separada ? 'Separado' : 'A separar');
    final detalle = [
      if (prov.diaPedido != null) 'Pedido ${prov.diaPedido!.toLowerCase()}',
      if (prov.diaEntrega != null) 'entrega ${prov.diaEntrega!.toLowerCase()}',
      if (total > 0) '${(t.totalCentavos * 100 / total).round()} % del total',
      if (t.efectivoCentavos > 0 && t.mpCentavos > 0) 'cajón ${pesos(t.efectivoCentavos)} · MP ${pesos(t.mpCentavos)}',
      if (deuda > 0) 'le debés ${pesos(deuda)}',
    ].join(' · ');
    final alternar = procesando || t.bloqueada ? null : () => c.alternar(t);
    return AlPasar(
      builder: (encima) => AnimatedContainer(
        duration: ms(200),
        constraints: const BoxConstraints(minHeight: 58),
        color: encima ? p.s2 : p.s,
        padding: const EdgeInsets.fromLTRB(24, 8, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: Tocable(
                onTap: alternar,
                radio: 18,
                etiqueta: '${prov.nombre}: $estado',
                seleccionado: t.separada,
                child: Row(
                  children: [
                    _Tilde(marcado: t.separada, bloqueado: t.bloqueada),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t.fila.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: estilo(17.5, 550, color: t.separada ? p.mute : p.tinta).copyWith(
                              decoration: t.separada ? TextDecoration.lineThrough : null,
                              decorationColor: p.mute,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            detalle.isEmpty ? estado : '$estado · $detalle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: estilo(13, 400, color: p.mute),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            if (t.efectivoCentavos > 0) const Etiqueta('Cajón', tono: TonoMock.g),
            if (t.efectivoCentavos > 0 && t.mpCentavos > 0) const SizedBox(width: 6),
            if (t.mpCentavos > 0) const Etiqueta('Mercado Pago', tono: TonoMock.i),
            const SizedBox(width: 14),
            SizedBox(
              width: 130,
              child: Text(
                pesos(t.totalCentavos),
                textAlign: TextAlign.right,
                style: estilo(19, 550, color: t.separada ? p.mute : p.tinta, num: true),
              ),
            ),
            const SizedBox(width: 14),
            Btn(
              'Pagar',
              tam: TamBtn.xs,
              variante: VarBtn.dark,
              icono: Ic.truck,
              etiqueta: 'Pagar a ${prov.nombre}',
              onTap: c.sesionCajaId == null
                  ? null
                  : () async {
                      await pagarProveedorYAvisar(
                        context,
                        db: c.db,
                        usuarioId: c.usuarioId,
                        sesionCajaId: c.sesionCajaId!,
                        proveedorIdInicial: prov.id,
                      );
                      await c.cargarTodo();
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// `.sep-ck`: círculo con borde; separado = verde lleno con el tilde blanco (más apagado si ya está pagado).
class _Tilde extends StatelessWidget {
  const _Tilde({required this.marcado, required this.bloqueado});

  final bool marcado;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnimatedContainer(
      duration: ms(250),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: marcado ? p.g.withValues(alpha: bloqueado ? .5 : 1) : Colors.transparent,
        border: marcado ? null : Border.all(color: p.linea, width: 2),
      ),
      child: marcado ? Pop(valor: true, alMontar: true, child: const Icono(Ic.check, size: 20, color: Colors.white, grosor: 3)) : null,
    );
  }
}

// ─── Lo vendido (Ganancia, Semana, Mes) ────────────────────────────────────

class _VistaLoVendido extends StatelessWidget {
  const _VistaLoVendido();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final p = context.p;
    final vendidos = c.vendidosVisibles;
    final retiro = moduloActivo(Modulo.retiroGanancias);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filaDeBloques([
          _Bloque(titulo: 'Vendido', valor: c.vendidoCentavos, tipo: _EstiloBloque.negro),
          _Bloque(titulo: 'Reposición (costo)', valor: c.costoCentavos, tipo: _EstiloBloque.gris),
          _Bloque(
            titulo: 'Ganancia',
            valor: c.gananciaCentavos,
            tipo: _EstiloBloque.verde,
            pie: c.vendidoCentavos > 0 ? '${(c.gananciaCentavos * 100 / c.vendidoCentavos).round()} % de lo vendido' : null,
          ),
        ]),
        const SizedBox(height: 16),
        Row(
          children: [
            Sec('Por proveedor · ${c.nombrePeriodo}'),
            if (c.vendidoSinCostoCentavos > 0) ...[
              const SizedBox(width: 14),
              Flexible(
                child: _ChipSinCosto(
                  texto: '${pesos(c.vendidoSinCostoCentavos)} sin costo: no suman a la reposición',
                  onTap: () => _verSinCosto(context, c, desde: c.inicioDelPeriodo, periodo: c.nombrePeriodo),
                ),
              ),
            ],
            const Spacer(),
            if (retiro && MediaQuery.sizeOf(context).width >= 1500)
              Text('Tocá un proveedor para ver su ganancia sin revisar', style: estilo(14, 400, color: p.mute)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: vendidos.isEmpty
              ? Vacio(texto: c.busqueda.isEmpty ? 'Sin ventas en este período' : 'Ningún proveedor coincide con "${c.busqueda}"')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: Tabla(
                        columnas: const [
                          ColumnaTabla('Proveedor', flex: 4),
                          ColumnaTabla('Vendido', flex: 2, derecha: true),
                          ColumnaTabla('Costo', flex: 2, derecha: true),
                          ColumnaTabla('Ganancia', flex: 2, derecha: true),
                        ],
                        cantidad: vendidos.length,
                        onTapFila: retiro
                            ? (i) {
                                final prov = vendidos[i].proveedor;
                                if (prov != null) mostrarDialogoGananciaProveedor(context, controlador: c, proveedorId: prov.id);
                              }
                            : null,
                        celdas: (context, i) => _celdasVendido(context, c, vendidos[i]),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

List<Widget> _celdasVendido(BuildContext context, SeparacionesControlador c, SeparacionDelDia f) {
  final p = context.p;
  return [
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        celda(context, f.nombre, peso: 500),
        if (f.vendidoSinCostoCentavos > 0)
          Tocable(
            onTap: () => _verSinCosto(context, c, desde: c.inicioDelPeriodo, periodo: c.nombrePeriodo, soloProveedor: f.proveedor?.nombre),
            radio: 8,
            etiqueta: 'Ver lo vendido sin costo de ${f.nombre}',
            child: Text('incluye ${pesos(f.vendidoSinCostoCentavos)} sin costo · ver cuáles', style: estilo(13, 400, color: p.w)),
          ),
      ],
    ),
    celda(context, pesos(f.vendidoCentavos), num: true),
    celda(context, pesos(f.costoCentavos), num: true, color: p.mute),
    celda(context, pesos(f.gananciaCentavos), num: true, color: p.g, peso: 600),
  ];
}
