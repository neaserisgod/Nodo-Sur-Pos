// "Pagar proveedor" desde la pantalla de venta (Alt+P) — rediseño v4 (El dueño, 2026-10-05: "lo principal es pagar proveedor").
// Es el camino más corto para el pago más común del día: se escribe parte del nombre, Enter elige, el monto ya viene con
// toda la deuda, Enter paga. No inventa nada nuevo: registra con el mismo `pagarDeuda` que la cuenta corriente del
// proveedor (mismo movimiento de caja, mismo saldo, mismo rastro), solo que sin pasar por la pantalla de Proveedores.
//
// - El origen de la plata se acuerda del último pago de esta sesión de la app (la mayoría de los días se paga siempre del
//   mismo lado); sin caja abierta solo se puede "Fuera de la caja".
// - Pagar más de lo que se debe pide confirmar con un segundo Enter: el pago sobrante queda como "pago sin deuda previa"
//   (regla de `pagarDeuda`) y por eso ese pago no se puede deshacer desde el aviso.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/repositorio_deuda_proveedores.dart';
import '../../domain/dinero.dart';
import '../../domain/modulos.dart';
import '../../domain/normalizacion_texto.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/aviso_superior.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';

/// Lo que quedó hecho, para que quien abrió el diálogo avise y ofrezca deshacer.
class PagoProveedorHecho {
  const PagoProveedorHecho({
    required this.proveedorNombre,
    required this.montoCentavos,
    required this.origen,
    required this.movimientoId,
    required this.deshacible,
  });

  final String proveedorNombre;
  final int montoCentavos;
  final OrigenPagoDeuda origen;
  final int movimientoId;

  /// `false` si pagó de más (quedó un cargo "pago sin deuda previa" que el deshacer no limpia).
  final bool deshacible;

  String get texto => 'Pagaste ${formatearARS(montoCentavos)} a $proveedorNombre · ${origen.etiqueta.toLowerCase()}';
}

/// El último origen elegido en esta ejecución de la app.
OrigenPagoDeuda? _ultimoOrigen;

Future<PagoProveedorHecho?> mostrarDialogoPagarProveedorRapido(
  BuildContext context, {
  required AppDatabase db,
  required int usuarioId,
  int? sesionCajaId,
}) {
  return mostrarModal<PagoProveedorHecho>(
    context,
    builder: (_) => DialogoPagarProveedorRapido(db: db, usuarioId: usuarioId, sesionCajaId: sesionCajaId),
  );
}

/// El flujo completo desde cualquier pantalla: abre el diálogo y, al pagar, avisa arriba con Deshacer (si se puede).
/// Lo usan Venta (Alt+P y el botón) y el Asistente (Ctrl+K), para que sea una sola cosa.
Future<void> pagarProveedorYAvisar(
  BuildContext context, {
  required AppDatabase db,
  required int usuarioId,
  required int sesionCajaId,
}) async {
  final hecho = await mostrarDialogoPagarProveedorRapido(context, db: db, usuarioId: usuarioId, sesionCajaId: sesionCajaId);
  if (hecho == null || !context.mounted) return;
  mostrarAviso(
    context,
    hecho.texto,
    textoAccion: hecho.deshacible ? 'Deshacer' : null,
    alAccionar: hecho.deshacible ? () => _deshacerPago(context, db, hecho, sesionCajaId, usuarioId) : null,
  );
}

Future<void> _deshacerPago(BuildContext context, AppDatabase db, PagoProveedorHecho hecho, int sesionId, int usuarioId) async {
  try {
    await anularMovimientoDeuda(db, movimientoId: hecho.movimientoId, usuarioId: usuarioId, sesionCajaId: sesionId);
    if (context.mounted) mostrarAviso(context, 'Pago deshecho · ${hecho.proveedorNombre}');
  } on Object catch (e) {
    if (context.mounted) mostrarAviso(context, 'No se pudo deshacer: ${e is ArgumentError ? e.message : e}');
  }
}

class _ProveedorConDeuda {
  const _ProveedorConDeuda(this.proveedor, this.saldoCentavos);
  final Proveedor proveedor;
  final int saldoCentavos;
}

class DialogoPagarProveedorRapido extends StatefulWidget {
  const DialogoPagarProveedorRapido({super.key, required this.db, required this.usuarioId, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<DialogoPagarProveedorRapido> createState() => _DialogoPagarProveedorRapidoState();
}

class _DialogoPagarProveedorRapidoState extends State<DialogoPagarProveedorRapido> {
  final _busquedaCtrl = TextEditingController();
  final _focoBusqueda = FocusNode();
  final _montoCtrl = TextEditingController();
  final _focoMonto = FocusNode();

  List<_ProveedorConDeuda> _todos = const [];
  _ProveedorConDeuda? _elegido;
  int _indice = 0;
  late OrigenPagoDeuda _origen = _origenInicial();
  String? _error;
  bool _confirmaSobrepago = false;
  bool _pagando = false;

  OrigenPagoDeuda _origenInicial() {
    if (widget.sesionCajaId == null) return OrigenPagoDeuda.fuera;
    final ultimo = _ultimoOrigen;
    if (ultimo != null && ultimo != OrigenPagoDeuda.fuera) return ultimo;
    return OrigenPagoDeuda.cajon;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _focoBusqueda.dispose();
    _montoCtrl.dispose();
    _focoMonto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final proveedores = await (widget.db.select(widget.db.proveedores)..where((p) => p.activo.equals(true))).get();
    final saldos = await saldosDeuda(widget.db);
    final lista = [for (final p in proveedores) _ProveedorConDeuda(p, saldos[p.id] ?? 0)]
      // Con deuda primero (la más grande arriba), después por nombre: lo que hay que pagar está a la vista.
      ..sort((a, b) {
        final porDeuda = b.saldoCentavos.compareTo(a.saldoCentavos);
        return porDeuda != 0 ? porDeuda : a.proveedor.nombre.compareTo(b.proveedor.nombre);
      });
    if (mounted) setState(() => _todos = lista);
  }

  List<_ProveedorConDeuda> get _filtrados {
    final q = normalizarTexto(_busquedaCtrl.text.trim());
    if (q.isEmpty) return _todos;
    return [for (final p in _todos) if (normalizarTexto(p.proveedor.nombre).contains(q)) p];
  }

  void _elegir(_ProveedorConDeuda p) {
    setState(() {
      _elegido = p;
      _error = null;
      _confirmaSobrepago = false;
      _montoCtrl.text = p.saldoCentavos > 0 ? formatearARS(p.saldoCentavos).replaceAll('\$', '').trim() : '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focoMonto.requestFocus();
      _montoCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _montoCtrl.text.length);
    });
  }

  void _volverALista() {
    setState(() {
      _elegido = null;
      _error = null;
      _confirmaSobrepago = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoBusqueda.requestFocus();
    });
  }

  int? get _monto {
    try {
      final m = parsearARS(_montoCtrl.text);
      return m > 0 ? m : null;
    } on FormatException {
      return null;
    }
  }

  KeyEventResult _teclaEnBusqueda(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final lista = _filtrados;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && lista.isNotEmpty) {
      setState(() => _indice = (_indice + 1) % lista.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && lista.isNotEmpty) {
      setState(() => _indice = (_indice - 1 + lista.length) % lista.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _enterEnBusqueda() {
    final lista = _filtrados;
    if (lista.isEmpty) return;
    _elegir(lista[_indice.clamp(0, lista.length - 1)]);
  }

  Future<void> _pagar() async {
    final elegido = _elegido;
    final monto = _monto;
    if (elegido == null || _pagando) return;
    if (monto == null) {
      setState(() => _error = 'Escribí el monto');
      _focoMonto.requestFocus();
      return;
    }
    final debe = elegido.saldoCentavos;
    if (monto > debe && !_confirmaSobrepago) {
      // Pagar más de lo debido es posible (queda como pago sin deuda previa) pero casi siempre es un error de tipeo:
      // se avisa y se confirma con un segundo Enter.
      setState(() {
        _confirmaSobrepago = true;
        _error = debe > 0
            ? 'Pagás más de lo que debés (${formatearARS(debe)}). Tocá Pagar de nuevo para confirmar.'
            : 'No tiene deuda cargada: el pago se anota igual como un gasto con este proveedor. Tocá Pagar de nuevo para confirmar.';
      });
      // Enter en un campo con acción "listo" le saca el foco: se lo devuelvo para que el segundo Enter confirme.
      _focoMonto.requestFocus();
      return;
    }
    setState(() => _pagando = true);
    try {
      final id = await pagarDeuda(
        widget.db,
        proveedorId: elegido.proveedor.id,
        montoCentavos: monto,
        origen: _origen,
        usuarioId: widget.usuarioId,
        sesionCajaId: widget.sesionCajaId,
      );
      _ultimoOrigen = _origen;
      if (!mounted) return;
      Navigator.of(context).pop(
        PagoProveedorHecho(
          proveedorNombre: elegido.proveedor.nombre,
          montoCentavos: monto,
          origen: _origen,
          movimientoId: id,
          deshacible: monto <= debe,
        ),
      );
    } on SinCajaAbiertaException {
      if (mounted) {
        setState(() {
          _pagando = false;
          _error = 'No hay caja abierta: elegí "Fuera de la caja" o abrí la caja primero.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final elegido = _elegido;
    return Modal(
      titulo: 'Pagar proveedor',
      subtitulo: elegido == null ? 'Escribí para buscar · Enter elige · Enter paga' : null,
      ancho: 620,
      contenido: elegido == null ? _paso1() : _paso2(elegido),
      botones: [
        if (elegido != null) BotonSecundario(texto: 'Cambiar de proveedor', onPressed: _volverALista),
        if (elegido != null) BotonPrimario(texto: 'Pagar ${_monto == null ? '' : formatearARS(_monto!)}'.trim(), onPressed: _pagar),
      ],
    );
  }

  Widget _paso1() {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final lista = _filtrados;
    final indice = lista.isEmpty ? 0 : _indice.clamp(0, lista.length - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: _teclaEnBusqueda,
          child: CampoTexto(
            key: const Key('pago_rapido_busqueda'),
            controller: _busquedaCtrl,
            focusNode: _focoBusqueda,
            autofocus: true,
            etiqueta: 'Proveedor',
            onChanged: (_) => setState(() => _indice = 0),
            onSubmitted: (_) => _enterEnBusqueda(),
          ),
        ),
        const SizedBox(height: Espaciado.md),
        if (lista.isEmpty)
          Padding(padding: const EdgeInsets.all(Espaciado.lg), child: Text('Sin coincidencias', style: textTheme.bodyMedium))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lista.length,
              itemBuilder: (context, i) {
                final p = lista[i];
                final marcada = i == indice;
                return Padding(
                  padding: const EdgeInsets.only(bottom: Espaciado.xs),
                  child: Material(
                    color: marcada ? colores.fondoBloque : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      key: Key('pago_rapido_proveedor_${p.proveedor.id}'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _elegir(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.proveedor.nombre, style: textTheme.titleMedium),
                                  if (p.proveedor.diaPedido != null)
                                    Text('pedido ${p.proveedor.diaPedido!.toLowerCase()}', style: textTheme.bodySmall),
                                ],
                              ),
                            ),
                            Text(
                              p.saldoCentavos > 0 ? formatearARS(p.saldoCentavos) : 'Al día',
                              style: textTheme.titleMedium?.copyWith(color: p.saldoCentavos > 0 ? colores.textoPrimario : colores.textoTenue),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _paso2(_ProveedorConDeuda elegido) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final monto = _monto;
    final debe = elegido.saldoCentavos;
    final queda = monto == null ? debe : (debe - monto).clamp(0, 1 << 40);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(elegido.proveedor.nombre, style: textTheme.headlineSmall),
        Text(debe > 0 ? 'Le debés ${formatearARS(debe)}' : 'Sin deuda cargada', style: textTheme.bodyMedium),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('pago_rapido_monto'),
          controller: _montoCtrl,
          focusNode: _focoMonto,
          etiqueta: 'Monto a pagar',
          onChanged: (_) => setState(() {
            _error = null;
            _confirmaSobrepago = false;
          }),
          onSubmitted: (_) => _pagar(),
        ),
        const SizedBox(height: Espaciado.sm),
        if (debe > 0)
          Wrap(
            spacing: Espaciado.sm,
            children: [
              ChipAtajo(
                texto: 'Todo · ${formatearARS(debe)}',
                elegido: monto == debe,
                onTap: () => setState(() => _montoCtrl.text = formatearARS(debe).replaceAll('\$', '').trim()),
              ),
              ChipAtajo(
                texto: 'Mitad · ${formatearARS(debe ~/ 2)}',
                elegido: monto == debe ~/ 2,
                onTap: () => setState(() => _montoCtrl.text = formatearARS(debe ~/ 2).replaceAll('\$', '').trim()),
              ),
            ],
          ),
        const SizedBox(height: Espaciado.lg),
        Text('De dónde sale la plata', style: textTheme.labelMedium),
        const SizedBox(height: Espaciado.xs + 2),
        Wrap(
          spacing: Espaciado.sm,
          runSpacing: Espaciado.sm,
          children: [
            for (final o in OrigenPagoDeuda.values)
              if (widget.sesionCajaId != null || o == OrigenPagoDeuda.fuera)
                if (o != OrigenPagoDeuda.lata || moduloActivo(Modulo.cajaAparte))
                  ChipAtajo(texto: o.etiqueta, elegido: _origen == o, onTap: () => setState(() => _origen = o)),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        Text('Después de pagar le debés ${formatearARS(queda)}', style: textTheme.bodyMedium),
        if (_error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(_error!, key: const Key('pago_rapido_error'), style: TextStyle(color: colores.error)),
        ],
      ],
    );
  }
}
