// Proveedores en el celular (El dueño, 2026-10-09: "simple para no agobiar, pero que no queden datos importantes sin poder
// llenar, por ej. un proveedor"). Un solo lugar para todo lo del proveedor, que antes estaba repartido en tres filas de
// "Más" (Cuenta corriente, Pagar proveedor, Cargar factura): la lista con lo que le debés a cada uno, el alta y la
// edición (antes solo se podían cargar en la PC), y la ficha de cada proveedor con sus datos, "Pedir por WhatsApp" y
// su cuenta corriente (cargos y pagos, cargar deuda, pagar, anular y deshacer una factura aplicada).
//
// Las reglas viven en `data/repositorio_deuda_proveedores.dart`, `data/repositorio_facturas_compra.dart` y
// `data/repositorio_reposicion.dart` (alta y edición, las mismas de la PC); acá solo se dibuja. Sobre la base del celular:
// los proveedores se sincronizan siempre y la cuenta corriente desde la v61, así que lo que se carga acá llega a la PC.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/repositorio_configuracion.dart' show configuracionNegocioActual;
import '../data/repositorio_deuda_proveedores.dart';
import '../data/repositorio_facturas_compra.dart';
import '../data/repositorio_reposicion.dart' show lineasParaPedirAProveedor;
import '../domain/dinero.dart';
import '../domain/pedido_whatsapp.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'pantalla_cargar_factura.dart';
import 'pantalla_formulario_proveedor.dart';
import 'pantalla_pagar_proveedor.dart';
import 'puerto_local.dart';

String _fecha(DateTime f) => '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

/// "Pide martes · Entrega jueves", o null si no tiene días cargados.
String? _dias(Proveedor p) {
  final partes = [
    if (p.diaPedido != null && p.diaPedido!.trim().isNotEmpty) 'Pide ${p.diaPedido!.trim().toLowerCase()}',
    if (p.diaEntrega != null && p.diaEntrega!.trim().isNotEmpty) 'Entrega ${p.diaEntrega!.trim().toLowerCase()}',
  ];
  return partes.isEmpty ? null : partes.join(' · ');
}

/// Los tests lo reemplazan para no abrir WhatsApp de verdad.
@visibleForTesting
Future<bool> Function(Uri url)? abrirUrlParaTestsNs;

/// Todos los proveedores (primero los que tienen deuda, de mayor a menor), con el total arriba, "+ Nuevo", cargar una
/// factura y pagar. Los dados de baja van al final, aparte.
class PantallaProveedores extends StatefulWidget {
  /// [db] y [usuarioId] son para tests.
  const PantallaProveedores({super.key, this.db, this.usuarioId});

  final AppDatabase? db;
  final int? usuarioId;

  @override
  State<PantallaProveedores> createState() => _PantallaProveedoresState();
}

class _PantallaProveedoresState extends State<PantallaProveedores> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<({Proveedor proveedor, int saldo})>? _filas;
  bool _soloConDeuda = false;
  final _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _recargar() async {
    final saldos = await saldosDeuda(_db);
    final proveedores = await _db.select(_db.proveedores).get();
    final filas = [for (final p in proveedores) (proveedor: p, saldo: saldos[p.id] ?? 0)]
      ..sort((a, b) => a.saldo != b.saldo ? b.saldo.compareTo(a.saldo) : a.proveedor.nombre.toLowerCase().compareTo(b.proveedor.nombre.toLowerCase()));
    if (mounted) setState(() => _filas = filas);
  }

  Future<void> _ir(Widget pantalla) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pantalla));
    await _recargar();
  }

  Future<void> _abrir(Proveedor p) => _ir(PantallaProveedor(db: _db, proveedor: p, usuarioId: widget.usuarioId));

  Future<void> _nuevo() async {
    final id = await abrirFormularioProveedor(context, db: _db);
    await _recargar();
    if (id == null || !mounted) return;
    final creado = _filas?.where((f) => f.proveedor.id == id).firstOrNull;
    if (creado != null) await _abrir(creado.proveedor);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final filas = _filas;
    final total = filas?.fold<int>(0, (a, f) => a + (f.saldo > 0 ? f.saldo : 0)) ?? 0;
    final texto = _buscar.text.trim().toLowerCase();
    bool pasa(({Proveedor proveedor, int saldo}) f) =>
        (!_soloConDeuda || f.saldo != 0) && (texto.isEmpty || f.proveedor.nombre.toLowerCase().contains(texto));
    final activos = [for (final f in filas ?? const <({Proveedor proveedor, int saldo})>[]) if (f.proveedor.activo && pasa(f)) f];
    final deBaja = [for (final f in filas ?? const <({Proveedor proveedor, int saldo})>[]) if (!f.proveedor.activo && pasa(f)) f];
    return PaginaNs(
      titulo: 'Proveedores',
      derecha: BotonNs(texto: '+ Nuevo', onTap: _nuevo, alto: 44, tamanio: 15, fondo: ns.prim, color: TokensNs.blanco, rellenar: false, paddingH: 20),
      cuerpo: filas == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _Saldo(etiqueta: total > 0 ? 'Les debés en total' : 'No le debés a nadie', saldo: total),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: BotonNs.secundario(context, 'Cargar factura', () => _ir(PantallaCargarFactura(db: widget.db, usuarioId: widget.usuarioId)), icono: IconoNs.camara)),
                    const SizedBox(width: 8),
                    Expanded(child: BotonNs.secundario(context, 'Pagar', () => _ir(PantallaPagarProveedor(servicio: PuertoLocal(_db))), icono: IconoNs.billetera)),
                  ],
                ),
                const SizedBox(height: 12),
                CampoNs(etiqueta: 'Buscar proveedor', controller: _buscar, placeholder: 'Nombre', onChanged: (_) => setState(() {})),
                const SizedBox(height: 10),
                SegmentoNs(opciones: const ['Todos', 'Con deuda'], indice: _soloConDeuda ? 1 : 0, onCambio: (i) => setState(() => _soloConDeuda = i == 1)),
                const SizedBox(height: 12),
                if (filas.isEmpty)
                  const InfoNs('Todavía no cargaste proveedores. Con "+ Nuevo" das de alta el primero.')
                else if (activos.isEmpty && deBaja.isEmpty)
                  InfoNs(_soloConDeuda && texto.isEmpty ? 'No le debés nada a nadie.' : 'Sin proveedores con ese nombre.'),
                for (final f in activos) _FilaProveedor(proveedor: f.proveedor, saldo: f.saldo, onTap: () => _abrir(f.proveedor)),
                if (deBaja.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 14, bottom: 8), child: SeccionNs('Dados de baja')),
                  for (final f in deBaja) _FilaProveedor(proveedor: f.proveedor, saldo: f.saldo, onTap: () => _abrir(f.proveedor)),
                ],
              ],
            ),
    );
  }
}

class _FilaProveedor extends StatelessWidget {
  const _FilaProveedor({required this.proveedor, required this.saldo, required this.onTap});
  final Proveedor proveedor;
  final int saldo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final dias = _dias(proveedor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PresionNs(
        onTap: onTap,
        etiqueta: proveedor.nombre,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(proveedor.nombre, style: estiloNs(17, peso: FontWeight.w500, color: proveedor.activo ? ns.ink : ns.mute)),
                    if (dias != null) Text(dias, style: estiloNs(13, color: ns.mute)),
                  ],
                ),
              ),
              Text(saldo == 0 ? 'Al día' : plataNs(saldo), style: estiloNs(17, peso: FontWeight.w600, color: saldo > 0 ? ns.w : ns.mute)),
              const SizedBox(width: 8),
              IconoNsWidget(IconoNs.chevron, tamanio: 16, color: ns.mute, grosor: 2.2),
            ],
          ),
        ),
      ),
    );
  }
}

class _Saldo extends StatelessWidget {
  const _Saldo({required this.etiqueta, required this.saldo});
  final String etiqueta;
  final int saldo;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final debe = saldo > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: debe ? ns.wbg : ns.gbg, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: estiloNs(15, peso: FontWeight.w500, color: debe ? ns.w : ns.g)),
          const SizedBox(height: 4),
          Text(plataNs(saldo), key: const Key('saldo_deuda'), style: tituloNs(36, color: debe ? ns.w : ns.g)),
        ],
      ),
    );
  }
}

/// La ficha de un proveedor: lo que le debés, sus datos (con "Editar" y "Pedir por WhatsApp") y su cuenta corriente
/// (cargos y pagos, más nuevos primero).
class PantallaProveedor extends StatefulWidget {
  const PantallaProveedor({super.key, required this.db, required this.proveedor, this.usuarioId});
  final AppDatabase db;
  final Proveedor proveedor;
  final int? usuarioId;

  @override
  State<PantallaProveedor> createState() => _PantallaProveedorState();
}

class _PantallaProveedorState extends State<PantallaProveedor> {
  late Proveedor _proveedor = widget.proveedor;
  int _saldo = 0;
  List<MovimientoDeuda>? _movimientos;

  /// Los cargos que vienen de una factura aplicada: se deshacen enteros (deuda, stock y costo), no se anulan solos.
  Set<int> _deFactura = const {};
  int? _usuarioId;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    _recargar();
  }

  Future<void> _recargar() async {
    final proveedor = await (widget.db.select(widget.db.proveedores)..where((p) => p.id.equals(_proveedor.id))).getSingleOrNull();
    if (proveedor != null) _proveedor = proveedor;
    final saldo = await saldoDeuda(widget.db, _proveedor.id);
    final movimientos = await listarMovimientosDeuda(widget.db, _proveedor.id);
    final deFactura = await movimientosDeudaConFactura(widget.db, _proveedor.id);
    if (mounted) {
      setState(() {
        _saldo = saldo;
        _movimientos = movimientos;
        _deFactura = deFactura;
      });
    }
  }

  /// La caja abierta de hoy, si hay: anular un pago que salió de una caja la devuelve ahí.
  Future<int?> _sesionAbierta() async {
    final s = await PuertoLocal(widget.db).sesion();
    return s.abierta ? s.id : null;
  }

  Future<void> _pagar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PantallaPagarProveedor(servicio: PuertoLocal(widget.db), proveedorId: _proveedor.id)),
    );
    await _recargar();
  }

  Future<void> _editar() async {
    await abrirFormularioProveedor(context, db: widget.db, proveedor: _proveedor);
    await _recargar();
  }

  /// Abre el chat del proveedor con lo que está bajo el mínimo ya escrito, como "Pedir por WhatsApp" de la PC. No manda
  /// nada solo: se le ponen las cantidades en WhatsApp y se aprieta enviar.
  Future<void> _pedirPorWhatsApp() async {
    final numero = normalizarWhatsapp(_proveedor.whatsapp ?? '');
    if (numero == null) {
      mostrarAvisoNs(context, 'Cargale el WhatsApp a ${_proveedor.nombre} con "Editar"', largo: true);
      return;
    }
    final lineas = await lineasParaPedirAProveedor(widget.db, _proveedor.id);
    if (!mounted) return;
    if (lineas.isEmpty) {
      mostrarAvisoNs(context, 'No hay nada con stock bajo para pedirle a ${_proveedor.nombre}', largo: true);
      return;
    }
    final comercio = (await configuracionNegocioActual(widget.db)).nombreComercio;
    final url = urlWhatsapp(numero, armarMensajePedido(proveedor: _proveedor.nombre, comercio: comercio, lineas: lineas));
    final abrio = await (abrirUrlParaTestsNs ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(url);
    if (!abrio && mounted) mostrarAvisoNs(context, 'No se pudo abrir WhatsApp');
  }

  Future<void> _cargarDeuda() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final cargo = await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaCargarDeuda(db: widget.db, proveedor: _proveedor, usuarioId: usuarioId),
    );
    if (cargo == true) {
      await _recargar();
      if (mounted) mostrarAvisoNs(context, 'Deuda cargada');
    }
  }

  Future<void> _acciones(MovimientoDeuda m) async {
    if (m.anuladoEn != null) return;
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final esPago = m.tipo == 'PAGO';
    final deFactura = _deFactura.contains(m.id);
    final texto = deFactura
        ? 'Se anula la deuda, se resta el stock que sumó y los productos vuelven al costo de antes (salvo los que hayas cambiado a mano después).'
        : esPago
            ? 'La deuda vuelve a subir ${plataNs(m.montoCentavos)}.${m.movimientoCajaId != null ? ' Lo que salió de la caja se devuelve con un movimiento nuevo en la caja abierta de hoy.' : ''}'
            : 'La deuda baja ${plataNs(m.montoCentavos)}.';
    final confirmar = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: deFactura ? 'Deshacer esta factura' : (esPago ? 'Anular este pago' : 'Anular esta deuda'),
        texto: '${m.nota ?? (esPago ? 'Pago' : 'Deuda')} · ${plataNs(m.montoCentavos)} · ${_fecha(m.fecha)}\n\n$texto',
        botones: [
          BotonNs.peligroSolido(ctx, deFactura ? 'Deshacer factura' : 'Anular', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      if (deFactura) {
        final factura = await facturaDelMovimientoDeuda(widget.db, m.id);
        if (factura == null) return;
        final r = await deshacerFactura(widget.db, facturaId: factura.id, usuarioId: usuarioId);
        if (mounted) {
          mostrarAvisoNs(context, r.costosQueQuedaron.isEmpty ? 'Factura deshecha' : 'Factura deshecha. El costo de ${r.costosQueQuedaron.join(', ')} quedó como lo cambiaste.', largo: true);
        }
      } else {
        await anularMovimientoDeuda(widget.db, movimientoId: m.id, usuarioId: usuarioId, sesionCajaId: await _sesionAbierta());
        if (mounted) mostrarAvisoNs(context, esPago ? 'Pago anulado' : 'Deuda anulada');
      }
    } on SinCajaAbiertaException {
      if (mounted) mostrarAvisoNs(context, 'Para anular un pago que salió de la caja hace falta la caja abierta.', largo: true);
    } on ArgumentError catch (e) {
      if (mounted) mostrarAvisoNs(context, '${e.message}', largo: true);
    }
    await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final movimientos = _movimientos;
    return PaginaNs(
      titulo: _proveedor.nombre,
      derecha: BotonNs(texto: 'Editar', onTap: _editar, alto: 44, tamanio: 15, fondo: ns.s, color: ns.ink, rellenar: false, paddingH: 18, icono: IconoNs.editar),
      cuerpo: movimientos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _Saldo(etiqueta: _saldo > 0 ? 'Le debés' : 'Sin deuda', saldo: _saldo),
                const SizedBox(height: 10),
                if (!_proveedor.activo) ...[
                  const InfoNs('Dado de baja: no aparece al elegir proveedor. Lo activás con "Editar".', tono: TonoNs.warn),
                  const SizedBox(height: 10),
                ],
                _Datos(proveedor: _proveedor),
                const SizedBox(height: 10),
                BotonNs.secundario(context, 'Pedir por WhatsApp', _pedirPorWhatsApp, icono: IconoNs.camion),
                const SizedBox(height: 18),
                const SeccionNs('Movimientos'),
                const SizedBox(height: 8),
                if (movimientos.isEmpty) const InfoNs('Todavía no cargaste nada. Con "Cargar deuda" anotás lo que le debés.'),
                for (final m in movimientos) _FilaMovimiento(m: m, deFactura: _deFactura.contains(m.id), onTap: () => _acciones(m)),
                if (movimientos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Tocá un movimiento para anularlo.', style: estiloNs(13, color: ns.mute))),
              ],
            ),
      botones: [
        Row(
          children: [
            Expanded(child: BotonNs.secundario(context, 'Cargar deuda', _cargarDeuda)),
            const SizedBox(width: 8),
            Expanded(child: BotonNs.primario(context, 'Pagar', _pagar, alto: 54, tamanio: 16)),
          ],
        ),
      ],
    );
  }
}

/// Los datos que se cargan en el alta: cuándo se le pide, cuándo entrega, cómo se le paga y su WhatsApp.
class _Datos extends StatelessWidget {
  const _Datos({required this.proveedor});
  final Proveedor proveedor;

  @override
  Widget build(BuildContext context) {
    String o(String? v) => v == null || v.trim().isEmpty ? 'Sin cargar' : v.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: context.ns.s, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          FilaClaveValorNs(clave: 'Le pedís', valor: o(proveedor.diaPedido), tamanioValor: 16),
          FilaClaveValorNs(clave: 'Te entrega', valor: o(proveedor.diaEntrega), tamanioValor: 16),
          FilaClaveValorNs(clave: 'Le pagás con', valor: proveedor.cajaAparte ? 'Efectivo de la lata' : proveedor.medioPago, tamanioValor: 16),
          FilaClaveValorNs(clave: 'WhatsApp', valor: o(proveedor.whatsapp), tamanioValor: 16, sinLinea: true),
        ],
      ),
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.m, required this.deFactura, required this.onTap});
  final MovimientoDeuda m;
  final bool deFactura;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final esPago = m.tipo == 'PAGO';
    final anulado = m.anuladoEn != null;
    final color = anulado ? ns.mute : (esPago ? ns.g : ns.w);
    final detalle = [
      _fecha(m.fecha),
      if (esPago) OrigenPagoDeuda.desde(m.origenPago).etiqueta,
      if (deFactura && !anulado) 'factura cargada',
      if (anulado) 'anulado',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PresionNs(
        onTap: anulado ? null : onTap,
        etiqueta: m.nota ?? (esPago ? 'Pago' : 'Deuda'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nota ?? (esPago ? 'Pago' : 'Deuda'), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: estiloNs(15, peso: FontWeight.w500, color: anulado ? ns.mute : ns.ink, )),
                    Text(detalle, style: estiloNs(13, color: ns.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${esPago ? '−' : '+'}${plataNs(m.montoCentavos)}',
                  style: estiloNs(16, peso: FontWeight.w600, color: color).copyWith(decoration: anulado ? TextDecoration.lineThrough : null)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HojaCargarDeuda extends StatefulWidget {
  const _HojaCargarDeuda({required this.db, required this.proveedor, required this.usuarioId});
  final AppDatabase db;
  final Proveedor proveedor;
  final int usuarioId;

  @override
  State<_HojaCargarDeuda> createState() => _HojaCargarDeudaState();
}

class _HojaCargarDeudaState extends State<_HojaCargarDeuda> {
  final _monto = TextEditingController();
  final _nota = TextEditingController();
  DateTime _fechaElegida = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(context: context, initialDate: _fechaElegida, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (elegida != null) setState(() => _fechaElegida = elegida);
  }

  Future<void> _confirmar() async {
    final int monto;
    try {
      monto = parsearARS(_monto.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a 0');
      return;
    }
    await cargarDeuda(widget.db, proveedorId: widget.proveedor.id, montoCentavos: monto, fecha: _fechaElegida, nota: _nota.text, usuarioId: widget.usuarioId);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Cargar deuda',
      texto: widget.proveedor.nombre,
      bloques: [
        CampoNs(etiqueta: 'Cuánto le debés', controller: _monto, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, grande: true, autofoco: true,
            onChanged: (_) => setState(() => _error = null)),
        CampoNs(etiqueta: 'Nota (remito, factura…) — opcional', controller: _nota, placeholder: 'Ej: remito 1234'),
        BotonNs.secundario(context, 'De la fecha: ${_fecha(_fechaElegida)}', _elegirFecha, icono: IconoNs.calendario),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [BotonNs.primario(context, 'Cargar deuda', _confirmar)],
    );
  }
}
