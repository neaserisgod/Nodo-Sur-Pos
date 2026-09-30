// Campo aparte para la parte en efectivo de un pago mixto — a propósito no
// reutiliza el campo único: si el monto entrara por ahí, un escaneo
// accidental mientras se carga el número se leería como plata. Alt+X abre
// este diálogo, y el foco vuelve solo al campo único al cerrarse (ver
// pantalla_venta.dart).
//
// Fase 12 (cobro por Point): confirmar ya no es una sola tecla — es también
// la elección del canal para el resto (El dueño, ESTADO.md: "la confirmación
// del monto en efectivo pasa a ser también la elección del canal, sin
// tecla extra"). Alt+Q confirma con el resto por QR, Alt+D por Débito,
// Enter (o el botón) confirma por QR — mismo default que el reflejo de
// hoy. Estas dos teclas son LOCALES a este diálogo (`CallbackShortcuts`),
// no pasan por el handler global de `pantalla_venta.dart`: mientras este
// diálogo está abierto, esa ruta ya no es la actual y el handler global se
// desactiva solo (`ModalRoute.isCurrent`, ver TRAMPAS.md) — las dos rutas
// de Alt+Q/Alt+D nunca se pisan.
//
// "Lenguaje de diseño" (mock `DialogosVenta` → Pago mixto): el resto por
// Mercado Pago se ve calculado al lado mientras se escribe, con una barra de
// la proporción y atajos de montos redondos — quien cobra ve de un vistazo
// cuánto recibe en mano y por cuánto sale la orden a la terminal.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/acentos.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';

/// Devuelve el monto en efectivo y el canal elegido para el resto, o null
/// si se canceló.
Future<({int monto, String canal})?> mostrarDialogoMixto(
  BuildContext context, {
  required int totalCentavos,
}) {
  return mostrarModal<({int monto, String canal})>(
    context,
    builder: (context) => _DialogoMixto(totalCentavos: totalCentavos),
  );
}

class _DialogoMixto extends StatefulWidget {
  const _DialogoMixto({required this.totalCentavos});
  final int totalCentavos;

  @override
  State<_DialogoMixto> createState() => _DialogoMixtoState();
}

class _DialogoMixtoState extends State<_DialogoMixto> {
  final _controlador = TextEditingController();
  final _foco = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _foco.requestFocus());
  }

  /// Lo escrito hasta ahora, o null si todavía no es un monto.
  int? get _efectivo {
    try {
      return parsearARS(_controlador.text.isEmpty ? '0' : _controlador.text);
    } on FormatException {
      return null;
    }
  }

  void _fijar(int monto) {
    _controlador.text = formatearARS(monto, conSigno: false);
    _controlador.selection = TextSelection.collapsed(offset: _controlador.text.length);
    setState(() => _error = null);
    _foco.requestFocus();
  }

  void _confirmar({String canal = 'qr'}) {
    final monto = _efectivo;
    if (monto == null) {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto < 0 || monto > widget.totalCentavos) {
      setState(() => _error = 'Tiene que ser entre \$0 y ${formatearARS(widget.totalCentavos)}');
      return;
    }
    Navigator.of(context).pop((monto: monto, canal: canal));
  }

  @override
  void dispose() {
    _controlador.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final total = widget.totalCentavos;
    final efectivo = (_efectivo ?? 0).clamp(0, total);
    final resto = total - efectivo;
    // Mitad redondeada al peso entero hacia arriba (convención 5).
    final mitad = (total / 200).ceil() * 100;
    final redondos = [500000, 1000000, 2000000].where((m) => m < total).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyQ, alt: true): () => _confirmar(canal: 'qr'),
        const SingleActivator(LogicalKeyboardKey.keyD, alt: true): () => _confirmar(canal: 'debit_card'),
      },
      child: Modal(
        titulo: 'Pago mixto',
        subtitulo: 'Total de la venta ${formatearARS(total)}',
        ancho: 620,
        contenido: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CampoPlata(
                    controller: _controlador,
                    focusNode: _foco,
                    autofocus: true,
                    etiqueta: 'En efectivo',
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _confirmar(),
                  ),
                ),
                const SizedBox(width: Espaciado.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Con Mercado Pago (el resto)', style: textTheme.labelMedium),
                      const SizedBox(height: Espaciado.xs + 2),
                      Container(
                        height: Medidas.alturaControl,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                        decoration: BoxDecoration(
                          color: colores.fondo,
                          borderRadius: BorderRadius.circular(radioControlEscritorio),
                        ),
                        child: Text(
                          formatearARS(resto),
                          style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espaciado.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (efectivo > 0) Expanded(flex: efectivo, child: ColoredBox(color: acentos.dinero)),
                    if (resto > 0) Expanded(flex: resto, child: ColoredBox(color: colores.acento)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Espaciado.md),
            Wrap(
              spacing: Espaciado.sm,
              runSpacing: Espaciado.sm,
              children: [
                for (final m in redondos) ChipAtajo(texto: formatearARS(m), elegido: efectivo == m, onTap: () => _fijar(m)),
                ChipAtajo(texto: 'Mitad', elegido: efectivo == mitad, onTap: () => _fijar(mitad)),
              ],
            ),
            const SizedBox(height: Espaciado.md),
            BloqueSuave(
              child: Text(
                'Primero cobrá los ${formatearARS(efectivo)} en mano. Después sale la orden por ${formatearARS(resto)} a la terminal.',
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: Espaciado.xs),
            Text(
              'Enter o Alt+Q: el resto por QR. Alt+D: el resto por Débito.',
              style: textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
            ),
            if (_error != null) ...[
              const SizedBox(height: Espaciado.sm),
              Text(_error!, style: TextStyle(color: colores.error)),
            ],
          ],
        ),
        botones: [
          BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
          BotonPrimario(texto: 'Cobrar mixto', onPressed: () => _confirmar()),
        ],
      ),
    );
  }
}
