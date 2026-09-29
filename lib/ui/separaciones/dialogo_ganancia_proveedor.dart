// La ganancia de un proveedor: retenerla como colchón o retirarla (Regla
// 13). Se abre tocando la tarjeta del proveedor en Separaciones → "Lo
// vendido" (2026-09-26 — antes vivía en Reportes, que se sacó del menú:
// "Retener como colchón" y "Retirar ganancia" eran lo único que Reportes
// tenía que no estuviera ya en Separaciones).
//
// La ganancia de acá es la SIN REVISAR — desde la última vez que se retuvo o
// retiró la de ese proveedor (`gananciaRevisadaFecha`), no la del período
// elegido arriba en "Lo vendido": son cortes distintos a propósito (retener
// o retirar cierra la revisión, y lo siguiente arranca de cero).

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/fila_dato.dart';
import '../comun/modal.dart';
import '../tema/acentos.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import 'dialogo_retirar_ganancia.dart';
import 'separaciones_controlador.dart';

Future<void> mostrarDialogoGananciaProveedor(
  BuildContext context, {
  required SeparacionesControlador controlador,
  required int proveedorId,
}) {
  return mostrarModal<void>(
    context,
    builder: (_) => ListenableBuilder(
      listenable: controlador,
      builder: (_, _) => _DialogoGanancia(
        controlador: controlador,
        proveedorId: proveedorId,
        // El de la pantalla, no el del diálogo: "Retirar ganancia" cierra
        // este diálogo y abre otro — el contexto de este ya no sirve.
        contextoPantalla: context,
      ),
    ),
  );
}

class _DialogoGanancia extends StatelessWidget {
  const _DialogoGanancia({required this.controlador, required this.proveedorId, required this.contextoPantalla});

  final SeparacionesControlador controlador;
  final int proveedorId;
  final BuildContext contextoPantalla;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final g = c.gananciaSinRevisar[proveedorId];
    final proveedor = g?.proveedor;
    final ganancia = g?.gananciaCentavos ?? 0;
    final desde = proveedor?.gananciaRevisadaFecha;
    final procesando = c.procesando.contains(proveedorId);
    final sinCaja = c.sesionCajaId == null;
    final habilitado = !procesando && !sinCaja && ganancia > 0;

    return Modal(
      titulo: 'Ganancia — ${proveedor?.nombre ?? ''}',
      subtitulo: 'Precio de venta menos costo',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "Lenguaje de diseño" (mock `DialogosSeparaciones` → Ganancia):
          // la ganancia como pieza destacada, lo vendido y el costo abajo.
          Superficie(
            key: const Key('ganancia_sin_revisar'),
            degrade: acentos.gradienteAcento,
            padding: const EdgeInsets.all(Espaciado.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ganancia sin revisar',
                  style: textTheme.labelLarge?.copyWith(color: acentos.textoSobreColor.withValues(alpha: 0.75)),
                ),
                Text(
                  formatearARS(ganancia),
                  style: textTheme.displaySmall?.copyWith(color: acentos.textoSobreColor, fontWeight: Pesos.fuerte).tabular,
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.md),
          FilaDato(etiqueta: 'Vendido sin revisar', valor: formatearARS(g?.vendidoCentavos ?? 0)),
          const SizedBox(height: Espaciado.sm),
          FilaDato(etiqueta: 'Costo de lo vendido', valor: formatearARS((g?.vendidoCentavos ?? 0) - ganancia)),
          const SizedBox(height: Espaciado.sm),
          Text(
            desde == null
                ? 'Desde siempre (nunca se revisó).'
                : 'Desde el ${desde.day.toString().padLeft(2, '0')}/${desde.month.toString().padLeft(2, '0')}, '
                    'la última vez que se retuvo o retiró.',
            style: TextStyle(color: colores.textoSecundario),
          ),
          if (sinCaja) ...[
            const SizedBox(height: Espaciado.sm),
            Text('Para retener o retirar hay que abrir la caja.', style: TextStyle(color: colores.textoSecundario)),
          ] else if (ganancia <= 0) ...[
            const SizedBox(height: Espaciado.sm),
            Text('No hay ganancia sin revisar.', style: TextStyle(color: colores.textoSecundario)),
          ],
        ],
      ),
      // Sin "Cerrar": se cierra con Esc o tocando afuera, como todo `Modal`.
      botones: [
        BotonSecundario(
          texto: 'Retener como colchón',
          onPressed: habilitado
              ? () {
                  Navigator.of(context).pop();
                  c.retenerComoColchon(proveedorId, ganancia);
                }
              : null,
        ),
        BotonPrimario(
          texto: 'Retirar ganancia',
          onPressed: habilitado
              ? () {
                  Navigator.of(context).pop();
                  mostrarDialogoRetirarGanancia(
                    contextoPantalla,
                    controlador: c,
                    proveedorId: proveedorId,
                    nombreProveedor: proveedor!.nombre,
                    gananciaCentavos: ganancia,
                  );
                }
              : null,
        ),
      ],
    );
  }
}
