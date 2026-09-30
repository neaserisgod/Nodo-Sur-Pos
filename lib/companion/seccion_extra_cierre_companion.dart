// Lo que un cierre real tiene además de las tres cajas (efectivo/MP/lata
// contado-esperado-diferencia, que cada pantalla ya mostraba a su manera):
// separación de cigarrillos, redondeo acumulado, vendido sin costo cargado,
// reserva diaria de fijos, nota, y el desglose por proveedor (El dueño,
// 2026-09-19: rework de "Cierres" — "lo que se debe separar por cada
// proveedor"). Un solo widget (Regla 3) para los dos lugares donde aparece:
// la fase "revisado" del diálogo de cerrar caja (`dialogo_cierre_companion.dart`)
// y el detalle de un cierre ya guardado (`pantalla_cierres.dart`).
//
// El tilde por proveedor es un check de trabajo, no un dato de dominio: vive
// solo en este widget (`_tildados`), efímero — se resetea cada vez que se
// vuelve a abrir esta pantalla, igual que tachar un papel. No persiste en
// ningún lado ni toca `Proveedores`/Reportes (eso sigue siendo la pantalla
// "Separar por proveedor" del escritorio, con sus propios "Retener
// colchón"/"Retirar ganancia" — acá es solo lectura).

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/tema/tokens.dart';
import 'cliente_companion.dart' show ResumenCierreCompanion, ResumenProveedorDiaCompanion;
import 'pantalla_carga_historica.dart' show SeccionProductosSinDatos;
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class SeccionExtraCierreCompanion extends StatefulWidget {
  const SeccionExtraCierreCompanion({super.key, required this.resumen});

  final ResumenCierreCompanion resumen;

  @override
  State<SeccionExtraCierreCompanion> createState() => _SeccionExtraCierreCompanionState();
}

class _SeccionExtraCierreCompanionState extends State<SeccionExtraCierreCompanion> {
  final Set<int> _tildados = {};

  @override
  Widget build(BuildContext context) {
    final r = widget.resumen;
    final colores = context.colores;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bug real (El dueño: "la companion directamente no lo dice"): este
        // monto — cuánto hay que separar a la lata AHORA, en este cierre —
        // no se mostraba en ningún lado acá, solo la parte pendiente
        // cuando no alcanzaba el efectivo. Sin la línea de abajo no había
        // forma de saber cuánto plata mover a la lata mirando esta
        // pantalla — a prueba de boludos significa que el número está acá,
        // no que haya que calcularlo de memoria con el total de arriba.
        _filaDato(context, 'A separar a la lata', r.separadoCentavos),
        if (r.esSeparacionParcial)
          _filaDato(
            context,
            'De eso, no alcanza el efectivo — queda pendiente para el próximo cierre',
            r.pendienteCentavos,
            color: colores.error,
          ),
        _filaDato(context, 'Redondeo acumulado', r.redondeoAcumuladoCentavos),
        _filaDato(context, 'Vendido sin costo cargado', r.vendidoSinCostoCentavos),
        // Bug real: el total de arriba llegaba solo, sin decir QUÉ
        // productos lo componen — `productosSinDatos` ya viaja completo en
        // este mismo `resumen` (tanto la vista previa en vivo de
        // `/sesion/cerrar/calcular` como el detalle guardado de
        // `/sesiones/cerradas/<id>/detalle`, las dos arman el JSON con
        // `_resumenCierreAJson`, servidor_companion.dart) y la app ya tiene
        // este widget (Arqueo intermedio, Carga histórica), pero acá nunca
        // se conectó.
        SeccionProductosSinDatos(productos: r.productosSinDatos),
        if (r.reservaDiariaFijosCentavos == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
            child: Text(
              'Reserva diaria de fijos: sin cargar los fijos de este mes',
              style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
            ),
          )
        else
          _filaDato(context, 'Reserva diaria de fijos (informativo)', r.reservaDiariaFijosCentavos!),
        if (r.nota != null && r.nota!.trim().isNotEmpty) ...[
          const SizedBox(height: Espaciado.sm),
          Text('Nota', style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta)),
          Text(r.nota!),
        ],
        if (r.porProveedor.isNotEmpty) ...[
          const SizedBox(height: Espaciado.lg),
          Text('A separar por proveedor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          for (final p in r.porProveedor) _filaProveedor(context, p),
        ],
      ],
    );
  }

  Widget _filaProveedor(BuildContext context, ResumenProveedorDiaCompanion p) {
    final colores = context.colores;
    final tildado = _tildados.contains(p.proveedorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaciado.sm),
      child: Presionable(
        onTap: () => setState(() {
          if (tildado) {
            _tildados.remove(p.proveedorId);
          } else {
            _tildados.add(p.proveedorId);
          }
        }),
        child: Superficie(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.md, vertical: Espaciado.sm),
          child: Row(
            children: [
              Icon(
                tildado ? IconosPlazoleta.checkCircle : IconosPlazoleta.radioButtonUnchecked,
                color: tildado ? colores.acento : colores.textoSecundario,
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nombreProveedor,
                      style: TextStyle(
                        decoration: tildado ? TextDecoration.lineThrough : null,
                        color: tildado ? colores.textoSecundario : null,
                      ),
                    ),
                    Text(
                      'Ganancia sin revisar: ${formatearARS(p.gananciaCentavos)}',
                      style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
                    ),
                  ],
                ),
              ),
              Text(
                formatearARS(p.costoRealCentavos),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  decoration: tildado ? TextDecoration.lineThrough : null,
                  color: tildado ? colores.textoSecundario : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaDato(BuildContext context, String etiqueta, int centavos, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(etiqueta, style: TextStyle(color: color))),
          Text(formatearARS(centavos), style: TextStyle(color: color, fontWeight: Pesos.medium)),
        ],
      ),
    );
  }
}
