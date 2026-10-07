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
import '../../domain/rentabilidad.dart';
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

  Future<void> _confirmar() async {
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
    final motivo = motivoParaNoRetirar(efectivoCentavos: efectivo, virtualCentavos: virtual, gananciaCentavos: widget.gananciaCentavos);
    if (motivo != null) {
      setState(() => _error = motivo);
      return;
    }
    // Asistente contable: la ganancia bruta no es plata libre (faltan pagar
    // los gastos). Se retira igual si el dueño lo decide, pero avisando
    // cuánto se pasa de lo retirable (El dueño, 2026-10-01: "avisa y pide
    // confirmar").
    if (efectivo + virtual > 0) {
      final estado = await widget.controlador.estadoDelMes();
      if (!mounted) return;
      final evaluacion = evaluarRetiro(montoCentavos: efectivo + virtual, estado: estado);
      if (evaluacion.requiereConfirmacion) {
        final seguir = await mostrarModal<bool>(
          context,
          builder: (context) => _AvisoRetiroEnExceso(evaluacion: evaluacion, estado: estado),
        );
        if (seguir != true || !mounted) return;
      }
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

/// El aviso de "te pasás": cuánto es realmente retirable este mes y cuánto se
/// excede el retiro. Se puede confirmar igual — la decisión es del dueño.
class _AvisoRetiroEnExceso extends StatelessWidget {
  const _AvisoRetiroEnExceso({required this.evaluacion, required this.estado});

  final EvaluacionDeRetiro evaluacion;
  final EstadoDeResultados estado;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Modal(
      titulo: 'Estás retirando más de lo que el negocio ganó',
      subtitulo: 'Después de pagar los gastos del mes',
      ancho: 560,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Fila('Ganancia bruta del mes', formatearARS(estado.gananciaBrutaCentavos)),
          _Fila('Gastos fijos y variables', '− ${formatearARS(estado.gastosFijosCentavos + estado.gastosVariablesCentavos)}'),
          _Fila('Ya retirado este mes', '− ${formatearARS(estado.retirosDelMesCentavos)}'),
          const Divider(),
          _Fila('Retirable hoy', formatearARS(evaluacion.retirableCentavos), fuerte: true),
          _Fila('Querés retirar', formatearARS(evaluacion.montoCentavos)),
          _Fila('Te pasás por', formatearARS(evaluacion.excedeCentavos), fuerte: true),
          const SizedBox(height: Espaciado.md),
          Text(
            'Esa plata la va a necesitar el negocio para pagar sus gastos. Si retirás igual, queda registrado.',
            style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
          ),
          if (!estado.esCompleto) ...[
            const SizedBox(height: Espaciado.sm),
            Text(
              'Ojo: faltan datos (ventas sin costo o fijos sin cargar), así que lo retirable puede ser menos todavía.',
              style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
            ),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
        BotonPrimario(texto: 'Retirar igual', onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.valor, {this.fuerte = false});

  final String etiqueta;
  final String valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: fuerte ? Pesos.fuerte : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: estilo)),
          Text(valor, style: estilo.tabular),
        ],
      ),
    );
  }
}
