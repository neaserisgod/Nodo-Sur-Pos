// Modal del arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12) — se
// abre desde el aviso de la pantalla de venta (ver `pantalla_venta.dart`,
// `VentaControlador.arqueoIntermedioVencido`; ya no bloquea la venta,
// Bruno 2026-09-15). No cierra la sesión ni separa cigarrillos de verdad,
// solo queda registrado (`registrarArqueoIntermedio`).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fila_dato.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'arqueo_intermedio_controlador.dart';

/// true si se confirmó el arqueo — false si se canceló sin terminar (el
/// llamador vuelve a ver el aviso, `arqueoIntermedioVencido` sigue en true).
Future<bool> mostrarDialogoArqueoIntermedio(
  BuildContext context, {
  required AppDatabase db,
  required int sesionId,
  required int usuarioId,
}) async {
  final confirmado = await mostrarModal<bool>(
    context,
    builder: (context) => _DialogoArqueoIntermedio(
      db: db,
      sesionId: sesionId,
      usuarioId: usuarioId,
    ),
  );
  return confirmado ?? false;
}

class _DialogoArqueoIntermedio extends StatefulWidget {
  const _DialogoArqueoIntermedio({
    required this.db,
    required this.sesionId,
    required this.usuarioId,
  });

  final AppDatabase db;
  final int sesionId;
  final int usuarioId;

  @override
  State<_DialogoArqueoIntermedio> createState() =>
      _DialogoArqueoIntermedioState();
}

class _DialogoArqueoIntermedioState extends State<_DialogoArqueoIntermedio> {
  late final ArqueoIntermedioControlador _c;

  @override
  void initState() {
    super.initState();
    _c = ArqueoIntermedioControlador(widget.db, sesionId: widget.sesionId);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _confirmarArqueo(BuildContext context) async {
    final guardado = await _c.confirmarArqueo(usuarioId: widget.usuarioId);
    if (guardado && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ArqueoIntermedioControlador>.value(
      value: _c,
      child: Consumer<ArqueoIntermedioControlador>(
        builder: (context, c, _) {
          return switch (c.fase) {
            FaseArqueoIntermedio.conteo => Modal(
              titulo: 'Arqueo obligatorio',
              contenido: _ContenidoConteo(c: c),
              botones: [
                BotonPrimario(
                  texto: 'Confirmar conteo',
                  onPressed: c.confirmarConteo,
                ),
              ],
            ),
            FaseArqueoIntermedio.revisado => Modal(
              titulo: 'Arqueo obligatorio',
              contenido: _ContenidoRevisado(c: c),
              botones: [
                BotonPrimario(
                  texto: 'Confirmar arqueo',
                  onPressed: () => _confirmarArqueo(context),
                ),
              ],
            ),
          };
        },
      ),
    );
  }
}

class _ContenidoConteo extends StatelessWidget {
  const _ContenidoConteo({required this.c});
  final ArqueoIntermedioControlador c;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pasaron 2 horas desde el último arqueo. Contá el efectivo del '
          'cajón, cigarrillos incluidos, antes de seguir vendiendo.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_efectivo_contado_intermedio'),
          controller: c.efectivoContadoCtrl,
          autofocus: true,
          etiqueta: 'Efectivo contado',
          onSubmitted: (_) => c.confirmarConteo(),
        ),
        if (c.error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(c.error!, style: TextStyle(color: context.colores.error)),
        ],
      ],
    );
  }
}

class _ContenidoRevisado extends StatelessWidget {
  const _ContenidoRevisado({required this.c});
  final ArqueoIntermedioControlador c;

  @override
  Widget build(BuildContext context) {
    final r = c.resumen!;
    final colorDiferencia = r.diferenciaCentavos == 0
        ? null
        : context.colores.error;
    final mpDiferencia = r.mpDiferenciaCentavos;
    final colorDiferenciaMp = mpDiferencia == null || mpDiferencia == 0
        ? null
        : context.colores.error;
    final lataDiferencia = c.lataDiferenciaCentavos;
    final colorDiferenciaLata = lataDiferencia == null || lataDiferencia == 0
        ? null
        : context.colores.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoPlata(
          key: const Key('campo_efectivo_contado_intermedio_revisado'),
          controller: c.efectivoContadoCtrl,
          etiqueta: 'Efectivo contado (se puede corregir)',
        ),
        const SizedBox(height: Espaciado.md),
        FilaDato(
          etiqueta: 'Caja esperada',
          valor: formatearARS(r.efectivoEsperadoCentavos),
        ),
        FilaDato(
          etiqueta: 'Diferencia',
          valor: formatearARS(r.diferenciaCentavos),
          enfasis: true,
          color: colorDiferencia,
        ),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_mp_contado_intermedio'),
          controller: c.mpContadoCtrl,
          etiqueta: 'MP contado (según la app de Mercado Pago)',
        ),
        if (mpDiferencia != null) ...[
          const SizedBox(height: Espaciado.md),
          FilaDato(
            etiqueta: 'MP esperado',
            valor: formatearARS(r.mpEsperadoCentavos),
          ),
          FilaDato(
            etiqueta: 'Diferencia',
            valor: formatearARS(mpDiferencia),
            enfasis: true,
            color: colorDiferenciaMp,
          ),
        ],
        if (moduloActivo(Modulo.cajaAparte)) ...[
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_lata_contada_intermedio'),
          controller: c.lataContadoCtrl,
          etiqueta: 'Lata contada',
        ),
        if (lataDiferencia != null) ...[
          const SizedBox(height: Espaciado.md),
          FilaDato(
            etiqueta: 'Lata esperada',
            valor: formatearARS(c.lataEsperadaCentavos!),
          ),
          FilaDato(
            etiqueta: 'Diferencia',
            valor: formatearARS(lataDiferencia),
            enfasis: true,
            color: colorDiferenciaLata,
          ),
        ],
        ],
        if (c.error != null) ...[
          const SizedBox(height: Espaciado.md),
          Text(c.error!, style: TextStyle(color: context.colores.error)),
        ],
      ],
    );
  }
}
