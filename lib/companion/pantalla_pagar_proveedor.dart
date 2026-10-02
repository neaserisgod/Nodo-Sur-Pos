// Pagar proveedor — acceso directo del Inicio. Es el ÚNICO camino del celular
// para pagarle a un proveedor (El dueño, 2026-10-02: "pagar proveedor es el
// único que quiero que quede"): el pago pasa por la cuenta corriente de la PC,
// así el gasto queda documentado con el proveedor y, si no había deuda cargada,
// la PC anota la diferencia como "Pago sin deuda previa" (ver `pagarDeuda`).
//
// Necesita la PC al alcance: `movimientos_deuda` no se sincroniza al celular,
// y grabar un pago solo en el celular dejaría la cuenta corriente de la PC sin
// enterarse. Sin PC se avisa en vez de grabar a medias.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'tema/chip_seleccionable.dart';
import 'tema/colores_companion.dart';
import 'tema/error_en_linea.dart';
import '../ui/comun/estado_error.dart';
import 'tema/superficie.dart';

/// De dónde sale la plata; las claves son las de `OrigenPagoDeuda`.
const _origenes = <({String clave, String etiqueta})>[
  (clave: 'cajon', etiqueta: 'Del cajón'),
  (clave: 'mp', etiqueta: 'Mercado Pago'),
  (clave: 'lata', etiqueta: 'De la lata'),
  (clave: 'fuera', etiqueta: 'Fuera de la caja'),
];

class PantallaPagarProveedor extends StatefulWidget {
  const PantallaPagarProveedor({super.key});

  @override
  State<PantallaPagarProveedor> createState() => _PantallaPagarProveedorState();
}

class _PantallaPagarProveedorState extends State<PantallaPagarProveedor> {
  ServicioCompanion? _servicio;
  int? _usuarioId;

  /// null si la caja está cerrada: los pagos "fuera de la caja" andan igual.
  int? _sesionCajaId;

  List<ProveedorCompanion> _proveedores = const [];
  Map<int, int> _saldos = const {};
  int? _proveedorId;
  String _origen = 'cajon';

  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _errorInicial;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    setState(() {
      _cargando = true;
      _errorInicial = null;
    });
    try {
      final conexion = await leerConexion();
      final usuario = await leerUsuario();
      if (usuario == null) throw const ErrorCompanion(0, 'Falta elegir usuario.');
      if (conexion == null) {
        throw const ErrorCompanion(
          400,
          'Pagarle a un proveedor se hace conectado a la PC del local. '
          'Emparejá este celular con la PC y conectate al wifi del local.',
        );
      }
      final servicio = await resolverServicioCompanion(conexion);
      final proveedores = await servicio.proveedores();
      final saldos = await servicio.saldosProveedores();
      final sesion = await servicio.sesion();
      if (!mounted) return;
      setState(() {
        _servicio = servicio;
        _usuarioId = usuario.id;
        _proveedores = proveedores;
        _saldos = saldos;
        _sesionCajaId = sesion.abierta ? sesion.id : null;
      });
    } catch (e) {
      if (mounted) setState(() => _errorInicial = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _elegirProveedor(ProveedorCompanion p) {
    setState(() {
      _proveedorId = p.id;
      // Con deuda cargada se sugiere pagarla entera; sin deuda, el monto lo
      // escribe quien paga.
      final saldo = _saldos[p.id] ?? 0;
      _montoCtrl.text = saldo > 0 ? formatearARS(saldo, conSigno: false) : '';
      _error = null;
    });
  }

  Future<void> _confirmar() async {
    final proveedorId = _proveedorId;
    if (proveedorId == null) {
      setState(() => _error = 'Elegí a quién le pagás');
      return;
    }
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a cero');
      return;
    }
    if (_origen != 'fuera' && _sesionCajaId == null) {
      setState(() => _error = 'No hay caja abierta: abrila desde Inicio o elegí "Fuera de la caja".');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _servicio!.pagarProveedor(
        proveedorId: proveedorId,
        usuarioId: _usuarioId!,
        montoCentavos: monto,
        origen: _origen,
        sesionCajaId: _origen == 'fuera' ? null : _sesionCajaId,
        nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago al proveedor anotado')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _resumen() {
    final saldo = _saldos[_proveedorId] ?? 0;
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      return '';
    }
    if (monto <= 0) return '';
    if (saldo <= 0) return 'No tiene deuda cargada: el pago se anota igual como gasto con este proveedor.';
    if (monto < saldo) return 'Después de este pago le seguís debiendo ${formatearARS(saldo - monto)}.';
    if (monto == saldo) return 'Se paga toda la deuda.';
    return 'Se paga toda la deuda y ${formatearARS(monto - saldo)} más se anotan como pago sin deuda previa.';
  }

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentos;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pagar proveedor')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _servicio == null
            ? EstadoError(mensaje: _errorInicial ?? 'No se pudo conectar.', onReintentar: _iniciar)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(Espaciado.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('¿A quién le pagás?', style: textTheme.labelMedium),
                    const SizedBox(height: Espaciado.sm),
                    Wrap(
                      spacing: Espaciado.sm,
                      runSpacing: Espaciado.sm,
                      children: [
                        for (final p in _proveedores)
                          ChipSeleccionable(
                            texto: (_saldos[p.id] ?? 0) > 0 ? '${p.nombre} · ${formatearARS(_saldos[p.id]!)}' : p.nombre,
                            seleccionado: _proveedorId == p.id,
                            onTap: () => _elegirProveedor(p),
                          ),
                      ],
                    ),
                    const SizedBox(height: Espaciado.lg),
                    if (_error != null) ...[
                      ErrorEnLinea(_error!),
                      const SizedBox(height: Espaciado.md),
                    ],
                    Superficie(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CampoPlata(controller: _montoCtrl, etiqueta: 'Monto', onChanged: (_) => setState(() {})),
                          if (_proveedorId != null && _resumen().isNotEmpty) ...[
                            const SizedBox(height: Espaciado.sm),
                            Text(_resumen(), style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario)),
                          ],
                          const SizedBox(height: Espaciado.lg),
                          CampoTexto(controller: _notaCtrl, etiqueta: 'Nota (opcional)'),
                          const SizedBox(height: Espaciado.lg),
                          Text('¿De dónde sale la plata?', style: textTheme.labelMedium),
                          const SizedBox(height: Espaciado.sm),
                          Wrap(
                            spacing: Espaciado.sm,
                            runSpacing: Espaciado.sm,
                            children: [
                              for (final o in _origenes)
                                ChipSeleccionable(
                                  texto: o.etiqueta,
                                  seleccionado: _origen == o.clave,
                                  onTap: () => setState(() => _origen = o.clave),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espaciado.xl),
                    FilledButton(
                      onPressed: _guardando ? null : _confirmar,
                      style: FilledButton.styleFrom(backgroundColor: acentos.mixto, foregroundColor: acentos.textoSobreColor),
                      child: _guardando
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Anotar pago'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
