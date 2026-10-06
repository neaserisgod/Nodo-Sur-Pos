// Cierres de caja — pestaña de Historial ("Lenguaje de diseño", el dueño
// 2026-09-26, mock `HistorialCierres.dc.html`): la lista de cierres a la
// izquierda (día, lo vendido, a qué hora cerró y si cuadró) y el cierre
// elegido a la derecha, con la cuenta del efectivo a la vista (fondo +
// ventas en efectivo − lo que se fue a la lata − gastos/pagos/retiros =
// lo que debería haber, contra lo contado) y Mercado Pago y la lata al
// costado. Las ventas del día, su edición y el PDF siguen en
// `PantallaDetalleDia` ("Ver las ventas de ese día").
//
// Rediseño v4 (2026-10-06): las filas son las del mock (día, cómo cuadró, lo vendido). El mock no tiene el detalle a la
// derecha (iba directo a las ventas del día), pero la cuenta del efectivo es lo que se mira para saber por qué no
// cuadró: queda en el espacio libre de la derecha, con el mismo lenguaje.

import 'package:flutter/material.dart';

import '../../data/repositorio_historial.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;

class VistaCierres extends StatefulWidget {
  const VistaCierres({super.key, required List<ResumenDia> dias, required this.alAbrirDia, this.busqueda = ''})
      : _todos = dias;

  final List<ResumenDia> _todos;

  /// Buscador de la fila de filtros: día ("sábado", "26", "septiembre") o empleado.
  final String busqueda;

  List<ResumenDia> get dias => [
    for (final d in _todos)
      if (coincideBusqueda('${fechaLarga(d.sesion.fechaApertura)} ${d.sesion.fechaApertura.day}/${d.sesion.fechaApertura.month} ${d.nombreEmpleado}', busqueda)) d,
  ];

  /// Abre `PantallaDetalleDia` (ventas del día, editar, PDF).
  final void Function(int sesionId) alAbrirDia;

  @override
  State<VistaCierres> createState() => _VistaCierresState();
}

class _VistaCierresState extends State<VistaCierres> {
  int _elegido = 0;

  @override
  Widget build(BuildContext context) {
    final dias = widget.dias;
    if (dias.isEmpty) {
      return Vacio(
        texto: widget.busqueda.isEmpty ? 'Todavía no hay ningún día cerrado.' : 'Ningún cierre coincide con "${widget.busqueda}"',
        icono: null,
      );
    }
    final elegido = _elegido.clamp(0, dias.length - 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 11,
          child: ListView.separated(
            padding: const EdgeInsets.only(right: 4),
            itemCount: dias.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => Aparecer.revelar(
              orden: i,
              child: _FilaCierre(dia: dias[i], elegida: i == elegido, onTap: () => setState(() => _elegido = i)),
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 8, child: SingleChildScrollView(child: _DetalleCierre(dia: dias[elegido], alAbrirDia: widget.alAbrirDia))),
      ],
    );
  }
}

/// Cualquier diferencia distinta de cero es un descuadre, sobre o falte
/// (Regla 10): faltante en rojo, sobrante en el tono de aviso, cero en verde.
TonoMock _tono(int diferencia) => diferencia == 0 ? TonoMock.g : (diferencia < 0 ? TonoMock.b : TonoMock.w);

String _estado(int diferencia) =>
    diferencia == 0 ? 'Cuadró' : '${diferencia > 0 ? 'Sobraron' : 'Faltaron'} ${pesos(diferencia.abs())}';

String _mayuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _FilaCierre extends StatelessWidget {
  const _FilaCierre({required this.dia, required this.elegida, required this.onTap});

  final ResumenDia dia;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final apertura = dia.sesion.fechaApertura;
    final cierre = dia.sesion.fechaCierre;
    return Rowb(
      titulo: _mayuscula(fechaLarga(apertura)),
      // Hora y empleado, no solo la fecha (El dueño, 31/08/2026): un turno es una sesión completa, puede haber más de
      // una el mismo día.
      detalle: '${horaCorta(apertura)}${cierre == null ? '' : ' a ${horaCorta(cierre)}'} · ${dia.nombreEmpleado}',
      izquierda: const Ibox(Ic.cal),
      elegida: elegida,
      onTap: onTap,
      derecha: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Etiqueta(_estado(dia.diferenciaCentavos), key: const Key('estado_cierre'), tono: _tono(dia.diferenciaCentavos)),
          const SizedBox(width: 16),
          Text(pesos(dia.totalVendidoCentavos), style: estilo(17, 600, color: p.tinta, num: true)),
        ],
      ),
    );
  }
}

class _DetalleCierre extends StatelessWidget {
  const _DetalleCierre({required this.dia, required this.alAbrirDia});

  final ResumenDia dia;
  final void Function(int sesionId) alAbrirDia;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = dia.sesion;
    final esperado = s.efectivoEsperadoCentavos ?? 0;
    final lata = s.lataSeparadoCentavos ?? 0;
    // Lo que no es fondo, ventas en efectivo ni lata: gastos, pagos a
    // proveedores, retiros e ingresos del turno — la diferencia que
    // completa la cuenta hasta lo esperado que calculó el cierre.
    final otros = esperado - (s.fondoInicialCentavos + dia.efectivoCentavos - lata);
    final colorDif = switch (_tono(dia.diferenciaCentavos)) {
      TonoMock.g => p.g,
      TonoMock.b => p.b,
      _ => p.w,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(36)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cierre del ${fechaLarga(s.fechaApertura)}', style: estilo(26, 550, color: p.tinta, em: -.03)),
                    const SizedBox(height: 6),
                    Text(
                      'Abrió ${horaCorta(s.fechaApertura)}${s.fechaCierre == null ? '' : ' · cerró ${horaCorta(s.fechaCierre!)}'} · ${dia.nombreEmpleado}',
                      style: estilo(15.5, 400, color: p.mute),
                    ),
                  ],
                ),
              ),
              Etiqueta(_estado(dia.diferenciaCentavos), tono: _tono(dia.diferenciaCentavos)),
            ],
          ),
          const SizedBox(height: 18),
          BloqueHero(
            radio: 28,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              children: [
                Expanded(child: Text('Vendido en el turno', style: estilo(15, 600, color: p.heroSub))),
                Text(pesos(dia.totalVendidoCentavos), style: estilo(30, 550, color: p.sobreHero, em: -.04, num: true)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Sec('Efectivo en el cajón'),
          const SizedBox(height: 10),
          Lista(
            color: p.papel,
            filas: [
              Kv('Fondo para el vuelto', pesos(s.fondoInicialCentavos)),
              Kv('+ Ventas en efectivo', pesos(dia.efectivoCentavos)),
              if (lata != 0) Kv('− A la lata (cigarrillos)', pesosConSigno(-lata)),
              if (otros != 0) Kv('± Gastos, pagos y retiros', pesosConSigno(otros)),
              Kv('= Debería haber', pesos(esperado), colorValor: p.tinta),
              Kv('Contado al cerrar', pesos(s.efectivoContadoCentavos ?? 0)),
              Kv('Diferencia', pesosConSigno(dia.diferenciaCentavos), colorValor: colorDif, tamanioValor: 20),
            ],
          ),
          if ((s.nota ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Nota(texto: 'Nota del cierre: “${s.nota!.trim()}”'),
          ],
          const SizedBox(height: 14),
          const Sec('Otros medios'),
          const SizedBox(height: 10),
          Lista(
            color: p.papel,
            filas: [
              Kv('Efectivo', pesos(dia.efectivoCentavos)),
              Kv('Mercado Pago', pesos(dia.mpCentavos)),
              if (dia.cigarrillosCentavos > 0) Kv('Cigarrillos (a la lata)', pesos(dia.cigarrillosCentavos)),
            ],
          ),
          if ((s.mpContadoCentavos ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Text(
              'MP contado ${pesos(s.mpContadoCentavos!)} · diferencia ${pesosConSigno(s.mpDiferenciaCentavos ?? 0)}',
              style: estilo(14, 400, color: p.mute),
            ),
          ] else if ((s.mpEsperadoCentavos ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Text('El saldo de Mercado Pago no se contó en este cierre', style: estilo(14, 500, color: p.w)),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Btn('Ver las ventas de ese día', variante: VarBtn.dark, flecha: true, onTap: () => alAbrirDia(s.id)),
          ),
        ],
      ),
    );
  }
}
