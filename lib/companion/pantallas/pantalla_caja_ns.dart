// Caja, tal cual el mock (docs/03 B4): título con lupa y campana, un segmento
// Resumen · Separar · Ventas, y debajo el contenido de cada solapa. Todo sale de
// los datos reales de la caja abierta (esperados, separaciones del día, ventas).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositorio_reposicion.dart' show SeparacionDelDia;
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../../domain/modulos.dart' show Modulo;
import '../../domain/periodo.dart' show PeriodoResumen;
import '../../servicios/modulos_activos.dart' show esNegocioDeServicios, moduloActivo;
import '../../ui/historial/devolucion_mp_dialogo.dart' show ofrecerDevolucionDeCobro;
import '../../ui/separaciones/separaciones_controlador.dart';
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../pantalla_cierres.dart';
import '../pantalla_movimiento_caja.dart';
import '../pantalla_pagar_proveedor.dart';
import '../puerto_local.dart';
import '../separaciones_extra_ns.dart';
import '../servicio_companion.dart';
import '../sync_nube_companion.dart' show syncNubeCompanion;
import 'hoja_abrir_caja_ns.dart';
import 'hoja_contar_caja_ns.dart';
import 'pantalla_buscador_ns.dart';
import 'pantalla_cierre_ns.dart';
import 'pantalla_notificaciones_ns.dart';

class PantallaCajaNs extends StatelessWidget {
  const PantallaCajaNs({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    return PantallaEntradaNs(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
              child: ListenableBuilder(
                listenable: app.pendientes,
                builder: (context, _) => Row(
                  children: [
                    Expanded(child: Text('Caja', style: tituloNs(42, color: ns.ink))),
                    BotonCircularNs(icono: IconoNs.lupa, onTap: () => app.irA((_) => const PantallaBuscadorNs(origen: PestaniaNs.caja)), etiqueta: 'Buscar una función o ajuste', tamanioIcono: 20),
                    const SizedBox(width: 8),
                    BotonCircularNs(
                      icono: IconoNs.campana,
                      onTap: () => app.irA((_) => const PantallaNotificacionesNs()),
                      etiqueta: app.pendientes.value.cantidad == 0 ? 'Notificaciones' : '${app.pendientes.value.cantidad} notificaciones',
                      globo: app.pendientes.value.cantidad,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: margenNs),
              child: ValueListenableBuilder<int>(
                valueListenable: app.segmentoCaja,
                // Un negocio de servicios no separa para proveedores (mock de servicios: Caja queda en Resumen y Ventas). El valor
                // del segmento sigue siendo 0 Resumen, 1 Separar, 2 Ventas para todos.
                builder: (context, seg, _) => esNegocioDeServicios()
                    ? SegmentoNs(opciones: const ['Resumen', 'Ventas'], indice: seg == 2 ? 1 : 0, onCambio: (i) => app.segmentoCaja.value = i == 1 ? 2 : 0)
                    : SegmentoNs(opciones: const ['Resumen', 'Separar', 'Ventas'], indice: seg, onCambio: (i) => app.segmentoCaja.value = i),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: app.segmentoCaja,
                builder: (context, seg, _) => switch (seg) {
                  0 => const _Resumen(),
                  1 when esNegocioDeServicios() => const _Resumen(),
                  1 => const _Separar(),
                  _ => const _Ventas(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Resumen ─────────────────────────

class _Resumen extends StatefulWidget {
  const _Resumen();

  @override
  State<_Resumen> createState() => _ResumenState();
}

class _ResumenState extends State<_Resumen> {
  EstadoArqueoIntermedioCompanion? _esperados;
  int _versionSesion = -1;

  Future<void> _cargarEsperados(ControladorAppNs app) async {
    if (!app.cajaAbierta || app.servicio == null) {
      if (_esperados != null) setState(() => _esperados = null);
      return;
    }
    try {
      final e = await app.servicio!.calcularArqueoIntermedio(efectivoContadoCentavos: 0);
      if (mounted) setState(() => _esperados = e);
    } catch (_) {
      // Sin esperados todavía: quedan en cero.
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    // Vuelve a pedir lo esperado cuando cambia la caja (venta, gasto, apertura).
    final marca = (app.estadoCaja?.efectivoEsperadoCentavos ?? -1) * 31 + (app.cajaAbierta ? 1 : 0) + (app.estadoCaja?.cantidadVentas ?? 0) * 7;
    if (marca != _versionSesion) {
      _versionSesion = marca;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _cargarEsperados(app) : null);
    }
    final abierta = app.cajaAbierta;
    final efectivo = app.estadoCaja?.efectivoEsperadoCentavos ?? 0;
    final mp = app.estadoCaja?.mpEsperadoCentavos ?? 0;
    final lata = _esperados?.lataEsperadoCentavos ?? app.estadoCaja?.lataInicialCentavos ?? 0;
    return ListenableBuilder(
      listenable: Listenable.merge([app.pendientes, app.datosDia]),
      builder: (context, _) {
        final dia = app.datosDia.value;
        final pend = app.pendientes.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado),
          children: [
            HeroNs(
              radio: 34,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Efectivo que tendría que haber en el cajón', style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
                  const SizedBox(height: 6),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(plataNs(efectivo), style: tituloNs(50, track: -0.06, altura: 1.02, color: TokensNs.blanco))),
                  const SizedBox(height: 14),
                  BotonNs(
                    texto: abierta ? 'Cerrar caja' : 'Abrir caja',
                    onTap: () => abierta ? _cerrar(context, app) : _abrir(context, app),
                    alto: 52,
                    tamanio: 16,
                    fondo: ns.paper,
                    color: ns.ink,
                    rellenar: false,
                    paddingH: 28,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Accion(icono: IconoNs.intercambio, titulo: 'Gasto o ingreso', detalle: 'Plata que sale o entra', onTap: () => app.irA((_) => const PantallaMovimientoCaja()))),
                const SizedBox(width: 10),
                Expanded(
                  child: _Accion(
                    icono: IconoNs.calculadora,
                    titulo: 'Contar la caja',
                    detalle: !abierta ? 'Caja cerrada' : (pend.arqueoVencido ? 'Hace ${duracionTextoNs(pend.minutosDesdeConteo)}' : 'Sin cerrar el día'),
                    ambar: abierta && pend.arqueoVencido,
                    onTap: () => _contar(context, app),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SeccionNs('Lo que tendría que haber'),
            const SizedBox(height: 10),
            _Bloque(filas: [
              FilaClaveValorNs(clave: 'Efectivo', valor: plataNs(efectivo)),
              FilaClaveValorNs(clave: 'Mercado Pago', valor: plataNs(mp)),
              FilaClaveValorNs(clave: 'Lata de cigarrillos', valor: plataNs(lata)),
            ]),
            const SizedBox(height: 22),
            const SeccionNs('Cómo va el día'),
            const SizedBox(height: 10),
            _Bloque(filas: [
              FilaClaveValorNs(clave: 'Vendido', valor: plataNs(dia.vendidoCentavos)),
              FilaClaveValorNs(clave: 'Ganancia', valor: plataNs(dia.gananciaCentavos), colorValor: ns.g),
              FilaClaveValorNs(clave: 'Por separar', valor: plataNs(pend.faltaSepararCentavos), colorValor: ns.w),
              FilaClaveValorNs(clave: 'Ventas registradas', valor: '${dia.ventas}'),
            ]),
            const SizedBox(height: 14),
            PresionNs(
              onTap: () => app.irA((_) => const PaginaCierresAnteriores()),
              etiqueta: 'Ver cierres anteriores',
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: TokensNs.contorno, width: 1.5)),
                child: Row(
                  children: [
                    Expanded(child: Text('Ver cierres anteriores', style: estiloNs(16, peso: FontWeight.w600, color: ns.ink))),
                    IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.mute, grosor: 2.2),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _abrir(BuildContext context, ControladorAppNs app) async {
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    await mostrarHojaAbrirCaja(context, servicio: s, usuarioId: u);
    await app.refrescar();
  }

  Future<void> _cerrar(BuildContext context, ControladorAppNs app) async {
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    final cerro = await app.irA<bool>(
      (_) => PantallaCierreNs(
        servicio: s,
        usuarioId: u,
        precargaEfectivoCentavos: app.sesion?.ultimoArqueoEfectivoCentavos,
        precargaMpCentavos: app.sesion?.ultimoArqueoMpCentavos,
        horaPrecarga: app.sesion?.fechaUltimoArqueoIntermedio,
      ),
    );
    if (cerro == true) await app.refrescar();
  }

  Future<void> _contar(BuildContext context, ControladorAppNs app) async {
    final s = app.servicio;
    final u = app.usuarioId;
    if (s == null || u == null) return;
    await mostrarHojaContarCaja(context, servicio: s, usuarioId: u);
    await app.refrescar();
  }
}

class _Accion extends StatelessWidget {
  const _Accion({required this.icono, required this.titulo, required this.detalle, required this.onTap, this.ambar = false});
  final bool ambar;
  final IconoNs icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: titulo,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: ambar ? ns.wbg : ns.s, borderRadius: BorderRadius.circular(26)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(icono, tamanio: 20, color: ambar ? ns.w : ns.ink)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titulo, style: estiloNs(15, peso: FontWeight.w600, track: -0.015, altura: 1.15, color: ambar ? ns.w : ns.ink)),
                  const SizedBox(height: 2),
                  Text(detalle, style: estiloNs(12, altura: 1.25, color: ambar ? ns.w : ns.mute)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloque `s` con filas clave/valor y la línea fina entre ellas (padding 4/20).
class _Bloque extends StatelessWidget {
  const _Bloque({required this.filas});
  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(color: context.ns.s, borderRadius: BorderRadius.circular(28)),
      child: Column(children: filas),
    );
  }
}

// ───────────────────────── Separar ─────────────────────────

class _Separar extends StatefulWidget {
  const _Separar();

  @override
  State<_Separar> createState() => _SepararState();
}

class _SepararState extends State<_Separar> {
  SeparacionesControlador? _c;
  StreamSubscription<void>? _avisos;
  int? _sesionId;
  ControladorAppNs? _app;

  Future<void> _iniciar(ControladorAppNs app) async {
    _app = app;
    final usuario = app.usuarioId;
    if (usuario == null) return;
    final db = baseLocalCompanion();
    final sesion = await sesionAbierta(db);
    final c = SeparacionesControlador(db, usuarioId: usuario, sesionCajaId: sesion?.id);
    await c.cargarTodo();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() {
      _c?.dispose();
      _c = c;
      _sesionId = sesion?.id;
    });
    _avisos ??= avisosCambiosCompanion.listen((_) {
      _c?.cargarTodo().then((_) => _app?.refrescar());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppNs.of(context);
    if (_c == null || _sesionId != app.sesion?.id) _iniciar(app);
  }

  @override
  void dispose() {
    _avisos?.cancel();
    _c?.dispose();
    super.dispose();
  }

  /// `90.000`, sin el `$`: las cifras chicas de "Efectivo 90.000 · MP 52.600".
  static String _sinSigno(int centavos) => plataNs(centavos).replaceFirst(RegExp(r'^\$\s?'), '');

  bool _vendido = false;

  Future<void> _pagar(int proveedorId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PantallaPagarProveedor(servicio: PuertoLocal(baseLocalCompanion()), proveedorId: proveedorId)),
    );
    await _c?.cargarTodo();
    _app?.refrescar();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<SeparacionesControlador>.value(
      value: c,
      child: Consumer<SeparacionesControlador>(
        builder: (context, c, _) {
          final ef = c.separarEfectivoCentavos;
          final mp = c.separarMpCentavos;
          return ListView(
            padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado),
            children: [
              _heroSeparar(context, c, ef, mp),
              if (c.reservaDiariaCentavos != null) ...[
                const SizedBox(height: 10),
                // Solo informativa, como en la PC: lo que conviene apartar por día para los fijos.
                InfoNs('Reserva diaria de fijos: ${plataNs(c.reservaDiariaCentavos!)}', tono: TonoNs.warn),
              ],
              if (moduloActivo(Modulo.retiroGanancias)) ...[
                const SizedBox(height: 10),
                BotonNs.secundario(context, 'Retirar plata', () => mostrarRetirarPlataNs(context, c).then((_) => _app?.refrescar()), icono: IconoNs.billetes),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  ChipNs(texto: 'Qué separar', activo: !_vendido, onTap: () => setState(() => _vendido = false)),
                  const SizedBox(width: 8),
                  ChipNs(texto: 'Lo vendido', activo: _vendido, onTap: () => setState(() => _vendido = true)),
                ],
              ),
              const SizedBox(height: 10),
              if (_vendido) ..._lVendido(context, c) else ..._queSeparar(context, c),
            ],
          );
        },
      ),
    );
  }

  Widget _heroSeparar(BuildContext context, SeparacionesControlador c, int ef, int mp) {
    final blanco85 = estiloNs(14, color: const Color(0xD9FFFFFF));
    Widget fila(Color punto, String texto, int valor) => Row(
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: punto, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: blanco85)),
        Text(plataNs(valor), style: estiloNs(14, peso: FontWeight.w700, color: TokensNs.blanco, tabular: true)),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: HeroNs(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Separar para proveedores · hoy', style: estiloNs(14, peso: FontWeight.w500, color: const Color(0xD9FFFFFF))),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(plataNs(ef + mp), style: tituloNs(50, track: -0.06, altura: 1.02, color: TokensNs.blanco))),
            const SizedBox(height: 8),
            fila(const Color(0xFFFF8A3D), 'De efectivo', ef),
            const SizedBox(height: 6),
            fila(const Color(0xFF3B6CFF), 'De Mercado Pago', mp),
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, thickness: 1, color: Color(0x38FFFFFF))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(TextSpan(style: blanco85, children: [const TextSpan(text: 'Cobrado '), TextSpan(text: plataNs(c.cobrado.efectivoCentavos + c.cobrado.mpCentavos), style: estiloNs(14, peso: FontWeight.w700, color: TokensNs.blanco, tabular: true))])),
                Text.rich(TextSpan(style: blanco85, children: [const TextSpan(text: 'Te queda '), TextSpan(text: plataNs(c.quedaEfectivoCentavos + c.quedaMpCentavos), style: estiloNs(14, peso: FontWeight.w700, color: const Color(0xFF63D9B0), tabular: true))])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _queSeparar(BuildContext context, SeparacionesControlador c) {
    final ns = context.ns;
    final tarjetas = c.tarjetas;
    return [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('Plata del día que tenés que apartar para pagarle a cada proveedor. Tocá uno cuando ya lo separaste.', style: estiloNs(15, altura: 1.4, color: ns.mute))),
      const SizedBox(height: 10),
      if (c.vendidoSinCostoHoyCentavos > 0) ...[
        PresionNs(
          onTap: () => mostrarSinCostoNs(context, c, desde: c.inicioDeHoy, periodo: 'hoy'),
          etiqueta: 'Ver lo vendido sin costo',
          child: InfoNs('${plataNs(c.vendidoSinCostoHoyCentavos)} vendidos hoy sin costo: no se sabe cuánto separar. Tocá para ver cuáles.', tono: TonoNs.warn, icono: IconoNs.alerta),
        ),
        const SizedBox(height: 10),
      ],
      SeccionNs('${c.cantidadSeparadas} de ${tarjetas.length} separados'),
      const SizedBox(height: 10),
      if (tarjetas.isEmpty)
        Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Hoy no hay nada para separar', style: estiloNs(16, color: ns.mute)))
      else
        for (final t in tarjetas) ...[
          PresionNs(
            onTap: t.bloqueada || c.procesando.contains(t.proveedorId) ? null : () => c.alternar(t).then((_) => _app?.refrescar()),
            etiqueta: t.fila.proveedor!.nombre,
            child: Semantics(
              checked: t.separada,
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.fromLTRB(18, 12, 22, 12),
                decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(32)),
                child: Row(
                  children: [
                    CasillaNs(marcada: t.separada, tamanio: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.fila.proveedor!.nombre, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                          Text('Efectivo ${_sinSigno(t.efectivoCentavos)} · MP ${_sinSigno(t.mpCentavos)}', style: estiloNs(13, altura: 1.25, color: ns.mute, tabular: true)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(plataNs(t.totalCentavos), style: estiloNs(20, peso: peso450, track: -0.03, color: ns.ink, tabular: true)),
                        const SizedBox(height: 4),
                        // El pago rápido con el proveedor ya elegido, como la fila de la PC.
                        BotonNs(texto: 'Pagar', onTap: () => _pagar(t.proveedorId), alto: 34, tamanio: 13, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
    ];
  }

  List<Widget> _lVendido(BuildContext context, SeparacionesControlador c) {
    final ns = context.ns;
    final periodos = [(PeriodoResumen.hoy, 'Hoy'), (PeriodoResumen.semana, 'Semana'), (PeriodoResumen.mes, 'Mes')];
    final texto = switch (c.periodo) {
      PeriodoResumen.hoy => 'Lo que vendiste a cada proveedor hoy. Lo vendido sin costo cargado suma a lo vendido, pero no al costo ni a la ganancia.',
      PeriodoResumen.semana => 'Lo que vendiste a cada proveedor en la semana, desde el lunes. Lo vendido sin costo cargado suma a lo vendido, pero no al costo ni a la ganancia.',
      PeriodoResumen.mes => 'Lo que vendiste a cada proveedor en el mes, desde el día 1. Lo vendido sin costo cargado suma a lo vendido, pero no al costo ni a la ganancia.',
      _ => 'Lo que vendiste a cada proveedor desde el último pago. Lo vendido sin costo cargado suma a lo vendido, pero no al costo ni a la ganancia.',
    };
    return [
      Row(
        children: [
          for (final (p, l) in periodos) ...[
            ChipNs(texto: l, activo: c.periodo == p, onTap: () => c.cambiarPeriodo(p)),
            const SizedBox(width: 8),
          ],
        ],
      ),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(texto, style: estiloNs(14, altura: 1.4, color: ns.mute))),
      const SizedBox(height: 10),
      if (c.vendidoSinCostoCentavos > 0) ...[
        PresionNs(
          onTap: () => mostrarSinCostoNs(context, c, desde: c.inicioDelPeriodo, periodo: c.nombrePeriodo),
          etiqueta: 'Ver lo vendido sin costo',
          child: InfoNs('${plataNs(c.vendidoSinCostoCentavos)} sin costo: no suman a la reposición. Tocá para ver cuáles.', tono: TonoNs.warn, icono: IconoNs.alerta),
        ),
        const SizedBox(height: 10),
      ],
      if (c.vendidos.isNotEmpty && moduloActivo(Modulo.retiroGanancias)) ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('Tocá un proveedor para ver su ganancia sin revisar.', style: estiloNs(14, color: ns.mute))),
        const SizedBox(height: 10),
      ],
      if (c.vendidos.isEmpty)
        Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Todavía no hay ventas en este período', style: estiloNs(16, color: ns.mute)))
      else
        for (final f in c.vendidos) ...[
          _TarjetaVendidoNs(
            fila: f,
            onTap: f.proveedor == null || !moduloActivo(Modulo.retiroGanancias) ? null : () => mostrarGananciaProveedorNs(context, c, f.proveedor!.id).then((_) => _app?.refrescar()),
            onSinCosto: f.vendidoSinCostoCentavos <= 0
                ? null
                : () => mostrarSinCostoNs(context, c, desde: c.inicioDelPeriodo, periodo: c.nombrePeriodo, soloProveedor: f.nombre),
          ),
          const SizedBox(height: 8),
        ],
    ];
  }
}

class _TarjetaVendidoNs extends StatelessWidget {
  const _TarjetaVendidoNs({required this.fila, this.onTap, this.onSinCosto});
  final SeparacionDelDia fila;

  /// Abre la ganancia sin revisar del proveedor (retener o retirar).
  final VoidCallback? onTap;

  /// "incluye $X sin costo · ver cuáles".
  final VoidCallback? onSinCosto;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final conCosto = fila.vendidoCentavos - fila.vendidoSinCostoCentavos;
    Widget caja(String etiqueta, int valor, {Color? color}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: estiloNs(12, color: ns.mute)),
            Text(plataNs(valor), style: estiloNs(17, peso: FontWeight.w600, color: color ?? ns.ink, tabular: true)),
          ],
        ),
      ),
    );
    final tarjeta = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(fila.nombre, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
              if (conCosto > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: ns.gbg, borderRadius: BorderRadius.circular(999)),
                  child: Text('${(fila.gananciaCentavos * 100 / conCosto).round()} %', style: estiloNs(13, peso: FontWeight.w700, color: ns.g)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Vendido', style: estiloNs(13, color: ns.mute)),
          Text(plataNs(fila.vendidoCentavos), style: tituloNs(34, track: -0.05, altura: 1.05, color: ns.ink)),
          const SizedBox(height: 10),
          Row(children: [caja('Costo', fila.costoCentavos), const SizedBox(width: 8), caja('Ganancia', fila.gananciaCentavos, color: ns.g)]),
          if (onSinCosto != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onSinCosto,
              child: Text('incluye ${plataNs(fila.vendidoSinCostoCentavos)} sin costo · ver cuáles', style: estiloNs(13, color: ns.w).copyWith(decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
    return onTap == null ? tarjeta : PresionNs(onTap: onTap, etiqueta: 'Ganancia de ${fila.nombre}', child: tarjeta);
  }
}

// ───────────────────────── Ventas ─────────────────────────

class _Ventas extends StatefulWidget {
  const _Ventas();

  @override
  State<_Ventas> createState() => _VentasState();
}

class _VentasState extends State<_Ventas> {
  _Periodo _periodo = _Periodo.hoy;
  MedioVentaHistorialCompanion? _filtro;
  List<VentaDelHistorialCompanion> _ventas = [];
  bool _cargando = true;
  String? _error;
  int? _abierta;
  final Map<int, DetalleVentaCompanion> _detalles = {};
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = avisosCambiosCompanion.listen((_) => _cargar(silencioso: true));
  }

  ServicioCompanion? _servicioCargado;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final servicio = AppNs.of(context).servicio;
    if (servicio != null && !identical(servicio, _servicioCargado)) {
      _servicioCargado = servicio;
      _cargar();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final servicio = AppNs.of(context).servicio;
    if (servicio == null) return;
    if (!silencioso) setState(() => _cargando = true);
    try {
      final ahora = DateTime.now();
      final hoy = DateTime(ahora.year, ahora.month, ahora.day);
      final (desde, hasta) = switch (_periodo) {
        _Periodo.hoy => (hoy, hoy.add(const Duration(days: 1))),
        _Periodo.ayer => (hoy.subtract(const Duration(days: 1)), hoy),
        _Periodo.sieteDias => (hoy.subtract(const Duration(days: 6)), hoy.add(const Duration(days: 1))),
        _Periodo.mes => (DateTime(hoy.year, hoy.month), hoy.add(const Duration(days: 1))),
      };
      final ventas = await servicio.historialDeVentas(desde: desde, hasta: hasta, filtroMedio: _filtro);
      if (mounted) {
        setState(() {
          _ventas = ventas;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  Future<void> _alternar(VentaDelHistorialCompanion v) async {
    if (v.anulada) return;
    if (_abierta == v.ventaId) {
      setState(() => _abierta = null);
      return;
    }
    setState(() => _abierta = v.ventaId);
    if (_detalles.containsKey(v.ventaId)) return;
    try {
      final d = await AppNs.of(context).servicio!.detalleVenta(v.ventaId);
      if (mounted) setState(() => _detalles[v.ventaId] = d);
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e));
    }
  }

  Future<bool?> _preguntarDevolucion(BuildContext context, String monto) => mostrarHojaNs<bool>(
    context,
    builder: (ctx) => HojaNs(
      titulo: '¿Devolver $monto por Mercado Pago?',
      texto: 'Esta venta se cobró con la terminal. La plata vuelve al cliente por Mercado Pago.',
      botones: [
        BotonNs.primario(ctx, 'Sí, devolver', () => Navigator.of(ctx).pop(true)),
        BotonNs.secundario(ctx, 'No', () => Navigator.of(ctx).pop(false)),
      ],
    ),
  );

  Future<void> _eliminar(VentaDelHistorialCompanion v) async {
    final app = AppNs.of(context);
    final motivo = TextEditingController();
    final confirmado = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Anular la venta de ${plataNs(v.totalCentavos)}?',
        texto: 'Se repone el stock y se revierte la caja. La venta sigue viéndose acá, marcada como anulada.',
        bloques: [CampoNs(etiqueta: 'Motivo', controller: motivo, placeholder: 'Ej: error de carga')],
        botones: [
          BotonNs.peligroSolido(ctx, 'Anular', () {
            if (motivo.text.trim().isEmpty) {
              mostrarAvisoNs(ctx, 'Escribí el motivo');
              return;
            }
            Navigator.of(ctx).pop(true);
          }),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    final texto = motivo.text.trim();
    motivo.dispose();
    if (confirmado != true || !mounted) return;
    final servicio = app.servicio;
    final usuario = app.usuarioId;
    if (servicio == null || usuario == null) return;
    try {
      await servicio.anularVenta(ventaId: v.ventaId, usuarioId: usuario, motivo: texto);
      if (!mounted) return;
      mostrarAvisoNs(context, 'Venta anulada');
      setState(() => _abierta = null);
      await _cargar();
      await app.refrescar();
      // Si se cobró con la Point y quien vinculó este celular puede devolver, se ofrece.
      final cobro = await servicio.cobroPointDeVenta(v.ventaId);
      if (mounted) {
        await ofrecerDevolucionDeCobro(context, cobro, almacen: syncNubeCompanion?.almacen, cliente: syncNubeCompanion?.cliente, preguntar: _preguntarDevolucion);
      }
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
    }
  }

  static const _filtros = <(String, MedioVentaHistorialCompanion?)>[
    ('Todos los medios', null),
    ('Efectivo', MedioVentaHistorialCompanion.efectivo),
    ('QR', MedioVentaHistorialCompanion.qr),
    ('Débito', MedioVentaHistorialCompanion.debitCard),
    ('Crédito', MedioVentaHistorialCompanion.creditCard),
    ('Mixto', MedioVentaHistorialCompanion.mixto),
  ];

  static String _medio(MedioVentaHistorialCompanion m) => switch (m) {
    MedioVentaHistorialCompanion.efectivo => 'Efectivo',
    MedioVentaHistorialCompanion.qr => 'QR',
    MedioVentaHistorialCompanion.debitCard => 'Débito',
    MedioVentaHistorialCompanion.creditCard => 'Crédito',
    MedioVentaHistorialCompanion.mixto => 'Mixto',
  };

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final vigentes = _ventas.where((v) => !v.anulada);
    final total = vigentes.fold<int>(0, (a, v) => a + v.totalCentavos);
    return RefreshIndicator(
      onRefresh: _cargar,
      color: ns.ink,
      backgroundColor: ns.paper,
      child: ListView(
        padding: const EdgeInsets.only(bottom: BarraInferiorNs.espacioReservado),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: margenNs),
            child: Text('${vigentes.length} ${vigentes.length == 1 ? 'venta' : 'ventas'} · ${plataNs(total)}', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute, tabular: true)),
          ),
          const SizedBox(height: 10),
          FilaChipsNs(chips: [for (final p in _Periodo.values) ChipNs(texto: p.texto, activo: _periodo == p, onTap: () {
            setState(() {
              _periodo = p;
              _abierta = null;
            });
            _cargar();
          })]),
          const SizedBox(height: 10),
          FilaChipsNs(chips: [for (final f in _filtros) ChipNs(texto: f.$1, activo: _filtro == f.$2, onTap: () {
            setState(() => _filtro = f.$2);
            _cargar();
          })]),
          const SizedBox(height: 10),
          if (_cargando)
            const Padding(padding: EdgeInsets.symmetric(horizontal: margenNs), child: EsqueletoListaNs(filas: 6, alto: 64))
          else if (_error != null)
            EstadoErrorNs(texto: _error!, onReintentar: _cargar)
          else if (_ventas.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: margenNs), child: Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Sin ventas en este período', style: estiloNs(16, color: ns.mute))))
          else
            for (var i = 0; i < _ventas.length; i++) ...[
              if (i == 0 || !_mismoDia(_ventas[i - 1].fecha, _ventas[i].fecha))
                Padding(padding: const EdgeInsets.fromLTRB(margenNs + 6, 10, margenNs, 10), child: Text(_tituloDia(_ventas[i].fecha), style: estiloNs(18, peso: FontWeight.w600, track: -0.02, color: ns.ink))),
              Padding(
                padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, 10),
                child: _FilaVenta(
                  venta: _ventas[i],
                  medio: _ventas[i].anulada ? 'Anulada' : _medio(_ventas[i].medio),
                  abierta: _abierta == _ventas[i].ventaId,
                  detalle: _detalles[_ventas[i].ventaId],
                  onTap: () => _alternar(_ventas[i]),
                  onEliminar: !_ventas[i].anulada && _ventas[i].sesionAbierta && AppNs.of(context).cajaAbierta ? () => _eliminar(_ventas[i]) : null,
                ),
              ),
            ],
        ],
      ),
    );
  }

  static bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _tituloDia(DateTime f) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(f.year, f.month, f.day);
    if (dia == hoy) return 'Hoy';
    if (dia == hoy.subtract(const Duration(days: 1))) return 'Ayer';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}';
  }
}

/// Qué días mira el historial (pastillas, no desplegable).
enum _Periodo {
  hoy('Hoy'),
  ayer('Ayer'),
  sieteDias('Últimos 7 días'),
  mes('Este mes');

  const _Periodo(this.texto);
  final String texto;
}

class _FilaVenta extends StatelessWidget {
  const _FilaVenta({required this.venta, required this.medio, required this.abierta, required this.detalle, required this.onTap, required this.onEliminar});
  final VentaDelHistorialCompanion venta;
  final String medio;
  final bool abierta;
  final DetalleVentaCompanion? detalle;
  final VoidCallback onTap;
  final VoidCallback? onEliminar;

  String _hora(DateTime f) => '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  static String _fechaHoraNs(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
  }

  static Widget _filaDetalle(String clave, String valor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(clave, style: estiloNs(14, color: const Color(0xDBFFFFFF)))),
        Text(valor, style: estiloNs(14, color: const Color(0xDBFFFFFF), tabular: true)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final v = venta;
    final texto = abierta ? TokensNs.blanco : ns.ink;
    final apagado = abierta ? const Color(0xB8FFFFFF) : ns.mute;
    final tachado = v.anulada ? TextDecoration.lineThrough : null;
    return Opacity(
      opacity: v.anulada ? 0.6 : 1,
      child: Semantics(
        expanded: abierta,
        child: Container(
          decoration: BoxDecoration(color: abierta ? ns.prim : ns.s, borderRadius: BorderRadius.circular(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PresionNs(
                onTap: v.anulada ? null : onTap,
                etiqueta: 'Venta ${v.etiqueta}',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 62, child: Text(_hora(v.fecha), style: estiloNs(21, peso: peso450, track: -0.03, color: texto, tabular: true, decoracion: tachado))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Venta ${v.etiqueta}', style: estiloNs(16, peso: FontWeight.w500, color: texto, decoracion: tachado)),
                            Text(medio, style: estiloNs(14, color: apagado)),
                          ],
                        ),
                      ),
                      Text(plataNs(v.totalCentavos), style: estiloNs(21, peso: peso450, track: -0.03, color: texto, tabular: true, decoracion: tachado)),
                    ],
                  ),
                ),
              ),
              if (abierta)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: detalle == null
                      ? const Center(child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: TokensNs.blanco))))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${_fechaHoraNs(detalle!.fecha)} · ${detalle!.vendedor}', style: estiloNs(13, color: const Color(0xB3FFFFFF)))),
                            for (final l in detalle!.lineas)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(l.gramos != null ? '${l.gramos} g × ${l.nombreProducto}' : '${l.cantidad} × ${l.nombreProducto}', style: estiloNs(14, color: const Color(0xDBFFFFFF)))),
                                    Text(plataNs(l.subtotalCentavos), style: estiloNs(14, color: const Color(0xDBFFFFFF), tabular: true)),
                                  ],
                                ),
                              ),
                            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, thickness: 1, color: Color(0x38FFFFFF))),
                            _filaDetalle('Subtotal', plataNs(detalle!.subtotalCentavos)),
                            if (detalle!.recargoCigarrillosCentavos != 0) _filaDetalle('Recargo cigarrillos', plataNs(detalle!.recargoCigarrillosCentavos)),
                            if (detalle!.descuentoCentavos != 0) _filaDetalle('Descuento', '-${plataNs(detalle!.descuentoCentavos)}'),
                            if (detalle!.redondeoCentavos != 0) _filaDetalle('Redondeo', '${detalle!.redondeoCentavos < 0 ? '-' : ''}${plataNs(detalle!.redondeoCentavos.abs())}'),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Expanded(child: Text('Total', style: estiloNs(16, peso: FontWeight.w700, color: TokensNs.blanco))),
                                  Text(plataNs(detalle!.totalCentavos), style: estiloNs(16, peso: FontWeight.w700, color: TokensNs.blanco, tabular: true)),
                                ],
                              ),
                            ),
                            if (onEliminar != null) ...[
                              const SizedBox(height: 10),
                              BotonNs(texto: 'Anular venta', onTap: onEliminar, alto: 48, tamanio: 15, fondo: const Color(0x24FFFFFF), color: TokensNs.eliminarSobreOscuro),
                            ],
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
