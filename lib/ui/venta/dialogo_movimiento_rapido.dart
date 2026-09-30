// Gasto rápido (Alt+guion) e ingreso rápido (Alt+I, Bruno 2026-09-13: "un
// botón de ingreso de dinero, evidentemente siguiendo con las cajas que
// hay"): la forma más rápida de anotar plata que sale o entra sin salir de
// la pantalla de venta. Ninguno de los dos es una venta (Regla 11): escriben
// directo en `movimientos_de_caja`, no tocan `ventas`.
//
// "Lenguaje de diseño" (mock `DialogosVenta` → Movimiento rápido): los dos
// eran diálogos espejo en archivos separados; ahora son uno solo con un
// selector Gasto/Ingreso arriba. Cada atajo lo abre ya en su lado, así que
// ninguna tecla cambió. Las cajas siguen siendo tres (cajón, lata de
// cigarrillos, Mercado Pago) aunque el mock mostrara dos: la lata es una
// caja aparte con su propio arqueo (REGLAS-NEGOCIO.md), fundirla con el
// cajón descuadra el cierre.

import 'package:flutter/material.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../../data/repositorio_gastos.dart';
import '../../data/repositorio_ingresos.dart';
import '../../data/repositorio_ventas.dart' show SesionCerradaException;
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';

enum TipoMovimientoRapido { gasto, ingreso }

Future<void> mostrarDialogoGastoRapido(
  BuildContext context, {
  required AppDatabase db,
  required int sesionCajaId,
  required int usuarioId,
}) =>
    _mostrar(context, db: db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, tipo: TipoMovimientoRapido.gasto);

Future<void> mostrarDialogoIngresoRapido(
  BuildContext context, {
  required AppDatabase db,
  required int sesionCajaId,
  required int usuarioId,
}) =>
    _mostrar(context, db: db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, tipo: TipoMovimientoRapido.ingreso);

Future<void> _mostrar(
  BuildContext context, {
  required AppDatabase db,
  required int sesionCajaId,
  required int usuarioId,
  required TipoMovimientoRapido tipo,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoMovimientoRapido(db: db, sesionCajaId: sesionCajaId, usuarioId: usuarioId, tipoInicial: tipo),
  );
}

/// Motivos de un toque para los gastos de todos los días; "Otro" deja el
/// motivo en la nota nada más.
const _motivosGasto = ['Flete', 'Limpieza', 'Bolsas', 'Impuestos'];

class _DialogoMovimientoRapido extends StatefulWidget {
  const _DialogoMovimientoRapido({
    required this.db,
    required this.sesionCajaId,
    required this.usuarioId,
    required this.tipoInicial,
  });

  final AppDatabase db;
  final int sesionCajaId;
  final int usuarioId;
  final TipoMovimientoRapido tipoInicial;

  @override
  State<_DialogoMovimientoRapido> createState() => _DialogoMovimientoRapidoState();
}

class _DialogoMovimientoRapidoState extends State<_DialogoMovimientoRapido> {
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _focoMonto = FocusNode();
  late TipoMovimientoRapido _tipo = widget.tipoInicial;
  MedioGasto _medio = MedioGasto.cajonNormal;
  String? _motivo;
  String? _error;

  bool get _esGasto => _tipo == TipoMovimientoRapido.gasto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focoMonto.requestFocus());
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
    final nota = _notaCtrl.text.trim();
    final motivo = [if (_esGasto && _motivo != null) _motivo!, if (nota.isNotEmpty) nota].join(' · ');

    try {
      if (_esGasto) {
        await registrarGastoRapido(
          widget.db,
          sesionCajaId: widget.sesionCajaId,
          usuarioId: widget.usuarioId,
          montoCentavos: monto,
          medio: _medio,
          motivo: motivo,
        );
      } else {
        await registrarIngresoRapido(
          widget.db,
          sesionCajaId: widget.sesionCajaId,
          usuarioId: widget.usuarioId,
          montoCentavos: monto,
          medio: _medio,
          motivo: motivo,
        );
      }
    } on SesionCerradaException {
      // Bruno, 2026-09-19: "aislar los usuarios para que no se pisen" — la
      // caja se cerró (probablemente desde otro dispositivo) entre que se
      // abrió este diálogo y se confirmó.
      setState(() => _error = 'La caja ya se cerró, este ${_esGasto ? 'gasto' : 'ingreso'} no se guardó');
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    _focoMonto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    return Modal(
      titulo: 'Movimiento rápido',
      subtitulo: _esGasto ? 'Plata que sale de una caja' : 'Plata que entra a una caja',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GrupoPildoras<TipoMovimientoRapido>(
              opciones: const [(TipoMovimientoRapido.gasto, 'Gasto'), (TipoMovimientoRapido.ingreso, 'Ingreso')],
              elegida: _tipo,
              onElegir: (t) => setState(() => _tipo = t),
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            controller: _montoCtrl,
            focusNode: _focoMonto,
            etiqueta: 'Monto',
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          Text(_esGasto ? 'Sale de' : 'Entra a', style: textTheme.labelMedium),
          const SizedBox(height: Espaciado.xs + 2),
          Wrap(
            spacing: Espaciado.sm,
            runSpacing: Espaciado.sm,
            children: [
              for (final (medio, texto) in [
                (MedioGasto.cajonNormal, 'Cajón normal'),
                if (moduloActivo(Modulo.cajaAparte)) (MedioGasto.lata, 'Lata cigarrillos'),
                (MedioGasto.mercadoPago, 'Mercado Pago'),
              ])
                ChipAtajo(texto: texto, elegido: _medio == medio, onTap: () => setState(() => _medio = medio)),
            ],
          ),
          if (_esGasto) ...[
            const SizedBox(height: Espaciado.md),
            Text('Motivo', style: textTheme.labelMedium),
            const SizedBox(height: Espaciado.xs + 2),
            Wrap(
              spacing: Espaciado.sm,
              runSpacing: Espaciado.sm,
              children: [
                for (final m in _motivosGasto)
                  ChipAtajo(
                    texto: m,
                    elegido: _motivo == m,
                    onTap: () => setState(() => _motivo = _motivo == m ? null : m),
                  ),
                ChipAtajo(texto: 'Otro', elegido: _motivo == null, onTap: () => setState(() => _motivo = null)),
              ],
            ),
          ],
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            controller: _notaCtrl,
            etiqueta: _esGasto ? 'Nota (opcional)' : 'Motivo (opcional)',
            onSubmitted: (_) => _confirmar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: _esGasto ? 'Registrar gasto' : 'Registrar ingreso', onPressed: _confirmar),
      ],
    );
  }
}
