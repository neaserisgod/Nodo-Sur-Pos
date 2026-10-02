// Movimiento de caja — fusiona "Gasto rápido" e "Ingreso rápido" (El dueño,
// 2026-09-18: "reacomodación de absolutamente todos los elementos... no
// cambios de skin"). Eran dos pantallas casi idénticas (mismo formulario,
// misma `SesionAbiertaGate`, mismas tres cajas) que solo diferían en qué
// endpoint llamaban y en la etiqueta — dos accesos en el menú para una
// misma idea ("anotar un movimiento de caja que no es una venta"). Un
// selector Gasto/Ingreso arriba reemplaza la necesidad de dos pantallas y
// dos accesos separados.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'sesion_abierta_gate.dart';
import 'tema/colores_companion.dart';
import '../ui/comun/estado_error.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

enum TipoMovimientoCaja { gasto, ingreso }

class PantallaMovimientoCaja extends StatefulWidget {
  const PantallaMovimientoCaja({super.key, this.tipoInicial = TipoMovimientoCaja.gasto});

  final TipoMovimientoCaja tipoInicial;

  @override
  State<PantallaMovimientoCaja> createState() => _PantallaMovimientoCajaState();
}

class _PantallaMovimientoCajaState extends State<PantallaMovimientoCaja> {
  late TipoMovimientoCaja _tipo = widget.tipoInicial;

  ServicioCompanion? _cliente;
  bool _pcEmparejada = false;
  int? _usuarioId;

  /// null mientras no se sabe si hay sesión abierta o no.
  int? _sesionCajaId;

  final _montoCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController();
  MedioGastoCompanion _medio = MedioGastoCompanion.cajonNormal;
  bool _guardando = false;
  bool _cargandoInicial = true;
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
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    setState(() {
      _cargandoInicial = true;
      _errorInicial = null;
    });
    try {
      final conexion = await leerConexion();
      final usuario = await leerUsuario();
      if (usuario == null) {
        throw const ErrorCompanion(0, 'Falta elegir usuario.');
      }
      final servicio = conexion == null
          ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
          : await resolverServicioCompanion(conexion);
      if (!mounted) return;
      setState(() {
        _cliente = servicio;
        _pcEmparejada = conexion != null;
        _usuarioId = usuario.id;
      });
    } catch (e) {
      if (mounted) setState(() => _errorInicial = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargandoInicial = false);
    }
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
      setState(() => _error = 'El monto tiene que ser mayor a cero');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (_tipo == TipoMovimientoCaja.gasto) {
        await _cliente!.registrarGasto(
          sesionCajaId: _sesionCajaId!,
          usuarioId: _usuarioId!,
          montoCentavos: monto,
          medio: _medio,
          motivo: _motivoCtrl.text,
        );
      } else {
        await _cliente!.registrarIngreso(
          sesionCajaId: _sesionCajaId!,
          usuarioId: _usuarioId!,
          montoCentavos: monto,
          medio: _medio,
          motivo: _motivoCtrl.text,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tipo == TipoMovimientoCaja.gasto ? 'Gasto anotado' : 'Ingreso anotado')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentos;
    final colorTipo = _tipo == TipoMovimientoCaja.gasto ? acentos.mixto : acentos.dinero;
    return Scaffold(
      appBar: AppBar(title: const Text('Movimiento de caja')),
      body: SafeArea(
        child: _cargandoInicial
            ? const Center(child: CircularProgressIndicator())
            : _cliente == null
            ? EstadoError(
                mensaje: _errorInicial ?? 'No se pudo conectar.',
                onReintentar: _iniciar,
              )
            : _sesionCajaId == null
            ? SesionAbiertaGate(
                cliente: _cliente!,
                usuarioId: _usuarioId!,
                onLista: (id) => setState(() => _sesionCajaId = id),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(Espaciado.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AvisoModoLocal(servicio: _cliente, pcEmparejada: _pcEmparejada),
                    SegmentedButton<TipoMovimientoCaja>(
                      segments: const [
                        ButtonSegment(
                          value: TipoMovimientoCaja.gasto,
                          label: Text('Gasto'),
                          icon: Icon(IconosPlazoleta.removeCircleOutline),
                        ),
                        ButtonSegment(
                          value: TipoMovimientoCaja.ingreso,
                          label: Text('Ingreso'),
                          icon: Icon(IconosPlazoleta.addCircleOutline),
                        ),
                      ],
                      selected: {_tipo},
                      onSelectionChanged: (s) => setState(() => _tipo = s.first),
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
                          CampoPlata(controller: _montoCtrl, etiqueta: 'Monto', textInputAction: TextInputAction.next),
                          const SizedBox(height: Espaciado.lg),
                          CampoTexto(
                            controller: _motivoCtrl,
                            etiqueta: 'Motivo (opcional)',
                          ),
                          const SizedBox(height: Espaciado.lg),
                          SegmentedButton<MedioGastoCompanion>(
                            segments: const [
                              ButtonSegment(
                                value: MedioGastoCompanion.cajonNormal,
                                label: Text('Cajón normal'),
                              ),
                              ButtonSegment(
                                value: MedioGastoCompanion.lata,
                                label: Text('Lata cigarrillos'),
                              ),
                              ButtonSegment(
                                value: MedioGastoCompanion.mercadoPago,
                                label: Text('Mercado Pago'),
                              ),
                            ],
                            selected: {_medio},
                            onSelectionChanged: (s) => setState(() => _medio = s.first),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espaciado.xl),
                    FilledButton(
                      onPressed: _guardando ? null : _confirmar,
                      style: FilledButton.styleFrom(backgroundColor: colorTipo, foregroundColor: acentos.textoSobreColor),
                      child: _guardando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_tipo == TipoMovimientoCaja.gasto ? 'Anotar gasto' : 'Anotar ingreso'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
