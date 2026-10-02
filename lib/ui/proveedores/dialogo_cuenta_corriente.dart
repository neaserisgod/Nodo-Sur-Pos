// Cuenta corriente con un proveedor: lo que el dueño LE DEBE (2026-09-29:
// "un apartado de deuda o cuenta corriente para ir cargando los saldos que
// yo adeudo, y pagar desde ahí dejando registro"). Arriba el saldo, abajo el
// libro (cargos y pagos, más nuevos primero) y las dos acciones: cargar una
// deuda y pagar.
//
// Es un libro aparte de lo que se separa para cada proveedor (Separaciones /
// Avanzado): no se tocan entre sí. Un pago desde una caja deja un movimiento
// de caja con el proveedor puesto — el arqueo baja y el gasto tiene dueño
// (`lib/data/repositorio_deuda_proveedores.dart`).

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_deuda_proveedores.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/acentos.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoCuentaCorriente(
  BuildContext context, {
  required AppDatabase db,
  required Proveedor proveedor,
  required int usuarioId,
  required int? sesionCajaId,
}) {
  return mostrarModal<void>(
    context,
    builder: (_) => _DialogoCuentaCorriente(
      db: db,
      proveedor: proveedor,
      usuarioId: usuarioId,
      sesionCajaId: sesionCajaId,
    ),
  );
}

String _fechaCorta(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

class _DialogoCuentaCorriente extends StatefulWidget {
  const _DialogoCuentaCorriente({
    required this.db,
    required this.proveedor,
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final Proveedor proveedor;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<_DialogoCuentaCorriente> createState() =>
      _DialogoCuentaCorrienteState();
}

class _DialogoCuentaCorrienteState extends State<_DialogoCuentaCorriente> {
  int _saldo = 0;
  List<MovimientoDeuda> _movimientos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    final saldo = await saldoDeuda(widget.db, widget.proveedor.id);
    final movimientos = await listarMovimientosDeuda(
      widget.db,
      widget.proveedor.id,
    );
    if (!mounted) return;
    setState(() {
      _saldo = saldo;
      _movimientos = movimientos;
      _cargando = false;
    });
  }

  Future<void> _cargarDeuda() async {
    final cargo = await mostrarModal<bool>(
      context,
      builder: (_) => _DialogoCargarDeuda(
        db: widget.db,
        proveedor: widget.proveedor,
        usuarioId: widget.usuarioId,
      ),
    );
    if (cargo == true) await _recargar();
  }

  Future<void> _pagar() async {
    final pago = await mostrarModal<bool>(
      context,
      builder: (_) => _DialogoPagarDeuda(
        db: widget.db,
        proveedor: widget.proveedor,
        usuarioId: widget.usuarioId,
        sesionCajaId: widget.sesionCajaId,
        saldoCentavos: _saldo,
      ),
    );
    if (pago == true) await _recargar();
  }

  Future<void> _anular(MovimientoDeuda m) async {
    final esPago = m.tipo == 'PAGO';
    final confirmar = await mostrarModal<bool>(
      context,
      builder: (context) => Modal(
        titulo: esPago ? 'Anular este pago' : 'Anular esta deuda',
        subtitulo: '${formatearARS(m.montoCentavos)} · ${_fechaCorta(m.fecha)}',
        contenido: Text(
          esPago
              ? 'La deuda vuelve a subir ${formatearARS(m.montoCentavos)}.'
                    '${m.movimientoCajaId != null ? ' Lo que salió de la caja se devuelve con un movimiento nuevo en la caja abierta de hoy.' : ''}'
              : 'La deuda baja ${formatearARS(m.montoCentavos)}.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        botones: [
          BotonSecundario(
            texto: 'Volver',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          BotonPrimario(
            texto: 'Anular',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await anularMovimientoDeuda(
        widget.db,
        movimientoId: m.id,
        usuarioId: widget.usuarioId,
        sesionCajaId: widget.sesionCajaId,
      );
      setState(() => _error = null);
      await _recargar();
    } on SinCajaAbiertaException {
      setState(
        () => _error =
            'Para anular un pago que salió de la caja hace falta la caja abierta.',
      );
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final debe = _saldo > 0;

    return Modal(
      titulo: 'Cuenta corriente',
      subtitulo: widget.proveedor.nombre,
      ancho: 640,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Espaciado.lg,
              vertical: Espaciado.md,
            ),
            decoration: BoxDecoration(
              color: debe ? acentos.alertaSuave : acentos.gananciaSuave,
              borderRadius: BorderRadius.circular(radioControlEscritorio),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    debe ? 'Le debés' : 'Sin deuda',
                    style: textTheme.titleMedium?.copyWith(
                      color: debe ? acentos.alerta : acentos.ganancia,
                      fontWeight: Pesos.medium,
                    ),
                  ),
                ),
                Text(
                  formatearARS(_saldo),
                  key: const Key('saldo_deuda'),
                  style: textTheme.headlineMedium
                      ?.copyWith(
                        color: debe ? acentos.alerta : acentos.ganancia,
                      )
                      .tabular,
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(Espaciado.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_movimientos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espaciado.lg),
              child: Text(
                'Todavía no cargaste nada. Con "Cargar deuda" anotás lo que le debés.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colores.textoSecundario,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _movimientos.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: Espaciado.xs),
                itemBuilder: (_, i) => _FilaMovimiento(
                  movimiento: _movimientos[i],
                  onAnular: () => _anular(_movimientos[i]),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonSecundario(texto: 'Cargar deuda', onPressed: _cargarDeuda),
        BotonPrimario(texto: 'Pagar', onPressed: _pagar),
      ],
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.movimiento, required this.onAnular});

  final MovimientoDeuda movimiento;
  final VoidCallback onAnular;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final m = movimiento;
    final esPago = m.tipo == 'PAGO';
    final anulado = m.anuladoEn != null;
    final colorMonto = anulado
        ? colores.textoTenue
        : (esPago ? acentos.ganancia : acentos.alerta);
    final titulo = m.nota ?? (esPago ? 'Pago' : 'Deuda');
    final detalle = [
      _fechaCorta(m.fecha),
      if (esPago) OrigenPagoDeuda.desde(m.origenPago).etiqueta,
      if (anulado) 'anulado',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.md,
        vertical: Espaciado.sm,
      ),
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: Pesos.medium,
                    color: anulado ? colores.textoTenue : colores.textoPrimario,
                    decoration: anulado ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(detalle, style: textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '${esPago ? '−' : '+'}${formatearARS(m.montoCentavos)}',
            style: textTheme.bodyMedium
                ?.copyWith(
                  color: colorMonto,
                  fontWeight: Pesos.fuerte,
                  decoration: anulado ? TextDecoration.lineThrough : null,
                )
                .tabular,
          ),
          if (!anulado) ...[
            const SizedBox(width: Espaciado.sm),
            TextButton(onPressed: onAnular, child: const Text('Anular')),
          ],
        ],
      ),
    );
  }
}

// ─── Cargar deuda ────────────────────────────────────────────────────────

class _DialogoCargarDeuda extends StatefulWidget {
  const _DialogoCargarDeuda({
    required this.db,
    required this.proveedor,
    required this.usuarioId,
  });

  final AppDatabase db;
  final Proveedor proveedor;
  final int usuarioId;

  @override
  State<_DialogoCargarDeuda> createState() => _DialogoCargarDeudaState();
}

class _DialogoCargarDeudaState extends State<_DialogoCargarDeuda> {
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _confirmar() async {
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a 0');
      return;
    }
    await cargarDeuda(
      widget.db,
      proveedorId: widget.proveedor.id,
      montoCentavos: monto,
      fecha: _fecha,
      nota: _notaCtrl.text,
      usuarioId: widget.usuarioId,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Cargar deuda',
      subtitulo: widget.proveedor.nombre,
      ancho: 520,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(
            key: const Key('campo_monto_deuda'),
            controller: _montoCtrl,
            etiqueta: 'Cuánto le debés',
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_nota_deuda'),
            controller: _notaCtrl,
            etiqueta: 'Nota (remito, factura…) — opcional',
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Text(
                'De la fecha',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: Espaciado.md),
              BotonSecundario(
                texto: _fechaCorta(_fecha),
                onPressed: _elegirFecha,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BotonPrimario(texto: 'Cargar deuda', onPressed: _confirmar),
      ],
    );
  }
}

// ─── Pagar ───────────────────────────────────────────────────────────────

class _DialogoPagarDeuda extends StatefulWidget {
  const _DialogoPagarDeuda({
    required this.db,
    required this.proveedor,
    required this.usuarioId,
    required this.sesionCajaId,
    required this.saldoCentavos,
  });

  final AppDatabase db;
  final Proveedor proveedor;
  final int usuarioId;
  final int? sesionCajaId;
  final int saldoCentavos;

  @override
  State<_DialogoPagarDeuda> createState() => _DialogoPagarDeudaState();
}

class _DialogoPagarDeudaState extends State<_DialogoPagarDeuda> {
  // Con deuda cargada arranca en el saldo; sin deuda, vacío (se puede pagar
  // igual: el pago se anota como un gasto con ese proveedor).
  late final _montoCtrl = TextEditingController(
    text: widget.saldoCentavos > 0 ? formatearARS(widget.saldoCentavos).replaceAll('\$', '') : '',
  );
  final _notaCtrl = TextEditingController();
  late OrigenPagoDeuda _origen = widget.sesionCajaId == null
      ? OrigenPagoDeuda.fuera
      : OrigenPagoDeuda.cajon;
  String? _error;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a 0');
      return;
    }
    try {
      await pagarDeuda(
        widget.db,
        proveedorId: widget.proveedor.id,
        montoCentavos: monto,
        origen: _origen,
        nota: _notaCtrl.text,
        usuarioId: widget.usuarioId,
        sesionCajaId: widget.sesionCajaId,
      );
    } on SinCajaAbiertaException {
      setState(
        () => _error =
            'No hay caja abierta: elegí "Fuera de la caja" o abrí la caja primero.',
      );
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    int monto;
    try {
      monto = _montoCtrl.text.trim().isEmpty ? 0 : parsearARS(_montoCtrl.text);
    } on FormatException {
      monto = 0;
    }
    final queda = widget.saldoCentavos - monto;
    final sinCaja = widget.sesionCajaId == null;

    return Modal(
      titulo: 'Pagar',
      subtitulo: widget.saldoCentavos > 0
          ? '${widget.proveedor.nombre} · debés ${formatearARS(widget.saldoCentavos)}'
          : '${widget.proveedor.nombre} · sin deuda cargada',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(
            key: const Key('campo_monto_pago_deuda'),
            controller: _montoCtrl,
            etiqueta: 'Cuánto pagás',
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          Text('De dónde sale la plata', style: textTheme.bodySmall),
          const SizedBox(height: Espaciado.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: GrupoPildoras<OrigenPagoDeuda>(
              opciones: [
                for (final o in OrigenPagoDeuda.values)
                  if (!sinCaja || o == OrigenPagoDeuda.fuera) (o, o.etiqueta),
              ],
              elegida: _origen,
              onElegir: (o) => setState(() => _origen = o),
            ),
          ),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_nota_pago_deuda'),
            controller: _notaCtrl,
            etiqueta: 'Nota — opcional',
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          BloqueSuave(
            child: Text(
              [
                monto <= 0
                    ? 'Escribí cuánto pagás.'
                    : widget.saldoCentavos <= 0
                    ? 'No tiene deuda cargada: el pago se anota igual como un gasto con este proveedor.'
                    : queda == 0
                    ? 'Se paga toda la deuda.'
                    : queda > 0
                    ? 'Después de este pago le seguís debiendo ${formatearARS(queda)}.'
                    : 'Se paga toda la deuda y ${formatearARS(-queda)} más se anotan como pago sin deuda previa.',
                switch (_origen) {
                  OrigenPagoDeuda.fuera => 'No toca ninguna caja de la app.',
                  OrigenPagoDeuda.mp =>
                    'Baja lo que debería haber en Mercado Pago.',
                  OrigenPagoDeuda.cajon =>
                    'Baja lo que debería haber en el cajón.',
                  OrigenPagoDeuda.lata => 'Baja lo que hay en la lata.',
                },
              ].join(' '),
              style: textTheme.bodyMedium,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BotonPrimario(texto: 'Registrar pago', onPressed: _confirmar),
      ],
    );
  }
}
