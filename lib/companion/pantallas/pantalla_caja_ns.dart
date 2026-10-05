// Caja, tal cual el mock (docs/03 B4): título con lupa y campana, un segmento
// Resumen · Separar · Ventas, y debajo el contenido de cada solapa. Todo sale de
// los datos reales de la caja abierta (esperados, separaciones del día, ventas).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../../ui/historial/devolucion_mp_dialogo.dart' show ofrecerDevolucionDeCobro;
import '../../ui/separaciones/separaciones_controlador.dart';
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../cliente_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../pantalla_cierres.dart';
import '../pantalla_separaciones_companion.dart';
import '../pantalla_movimiento_caja.dart';
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
                builder: (context, seg, _) => SegmentoNs(opciones: const ['Resumen', 'Separar', 'Ventas'], indice: seg, onCambio: (i) => app.segmentoCaja.value = i),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: app.segmentoCaja,
                builder: (context, seg, _) => switch (seg) {
                  0 => const _Resumen(),
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

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    return ChangeNotifierProvider<SeparacionesControlador>.value(
      value: c,
      child: Consumer<SeparacionesControlador>(
        builder: (context, c, _) {
          final tarjetas = c.tarjetas;
          final ef = c.separarEfectivoCentavos;
          final mp = c.separarMpCentavos;
          return ListView(
            padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, BarraInferiorNs.espacioReservado),
            children: [
              Text('Plata del día que tenés que apartar para pagarle a cada proveedor. Tocá uno cuando ya lo separaste.', style: estiloNs(15, altura: 1.4, color: ns.mute)),
              const SizedBox(height: 8),
              Text('Separá ${plataNs(ef + mp)} en total: ${plataNs(ef)} de efectivo y ${plataNs(mp)} de Mercado Pago.', style: estiloNs(15, peso: FontWeight.w600, altura: 1.4, color: ns.ink)),
              const SizedBox(height: 14),
              SeccionNs('${c.cantidadSeparadas} de ${tarjetas.length} separados'),
              const SizedBox(height: 10),
              if (tarjetas.isEmpty)
                Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Hoy no hay nada para separar', style: estiloNs(16, color: ns.mute)))
              else
                for (final t in tarjetas) ...[
                  Opacity(
                    opacity: t.separada ? 0.6 : 1,
                    child: PresionNs(
                      onTap: t.bloqueada || c.procesando.contains(t.proveedorId) ? null : () => c.alternar(t).then((_) => _app?.refrescar()),
                      etiqueta: t.fila.proveedor!.nombre,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.fromLTRB(18, 12, 22, 12),
                        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          children: [
                            CasillaNs(marcada: t.separada, tamanio: 30),
                            const SizedBox(width: 14),
                            Expanded(child: Text(t.fila.proveedor!.nombre, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
                            Text(plataNs(t.totalCentavos), style: estiloNs(20, peso: FontWeight.w500, track: -0.03, color: ns.ink, tabular: true)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              PresionNs(
                onTap: () => AppNs.of(context).irA((_) => PantallaSeparacionesCompanion(db: baseLocalCompanion(), usuarioId: AppNs.of(context).usuarioId ?? 0)),
                etiqueta: 'Ver lo vendido por proveedor',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: TokensNs.contorno, width: 1.5)),
                  child: Row(
                    children: [
                      Expanded(child: Text('Ver lo vendido por proveedor', style: estiloNs(16, peso: FontWeight.w600, color: ns.ink))),
                      IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.mute, grosor: 2.2),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Ventas ─────────────────────────

class _Ventas extends StatefulWidget {
  const _Ventas();

  @override
  State<_Ventas> createState() => _VentasState();
}

class _VentasState extends State<_Ventas> {
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

  bool _inicio = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inicio) {
      _inicio = true;
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
      final ventas = await servicio.historialDeVentas(desde: hoy, hasta: hoy.add(const Duration(days: 1)), filtroMedio: _filtro);
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
        titulo: '¿Eliminar la venta ${v.etiqueta}?',
        texto: 'Se descuenta de la caja y vuelve el stock.',
        bloques: [CampoNs(etiqueta: 'Motivo', controller: motivo, placeholder: 'Ej: error de carga')],
        botones: [
          BotonNs.peligroSolido(ctx, 'Eliminar venta', () {
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
      mostrarAvisoNs(context, 'Venta eliminada');
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
          FilaChipsNs(chips: [for (final f in _filtros) ChipNs(texto: f.$1, activo: _filtro == f.$2, onTap: () {
            setState(() => _filtro = f.$2);
            _cargar();
          })]),
          const SizedBox(height: 10),
          if (_cargando)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: margenNs), child: InfoNs(_error!, tono: TonoNs.bad))
          else if (_ventas.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: margenNs), child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Sin ventas hoy.', style: estiloNs(16, color: ns.mute))))
          else
            for (final v in _ventas)
              Padding(
                padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, 8),
                child: _FilaVenta(
                  venta: v,
                  medio: v.anulada ? 'Eliminada' : _medio(v.medio),
                  abierta: _abierta == v.ventaId,
                  detalle: _detalles[v.ventaId],
                  onTap: () => _alternar(v),
                  onEliminar: !v.anulada && v.sesionAbierta ? () => _eliminar(v) : null,
                ),
              ),
        ],
      ),
    );
  }
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
                            if (onEliminar != null) ...[
                              const SizedBox(height: 10),
                              BotonNs(texto: 'Eliminar esta venta', onTap: onEliminar, alto: 48, tamanio: 15, fondo: const Color(0x24FFFFFF), color: TokensNs.eliminarSobreOscuro),
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
