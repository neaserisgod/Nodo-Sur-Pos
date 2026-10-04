// Inicio, tal cual el mock (docs/03 B1): estado de conexión y campana arriba,
// "Hola, X", el botón azul de venta, el carrusel "Tu día" de tres tarjetas, tres
// atajos y el buscador de funciones. Las cifras salen de la base real.

import 'package:flutter/material.dart';

import '../app_ns.dart';
import '../kit/kit_ns.dart';
import '../pantalla_consultar_precio.dart';
import '../pantalla_movimiento_caja.dart';
import 'pantalla_buscador_ns.dart';
import 'pantalla_notificaciones_ns.dart';

class PantallaInicioNs extends StatelessWidget {
  const PantallaInicioNs({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    return PantallaEntradaNs(
      child: RefreshIndicator(
        onRefresh: app.sincronizar,
        color: ns.ink,
        backgroundColor: ns.paper,
        child: ListenableBuilder(
          listenable: Listenable.merge([app.pendientes, app.datosDia]),
          builder: (context, _) {
            final pend = app.pendientes.value;
            final dia = app.datosDia.value;
            final enCarrito = app.carrito.length;
            final etiquetaVenta = !app.cajaAbierta
                ? 'Abrir la caja y vender'
                : enCarrito > 0
                ? 'Seguir con la venta ($enCarrito)'
                : 'Nueva venta';
            return ListView(
              padding: const EdgeInsets.only(top: 24, bottom: BarraInferiorNs.espacioReservado),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _FilaSuperior(app: app, pendientes: pend.cantidad),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: margenNs),
                  child: Text('Hola, ${app.nombreUsuario ?? ''}', style: tituloNs(44, altura: 1.02, color: ns.ink)),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: margenNs),
                  child: _BotonNuevaVenta(texto: etiquetaVenta, onTap: () => app.irAPestania(PestaniaNs.vender)),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(margenNs, 6, margenNs, 0),
                  child: SeccionNs('Tu día', derecha: Text('Deslizá para ver más →', style: estiloNs(13, color: ns.mute))),
                ),
                const SizedBox(height: 14),
                _Carrusel(app: app, dia: dia, pend: pend),
                const Padding(padding: EdgeInsets.fromLTRB(margenNs, 22, margenNs, 14), child: _EncabezadoRapido()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: margenNs),
                  child: _Atajos(app: app),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: margenNs),
                  child: PresionNs(
                    onTap: () => app.irA((_) => const PantallaBuscadorNs(origen: PestaniaNs.inicio)),
                    etiqueta: '¿No encontrás algo? Buscá una función',
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        children: [
                          IconoNsWidget(IconoNs.lupa, tamanio: 20, color: ns.mute),
                          const SizedBox(width: 12),
                          Expanded(child: Text('¿No encontrás algo? Buscá una función', style: estiloNs(16, peso: FontWeight.w500, color: ns.mute))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EncabezadoRapido extends StatelessWidget {
  const _EncabezadoRapido();
  @override
  Widget build(BuildContext context) => const SeccionNs('Para hacer rápido');
}

class _FilaSuperior extends StatelessWidget {
  const _FilaSuperior({required this.app, required this.pendientes});
  final ControladorAppNs app;
  final int pendientes;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final sin = app.sinConexion;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: margenNs),
      child: Row(
        children: [
          // Solo informativo: el estado lo decide la conexión real con la PC.
          Semantics(
            label: sin ? 'Sin conexión con la PC' : 'Conectado a la PC',
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: sin ? ns.wbg : ns.gbg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: IconoNsWidget(sin ? IconoNs.sinWifi : IconoNs.computadora, tamanio: 22, color: sin ? ns.w : ns.g),
            ),
          ),
          const Spacer(),
          BotonCircularNs(
            icono: IconoNs.campana,
            tamanio: 48,
            etiqueta: pendientes == 0 ? 'Notificaciones' : '$pendientes notificaciones',
            globo: pendientes,
            onTap: () => app.irA((_) => const PantallaNotificacionesNs()),
          ),
        ],
      ),
    );
  }
}

class _BotonNuevaVenta extends StatelessWidget {
  const _BotonNuevaVenta({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PresionNs(
      onTap: onTap,
      etiqueta: texto,
      child: Container(
        height: 68,
        padding: const EdgeInsets.fromLTRB(28, 0, 12, 0),
        decoration: BoxDecoration(color: TokensNs.marca, borderRadius: BorderRadius.circular(999)),
        child: Row(
          children: [
            Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(19, peso: FontWeight.w600, track: -0.02, color: TokensNs.blanco))),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Color(0x2EFFFFFF), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const IconoNsWidget(IconoNs.chevron, tamanio: 22, color: TokensNs.blanco, grosor: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Carrusel extends StatelessWidget {
  const _Carrusel({required this.app, required this.dia, required this.pend});
  final ControladorAppNs app;
  final DatosDiaNs dia;
  final PendientesNs pend;

  @override
  Widget build(BuildContext context) {
    // Tarjetas de 300 px con 12 de separación, que se frenan al comienzo de
    // cada una (`scroll-snap-type: x mandatory`) y dejan ver la siguiente.
    final cartas = <Widget>[
      _TarjetaHoy(dia: dia),
      _TarjetaCajon(app: app),
      _TarjetaSeparar(app: app, pend: pend),
    ];
    return SizedBox(
      height: 232,
      child: LayoutBuilder(
        builder: (context, c) {
          final ancho = c.maxWidth - 2 * margenNs;
          return Padding(
            padding: const EdgeInsets.only(left: margenNs),
            child: PageView.builder(
              padEnds: false,
              clipBehavior: Clip.none,
              controller: PageController(viewportFraction: 312 / ancho),
              itemCount: cartas.length,
              itemBuilder: (_, i) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: 300, child: EntradaNs(retraso: Duration(milliseconds: 90 * i), child: cartas[i])),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaHoy extends StatelessWidget {
  const _TarjetaHoy({required this.dia});
  final DatosDiaNs dia;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final total = dia.efectivoCentavos + dia.mpCentavos;
    final pEf = total == 0 ? 0 : (dia.efectivoCentavos * 100 / total).round();
    final pMp = total == 0 ? 0 : 100 - pEf;
    return Container(
      constraints: const BoxConstraints(minHeight: 232),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(34)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Hoy vendiste', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plataNs(dia.vendidoCentavos), style: tituloNs(46, color: ns.ink)),
              const SizedBox(height: 2),
              Text('Ganancia ${plataNs(dia.gananciaCentavos)}', style: estiloNs(15, peso: FontWeight.w600, color: ns.g, tabular: true)),
            ],
          ),
          Column(
            children: [
              Semantics(
                label: 'Efectivo $pEf por ciento, Mercado Pago $pMp por ciento',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 12,
                    color: ns.s2,
                    child: Row(
                      children: [
                        if (pEf > 0) Expanded(flex: pEf, child: Container(color: TokensNs.medioEfectivo)),
                        if (pEf > 0 && pMp > 0) const SizedBox(width: 2),
                        if (pMp > 0) Expanded(flex: pMp, child: Container(color: TokensNs.medioMercadoPago)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Leyenda(color: TokensNs.medioEfectivo, nombre: 'Efectivo', monto: plataNs(dia.efectivoCentavos), alDerecha: false),
                  _Leyenda(color: TokensNs.medioMercadoPago, nombre: 'Mercado Pago', monto: plataNs(dia.mpCentavos), alDerecha: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.nombre, required this.monto, required this.alDerecha});
  final Color color;
  final String nombre;
  final String monto;
  final bool alDerecha;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Column(
      crossAxisAlignment: alDerecha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(nombre, style: estiloNs(13, color: ns.mute)),
          ],
        ),
        const SizedBox(height: 1),
        Text(monto, style: estiloNs(16, peso: FontWeight.w600, color: ns.ink, tabular: true)),
      ],
    );
  }
}

class _TarjetaCajon extends StatelessWidget {
  const _TarjetaCajon({required this.app});
  final ControladorAppNs app;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final abierta = app.cajaAbierta;
    return HeroNs(
      radio: 34,
      padding: const EdgeInsets.all(22),
      alto: 232,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Efectivo en el cajón', style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: Text(abierta ? 'Caja abierta' : 'Caja cerrada', style: estiloNs(12, peso: FontWeight.w700, color: TokensNs.blanco)),
              ),
            ],
          ),
          Text(plataNs(app.estadoCaja?.efectivoEsperadoCentavos ?? 0), style: tituloNs(46, color: TokensNs.blanco)),
          BotonNs(
            texto: 'Ir a Caja',
            onTap: () {
              app.segmentoCaja.value = 0;
              app.irAPestania(PestaniaNs.caja);
            },
            alto: 48,
            tamanio: 15,
            fondo: ns.paper,
            color: ns.ink,
          ),
        ],
      ),
    );
  }
}

class _TarjetaSeparar extends StatelessWidget {
  const _TarjetaSeparar({required this.app, required this.pend});
  final ControladorAppNs app;
  final PendientesNs pend;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final total = pend.proveedoresTotal;
    final fraccion = total == 0 ? 0.0 : pend.proveedoresSeparados / total;
    return PresionNs(
      etiqueta: 'Separar para proveedores',
      onTap: () {
        app.segmentoCaja.value = 1;
        app.irAPestania(PestaniaNs.caja);
      },
      child: Container(
        height: 232,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: ns.wbg, borderRadius: BorderRadius.circular(34)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Separar para proveedores', style: estiloNs(14, peso: FontWeight.w600, color: ns.w)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plataNs(pend.faltaSepararCentavos), style: tituloNs(46, color: ns.w)),
                const SizedBox(height: 2),
                Text('${pend.proveedoresSeparados} de $total proveedores separados', style: estiloNs(15, peso: FontWeight.w600, color: ns.w)),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 12,
                color: ns.w.withValues(alpha: 0.18),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: fraccion.clamp(0.0, 1.0), child: Container(color: ns.w)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Atajos extends StatelessWidget {
  const _Atajos({required this.app});
  final ControladorAppNs app;

  @override
  Widget build(BuildContext context) {
    final atajos = <(String, IconoNs, VoidCallback)>[
      ('Consultar precio', IconoNs.escanear, () => app.irA((_) => const PantallaConsultarPrecio())),
      ('Gasto o ingreso', IconoNs.intercambio, () => app.irA((_) => const PantallaMovimientoCaja(tipoInicial: TipoMovimientoCaja.gasto))),
      (
        'Controlar stock',
        IconoNs.portapapeles,
        () {
          app.productosEnConteo.value = true;
          app.irAPestania(PestaniaNs.productos);
        },
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < atajos.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _Atajo(texto: atajos[i].$1, icono: atajos[i].$2, onTap: atajos[i].$3)),
        ],
      ],
    );
  }
}

class _Atajo extends StatelessWidget {
  const _Atajo({required this.texto, required this.icono, required this.onTap});
  final String texto;
  final IconoNs icono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: texto,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: IconoNsWidget(icono, tamanio: 22, color: ns.ink),
            ),
            const SizedBox(height: 18),
            Text(texto, style: estiloNs(15, peso: FontWeight.w600, track: -0.015, altura: 1.15, color: ns.ink)),
          ],
        ),
      ),
    );
  }
}
