// Cuenta corriente con proveedores en el celular (El dueño, 2026-10-07: "seguí con la cuenta corriente"). Lo mismo que la cuenta
// corriente de la PC (Proveedores › un proveedor › Cuenta corriente): cuánto le debés a cada uno, el libro de cargos y pagos, cargar una
// deuda, pagar, anular y deshacer una factura aplicada. Las reglas viven en `data/repositorio_deuda_proveedores.dart` y
// `data/repositorio_facturas_compra.dart`; acá solo se dibuja.
//
// Sobre la base del celular, como Cargar factura y Pagar proveedor: la cuenta corriente se sincroniza desde la v61.

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositorio_deuda_proveedores.dart';
import '../data/repositorio_facturas_compra.dart';
import '../domain/dinero.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'pantalla_pagar_proveedor.dart';
import 'puerto_local.dart';

String _fecha(DateTime f) => '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

/// Todos los proveedores, primero los que tienen deuda (de mayor a menor), con el total arriba.
class PantallaCuentaCorriente extends StatefulWidget {
  /// [db] y [usuarioId] son para tests.
  const PantallaCuentaCorriente({super.key, this.db, this.usuarioId});

  final AppDatabase? db;
  final int? usuarioId;

  @override
  State<PantallaCuentaCorriente> createState() => _PantallaCuentaCorrienteState();
}

class _PantallaCuentaCorrienteState extends State<PantallaCuentaCorriente> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<({Proveedor proveedor, int saldo})>? _filas;
  bool _todos = false;
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
    final proveedores = await (_db.select(_db.proveedores)..where((p) => p.activo.equals(true))).get();
    final filas = [for (final p in proveedores) (proveedor: p, saldo: saldos[p.id] ?? 0)]
      ..sort((a, b) => a.saldo != b.saldo ? b.saldo.compareTo(a.saldo) : a.proveedor.nombre.toLowerCase().compareTo(b.proveedor.nombre.toLowerCase()));
    if (mounted) setState(() => _filas = filas);
  }

  Future<void> _abrir(Proveedor p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PantallaCuentaProveedor(db: _db, proveedor: p, usuarioId: widget.usuarioId)));
    await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final filas = _filas;
    final total = filas?.fold<int>(0, (a, f) => a + (f.saldo > 0 ? f.saldo : 0)) ?? 0;
    final texto = _buscar.text.trim().toLowerCase();
    final visibles = filas == null
        ? const <({Proveedor proveedor, int saldo})>[]
        : [
            for (final f in filas)
              if ((_todos || f.saldo != 0 || texto.isNotEmpty) && (texto.isEmpty || f.proveedor.nombre.toLowerCase().contains(texto))) f,
          ];
    return PaginaNs(
      titulo: 'Cuenta corriente',
      cuerpo: filas == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _Saldo(etiqueta: total > 0 ? 'Les debés en total' : 'No le debés a nadie', saldo: total),
                const SizedBox(height: 12),
                CampoNs(etiqueta: 'Buscar proveedor', controller: _buscar, placeholder: 'Nombre', onChanged: (_) => setState(() {})),
                const SizedBox(height: 10),
                SegmentoNs(opciones: const ['Con deuda', 'Todos'], indice: _todos ? 1 : 0, onCambio: (i) => setState(() => _todos = i == 1)),
                const SizedBox(height: 12),
                if (visibles.isEmpty) InfoNs(_todos || texto.isNotEmpty ? 'Sin proveedores.' : 'No le debés nada a nadie. Con "Todos" ves cada proveedor para cargarle una deuda.'),
                for (final f in visibles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PresionNs(
                      onTap: () => _abrir(f.proveedor),
                      etiqueta: f.proveedor.nombre,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                        child: Row(
                          children: [
                            Expanded(child: Text(f.proveedor.nombre, style: estiloNs(17, peso: FontWeight.w500, color: ns.ink))),
                            Text(f.saldo == 0 ? 'Al día' : plataNs(f.saldo), style: estiloNs(17, peso: FontWeight.w600, color: f.saldo > 0 ? ns.w : ns.mute)),
                            const SizedBox(width: 8),
                            IconoNsWidget(IconoNs.chevron, tamanio: 16, color: ns.mute, grosor: 2.2),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
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

/// El libro con un proveedor: saldo, cargos y pagos (más nuevos primero) y las acciones.
class PantallaCuentaProveedor extends StatefulWidget {
  const PantallaCuentaProveedor({super.key, required this.db, required this.proveedor, this.usuarioId});
  final AppDatabase db;
  final Proveedor proveedor;
  final int? usuarioId;

  @override
  State<PantallaCuentaProveedor> createState() => _PantallaCuentaProveedorState();
}

class _PantallaCuentaProveedorState extends State<PantallaCuentaProveedor> {
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
    final saldo = await saldoDeuda(widget.db, widget.proveedor.id);
    final movimientos = await listarMovimientosDeuda(widget.db, widget.proveedor.id);
    final deFactura = await movimientosDeudaConFactura(widget.db, widget.proveedor.id);
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
      MaterialPageRoute<void>(builder: (_) => PantallaPagarProveedor(servicio: PuertoLocal(widget.db), proveedorId: widget.proveedor.id)),
    );
    await _recargar();
  }

  Future<void> _cargarDeuda() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final cargo = await mostrarHojaNs<bool>(
      context,
      builder: (_) => _HojaCargarDeuda(db: widget.db, proveedor: widget.proveedor, usuarioId: usuarioId),
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
      titulo: widget.proveedor.nombre,
      cuerpo: movimientos == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _Saldo(etiqueta: _saldo > 0 ? 'Le debés' : 'Sin deuda', saldo: _saldo),
                const SizedBox(height: 14),
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
