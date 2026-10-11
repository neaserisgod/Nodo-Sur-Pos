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
//
// Con el mock del celular (lote 2) se dibuja con el kit: filas de dato con línea fina, filas de producto de 64 y
// el tilde por proveedor como un "✓" delante del nombre y la fila a media luz.

import 'package:flutter/material.dart';

import '../servicios/modulos_activos.dart' show esNegocioDeServicios;
import 'cliente_companion.dart' show ResumenCierreCompanion, ResumenProveedorDiaCompanion;
import 'kit/kit_ns.dart';
import 'pantalla_carga_historica.dart' show SeccionProductosSinDatos;

class SeccionExtraCierreCompanion extends StatefulWidget {
  const SeccionExtraCierreCompanion({super.key, required this.resumen, this.nota});

  final ResumenCierreCompanion resumen;

  /// La nota escrita al cerrar (el resumen en vivo todavía no la trae).
  final String? nota;

  @override
  State<SeccionExtraCierreCompanion> createState() => _SeccionExtraCierreCompanionState();
}

class _SeccionExtraCierreCompanionState extends State<SeccionExtraCierreCompanion> {
  final Set<int> _tildados = {};

  @override
  Widget build(BuildContext context) {
    final r = widget.resumen;
    final nota = widget.nota;
    final ns = context.ns;
    // Un negocio de servicios no tiene cigarrillos, ni productos sin costo, ni separa por proveedor (El dueño, 2026-10-11:
    // "lata de cigarrillos… que parezca que está hecho para turnos").
    final servicios = esNegocioDeServicios();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cuánta plata mover a la lata AHORA, en este cierre (sin esta línea había que calcularlo de memoria).
        if (!servicios) FilaClaveValorNs(clave: 'A separar a la lata', valor: plataNs(r.separadoCentavos)),
        if (!servicios && r.esSeparacionParcial)
          FilaClaveValorNs(clave: 'De eso, no alcanza el efectivo — queda pendiente para el próximo cierre', valor: plataNs(r.pendienteCentavos), colorValor: ns.b),
        FilaClaveValorNs(clave: 'Redondeo acumulado', valor: plataNs(r.redondeoAcumuladoCentavos)),
        if (!servicios) ...[
          FilaClaveValorNs(clave: 'Vendido sin costo cargado', valor: plataNs(r.vendidoSinCostoCentavos)),
          // Qué productos componen el "vendido sin costo" (viaja completo en el mismo resumen).
          SeccionProductosSinDatos(productos: r.productosSinDatos),
        ],
        const SizedBox(height: 14),
        if (r.reservaDiariaFijosCentavos == null)
          const InfoNs('Reserva diaria de fijos: sin cargar los fijos de este mes')
        else
          FilaClaveValorNs(clave: 'Reserva diaria de fijos (informativo)', valor: plataNs(r.reservaDiariaFijosCentavos!)),
        if ((nota ?? r.nota) != null && (nota ?? r.nota)!.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          const SeccionNs('Nota'),
          const SizedBox(height: 10),
          InfoNs((nota ?? r.nota)!.trim()),
        ],
        if (!servicios && r.porProveedor.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SeccionNs('A separar por proveedor'),
          const SizedBox(height: 10),
          for (final p in r.porProveedor) ...[_filaProveedor(context, p), const SizedBox(height: 10)],
        ],
      ],
    );
  }

  Widget _filaProveedor(BuildContext context, ResumenProveedorDiaCompanion p) {
    final tildado = _tildados.contains(p.proveedorId);
    return FilaProductoNs(
      nombre: '${tildado ? '✓ ' : ''}${p.nombreProveedor}',
      detalle: 'Ganancia sin revisar: ${plataNs(p.gananciaCentavos)}',
      valor: plataNs(p.costoRealCentavos),
      apagada: tildado,
      tildable: true,
      onTap: () => setState(() {
        if (tildado) {
          _tildados.remove(p.proveedorId);
        } else {
          _tildados.add(p.proveedorId);
        }
      }),
    );
  }
}
