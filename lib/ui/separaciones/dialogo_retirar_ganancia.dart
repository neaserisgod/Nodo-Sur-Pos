// Retiro de ganancia real (Regla 13). Desde 2026-09-26 se abre desde
// Separaciones → "Lo vendido" → tarjeta del proveedor (antes, desde Reportes,
// que se sacó del menú). El dueño, 2026-09-06: necesita poder
// volver a retirar plata al bolsillo (no solo retener como colchón, la
// única acción que quedó tras la simplificación del 2026-09-05), "pero
// todo simple: que me calcule las ganancias de manera automática en base
// al costo" — y de qué medio sale, "calculado desde cómo se vendió, o en
// su defecto editable".
//
// Los dos montos vienen prellenados con `gananciaPorMedioDesde`
// (repositorio_reposicion.dart): la proporción real en que se cobraron las
// ventas que generaron esa ganancia, no una adivinanza. Quedan editables
// para el caso sin atribución exacta (un mixto de varios productos —
// limitación conocida, ver ESTADO.md) o porque el dueño decide otra cosa. Lo
// que no se retira de los dos campos queda como colchón automáticamente
// (`revisarGananciaProveedor` ya lo hace así) — no hace falta un tercer
// campo para eso.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';
import 'separaciones_controlador.dart';

Future<void> mostrarDialogoRetirarGanancia(
  BuildContext context, {
  required SeparacionesControlador controlador,
  required int proveedorId,
  required String nombreProveedor,
  required int gananciaCentavos,
}) async {
  final sugerencia = await controlador.sugerenciaRetiro(proveedorId);
  if (!context.mounted) return;

  await mostrarModal<void>(
    context,
    builder: (context) => _DialogoRetirarGanancia(
      controlador: controlador,
      proveedorId: proveedorId,
      nombreProveedor: nombreProveedor,
      gananciaCentavos: gananciaCentavos,
      efectivoSugeridoCentavos: sugerencia.efectivoCentavos,
      virtualSugeridoCentavos: sugerencia.virtualCentavos,
    ),
  );
}

class _DialogoRetirarGanancia extends StatefulWidget {
  const _DialogoRetirarGanancia({
    required this.controlador,
    required this.proveedorId,
    required this.nombreProveedor,
    required this.gananciaCentavos,
    required this.efectivoSugeridoCentavos,
    required this.virtualSugeridoCentavos,
  });

  final SeparacionesControlador controlador;
  final int proveedorId;
  final String nombreProveedor;
  final int gananciaCentavos;
  final int efectivoSugeridoCentavos;
  final int virtualSugeridoCentavos;

  @override
  State<_DialogoRetirarGanancia> createState() =>
      _DialogoRetirarGananciaState();
}

class _DialogoRetirarGananciaState extends State<_DialogoRetirarGanancia> {
  late final _efectivoCtrl = TextEditingController(
    text: _sinSigno(widget.efectivoSugeridoCentavos),
  );
  late final _virtualCtrl = TextEditingController(
    text: _sinSigno(widget.virtualSugeridoCentavos),
  );
  String? _error;

  static String _sinSigno(int centavos) =>
      formatearARS(centavos).replaceAll('\$', '');

  void _confirmar() {
    final int efectivo;
    final int virtual;
    try {
      efectivo = parsearARS(
        _efectivoCtrl.text.isEmpty ? '0' : _efectivoCtrl.text,
      );
      virtual = parsearARS(_virtualCtrl.text.isEmpty ? '0' : _virtualCtrl.text);
    } on FormatException {
      setState(() => _error = 'Revisá los montos');
      return;
    }
    if (efectivo < 0 || virtual < 0) {
      setState(() => _error = 'Los montos no pueden ser negativos');
      return;
    }
    if (efectivo + virtual > widget.gananciaCentavos) {
      setState(
        () => _error =
            'Entre los dos no pueden superar ${formatearARS(widget.gananciaCentavos)}',
      );
      return;
    }
    widget.controlador.retirarGanancia(
      widget.proveedorId,
      gananciaCentavos: widget.gananciaCentavos,
      efectivoCentavos: efectivo,
      virtualCentavos: virtual,
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _virtualCtrl.dispose();
    super.dispose();
  }

  int _leer(TextEditingController c) {
    try {
      return parsearARS(c.text.isEmpty ? '0' : c.text);
    } on FormatException {
      return 0;
    }
  }

  // "Lenguaje de diseño" (mock `DialogosSeparaciones` → Retirar plata): los
  // dos medios lado a lado y, abajo, qué queda como colchón mientras se
  // escribe. El "para qué" y "quién retira" del mock no están: el retiro de
  // ganancia es siempre del dueño y no lleva motivo.
  @override
  Widget build(BuildContext context) {
    final retiro = _leer(_efectivoCtrl) + _leer(_virtualCtrl);
    final colchon = widget.gananciaCentavos - retiro;
    return Modal(
      titulo: 'Retirar ganancia — ${widget.nombreProveedor}',
      subtitulo: 'Ganancia disponible ${formatearARS(widget.gananciaCentavos)}',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Calculado según cómo se cobraron las ventas — se puede corregir.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_retiro_efectivo'),
                  controller: _efectivoCtrl,
                  etiqueta: 'Efectivo',
                  autofocus: true,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_retiro_virtual'),
                  controller: _virtualCtrl,
                  etiqueta: 'Mercado Pago',
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          BloqueSuave(
            child: Text(
              colchon > 0
                  ? 'Se retiran ${formatearARS(retiro)}. Los ${formatearARS(colchon)} que quedan pasan a colchón.'
                  : 'Se retiran ${formatearARS(retiro)}: la ganancia de ${widget.nombreProveedor} queda revisada.',
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Retirar', onPressed: _confirmar),
      ],
    );
  }
}
