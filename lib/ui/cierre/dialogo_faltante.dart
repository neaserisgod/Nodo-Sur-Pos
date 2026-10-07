// "¿A dónde fueron?" (El dueño, 2026-10-07): un faltante del cierre se explica en el momento, con un toque, en vez de
// quedar como diferencia. Así la plata que salió para un proveedor, un fijo o un gasto personal deja de figurar como
// ganancia retirable en Equilibrio. El monto viene con el faltante entero y se puede bajar: si fue en dos partes (un
// proveedor y el resto un gasto propio), se anota una y el diálogo se vuelve a abrir con lo que queda.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_deuda_proveedores.dart' show saldosDeuda;
import '../../data/repositorio_faltantes.dart';
import '../../domain/dinero.dart';
import '../../domain/faltantes_cierre.dart';
import '../kit/kit.dart';
import 'cierre_controlador.dart';

String nombreCaja(CajaDelCierre caja) => switch (caja) {
  CajaDelCierre.efectivo => 'el cajón',
  CajaDelCierre.mercadoPago => 'Mercado Pago',
  CajaDelCierre.lata => 'la lata de cigarrillos',
};

Future<void> mostrarDialogoFaltante(
  BuildContext context, {
  required CierreControlador c,
  required CajaDelCierre caja,
  required int faltanteCentavos,
  required int usuarioId,
}) async {
  final proveedores = await (c.db.select(c.db.proveedores)..where((p) => p.activo.equals(true))).get();
  final deudas = await saldosDeuda(c.db);
  // Los que tienen deuda primero (lo más probable es que se le haya pagado a uno de esos), después por nombre.
  proveedores.sort((a, b) {
    final porDeuda = (deudas[b.id] ?? 0).compareTo(deudas[a.id] ?? 0);
    return porDeuda != 0 ? porDeuda : a.nombre.compareTo(b.nombre);
  });
  final fijos = await (c.db.select(c.db.gastosFijos)..where((g) => g.activo.equals(true))).get();
  if (!context.mounted) return;
  await mostrarModalMock<void>(
    context,
    builder: (_) => _DialogoFaltante(
      c: c,
      caja: caja,
      faltanteCentavos: faltanteCentavos,
      usuarioId: usuarioId,
      proveedores: proveedores,
      deudas: deudas,
      fijos: fijos,
    ),
  );
}

class _DialogoFaltante extends StatefulWidget {
  const _DialogoFaltante({
    required this.c,
    required this.caja,
    required this.faltanteCentavos,
    required this.usuarioId,
    required this.proveedores,
    required this.deudas,
    required this.fijos,
  });

  final CierreControlador c;
  final CajaDelCierre caja;
  final int faltanteCentavos;
  final int usuarioId;
  final List<Proveedor> proveedores;
  final Map<int, int> deudas;
  final List<GastoFijo> fijos;

  @override
  State<_DialogoFaltante> createState() => _DialogoFaltanteState();
}

class _DialogoFaltanteState extends State<_DialogoFaltante> {
  late final _montoCtrl = TextEditingController(text: formatearARS(widget.faltanteCentavos, conSigno: false));
  final _notaCtrl = TextEditingController();
  DestinoFaltante _destino = DestinoFaltante.gastoMio;
  int? _proveedorId;
  int? _fijoId;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _anotar() async {
    if (_guardando) return;
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      setState(() => _error = 'Revisá el monto');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a cero');
      return;
    }
    if (_destino == DestinoFaltante.proveedor && _proveedorId == null) {
      setState(() => _error = 'Elegí a qué proveedor');
      return;
    }
    if (_destino == DestinoFaltante.fijo && _fijoId == null) {
      setState(() => _error = 'Elegí qué fijo');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.c.explicarFaltante(
      usuarioId: widget.usuarioId,
      caja: widget.caja,
      montoCentavos: monto,
      destino: _destino,
      proveedorId: _proveedorId,
      gastoFijoId: _fijoId,
      nota: _notaCtrl.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _guardando = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _meEquivoque() {
    Navigator.of(context).pop();
    widget.c.volverAContar();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final opciones = [
      (DestinoFaltante.gastoMio, 'Gasto mío'),
      (DestinoFaltante.proveedor, 'Proveedor'),
      if (destinoPosible(DestinoFaltante.fijo, widget.caja)) (DestinoFaltante.fijo, 'Fijo (luz, alquiler…)'),
      (DestinoFaltante.negocio, 'Otro gasto del negocio'),
    ];
    return ModalMock(
      titulo: '¿A dónde fueron?',
      subtitulo: 'Faltan ${pesos(widget.faltanteCentavos)} en ${nombreCaja(widget.caja)}. Si lo anotás, Equilibrio deja de '
          'contarlo como ganancia que tenés.',
      cuerpo: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (destino, texto) in opciones)
              ChipMock(
                texto,
                key: Key('faltante_destino_${destino.name}'),
                elegido: _destino == destino,
                onTap: () => setState(() => _destino = destino),
              ),
          ],
        ),
        if (_destino == DestinoFaltante.gastoMio)
          Text(
            'Lo que pagaste para vos con plata del negocio. Cuenta como retiro: no es un gasto del negocio, es tuyo.',
            style: estilo(14, 400, color: p.mute, alto: 1.4),
          ),
        if (_destino == DestinoFaltante.proveedor)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prov in widget.proveedores)
                ChipMock(
                  (widget.deudas[prov.id] ?? 0) > 0 ? '${prov.nombre} · debés ${pesos(widget.deudas[prov.id]!)}' : prov.nombre,
                  chico: true,
                  elegido: _proveedorId == prov.id,
                  onTap: () => setState(() => _proveedorId = prov.id),
                ),
            ],
          ),
        if (_destino == DestinoFaltante.fijo)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in widget.fijos)
                ChipMock(f.nombre, chico: true, elegido: _fijoId == f.id, onTap: () => setState(() => _fijoId = f.id)),
            ],
          ),
        Campo(
          etiqueta: 'Monto',
          campoKey: const Key('faltante_monto'),
          controller: _montoCtrl,
          teclado: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _anotar(),
        ),
        if (_destino != DestinoFaltante.fijo)
          Campo(
            etiqueta: 'Nota (opcional)',
            controller: _notaCtrl,
            pista: switch (_destino) {
              DestinoFaltante.gastoMio => 'Ej: supermercado, servicio de casa…',
              DestinoFaltante.proveedor => 'Ej: transferencia',
              _ => 'Ej: bolsas, limpieza…',
            },
            onSubmitted: (_) => _anotar(),
          ),
        if (_error != null) Text(_error!, style: estilo(15, 500, color: p.b)),
      ],
      pie: [
        Btn('Anotar', key: const Key('faltante_anotar'), variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: _guardando ? null : _anotar),
        Btn('Me equivoqué al contar', variante: VarBtn.out, ancho: true, onTap: _meEquivoque),
      ],
    );
  }
}
