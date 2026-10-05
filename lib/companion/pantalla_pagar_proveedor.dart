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
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';

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
      Navigator.of(context).pop();
      mostrarAvisoNs(context, 'Pago al proveedor anotado');
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
    final ns = context.ns;
    final saldo = _saldos[_proveedorId] ?? 0;
    final resumen = _proveedorId == null ? '' : _resumen();
    Widget etiqueta(String t) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Text(t, style: estiloNs(13, peso: FontWeight.w500, color: ns.mute)));
    return PaginaNs(
      titulo: 'Pagar proveedor',
      cuerpo: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _servicio == null
          ? ListView(children: [EstadoErrorNs(texto: _errorInicial ?? 'No se pudo conectar.', onReintentar: _iniciar)])
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                etiqueta('Proveedor'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _proveedores) ChipNs(texto: p.nombre, activo: _proveedorId == p.id, onTap: () => _elegirProveedor(p)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_proveedorId != null) FilaClaveValorNs(clave: 'Saldo con este proveedor', valor: formatearARS(saldo), tamanioValor: 17),
                const SizedBox(height: 4),
                CampoNs(etiqueta: 'Monto', controller: _montoCtrl, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs, onChanged: (_) => setState(() {})),
                if (resumen.isNotEmpty) ...[const SizedBox(height: 8), InfoNs(resumen)],
                const SizedBox(height: 10),
                CampoNs(etiqueta: 'Nota (opcional)', controller: _notaCtrl, placeholder: 'Ej: pedido del jueves'),
                const SizedBox(height: 14),
                etiqueta('De dónde salió la plata'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in _origenes) ChipNs(texto: o.etiqueta, activo: _origen == o.clave, onTap: () => setState(() => _origen = o.clave)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
      botones: [
        if (_servicio != null) ...[
          if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
          BotonNs.primario(context, _guardando ? 'Anotando…' : 'Anotar pago', _guardando ? null : _confirmar, habilitado: !_guardando),
        ],
      ],
    );
  }
}
