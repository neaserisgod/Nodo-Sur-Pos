// Panel de cobro — remake de disposición (2026-09-19, el dueño: "ahora
// remakea venta" → "Cambiar también la disposición"). Antes era una
// columna angosta (340px) apilando total/descuento/medios/cobrar en
// vertical, compartiendo ancho con el carrito; ahora es un panel FIJO al
// pie de la zona derecha, ancho completo — el carrito (`ColumnaCarrito`)
// pasó a ser `Expanded` con scroll propio arriba de este panel
// (`pantalla_venta.dart`).
//
// El total sigue siendo la pieza "hero" (rediseño de composición: ahora un
// bisel doble, marco de vidrio + núcleo con el degradé de
// `acentos.gradienteDinero`, ver `_TotalHero`) pero ahora ocupa el ancho
// completo del panel, con el control de descuento como un ícono chico
// adentro (mismo criterio que la tarjeta del total de la companion,
// `pantalla_carrito_venta.dart::_tarjetaCobrar`/`_botonDescuento`) en vez
// de un bloque propio siempre visible con el toggle $/% y el campo de
// texto ocupando toda una fila — se abre en un `Modal` (vidrio, mismo
// mecanismo que el resto de la app) solo cuando hace falta.
//
// Lo que NO se porta de la companion, a propósito (ver el plan del
// remake): los cuatro medios de pago siguen siendo CUATRO CONTROLES
// SIEMPRE VISIBLES con su propio atajo Alt+, no una tarjeta que al
// tocarla abre un menú para elegir el medio — CLAUDE.md documenta que
// El dueño revirtió ese patrón de un solo toque en el paso a la terminal
// Point (fase 12: "necesito cobro manual... no hay más modal para
// seleccionarlo"), así que no corresponde reintroducirlo acá.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/descuento.dart';
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/ticket.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/acentos.dart';
import '../tema/tokens.dart';
import 'acciones_venta.dart';
import 'columna_busqueda.dart' show TeclaAtajo;
import 'color_categoria.dart';
import 'tacto_venta.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/movimiento.dart';
import 'elegir_tarjeta.dart';
import '../../domain/cobro_posnet.dart' show canalCredito, canalDebito, esCanalTarjeta;

class PanelCobro extends StatelessWidget {
  const PanelCobro({super.key, required this.usuarioId, this.compacto = false});

  final int usuarioId;

  /// Poca altura de ventana: total más bajo y botones más chicos, para que todo entre sin scroll.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final colores = context.colores;
    final habilitado = c.carrito.isNotEmpty && c.medioElegido != null && !c.cobrando;
    final alturaMedio = compacto ? 56.0 : 72.0;
    final separacion = compacto ? 10.0 : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.avisoCobro != null) ...[
          Text(
            c.avisoCobro!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colores.error, fontWeight: Pesos.medium),
          ),
          const SizedBox(height: Espaciado.sm),
        ],
        _TotalHero(controlador: c, compacto: compacto),
        SizedBox(height: separacion),
        // Grilla 2×2 como el mock (`.medios`): cada medio con su ícono en un círculo, el nombre y el atajo debajo.
        Row(
          children: [
            Expanded(
              child: _BotonMedioMock(
                alto: alturaMedio,
                icono: IconosPlazoleta.paymentsOutlined,
                etiqueta: 'Efectivo',
                atajo: 'ALT+E',
                seleccionado: c.medioElegido == ComposicionPago.efectivo,
                colorSeleccionado: ColorMedioPago.efectivo(context),
                onPressed: () => _elegir(context, ComposicionPago.efectivo),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BotonMedioMock(
                alto: alturaMedio,
                icono: IconosPlazoleta.qrCode2Outlined,
                etiqueta: 'QR',
                atajo: 'ALT+Q',
                seleccionado: c.medioElegido == ComposicionPago.virtual && c.canalElegido == 'qr',
                colorSeleccionado: ColorMedioPago.qr(context),
                onPressed: () => _elegirCanal(context, 'qr'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BotonMedioMock(
                alto: alturaMedio,
                icono: IconosPlazoleta.creditCardOutlined,
                // Etapa C: "Tarjeta" pregunta Débito o Crédito (1 pago); elegido, dice cuál.
                etiqueta: switch (c.medioElegido == ComposicionPago.virtual ? c.canalElegido : null) {
                  canalDebito => 'Débito',
                  canalCredito => 'Crédito 1 pago',
                  _ => 'Tarjeta',
                },
                atajo: 'ALT+D',
                seleccionado: c.medioElegido == ComposicionPago.virtual && esCanalTarjeta(c.canalElegido),
                colorSeleccionado: ColorMedioPago.debito(context),
                onPressed: () => elegirTarjeta(context, c),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BotonMedioMock(
                alto: alturaMedio,
                icono: IconosPlazoleta.callSplitOutlined,
                etiqueta: 'Mixto',
                atajo: 'ALT+X',
                seleccionado: c.medioElegido == ComposicionPago.mixto,
                colorSeleccionado: ColorMedioPago.mixto(context),
                onPressed: () => abrirMixto(context, c),
              ),
            ),
          ],
        ),
        SizedBox(height: separacion),
        _BotonCobrar(habilitado: habilitado, alto: compacto ? 64 : 78, onTap: () => _cobrar(context)),
        // "Cobrar a mano (sin terminal)" (El dueño, 2026-09-08): solo con QR/Débito ya elegido, nunca con Efectivo puro. En el mock
        // ocupa siempre su lugar (44 px) para que el botón de cobrar no salte; con poca altura solo aparece cuando hace falta.
        if (c.canalElegido != null) ...[
          SizedBox(height: compacto ? 8 : 10),
          Tooltip(
            message: 'Cobrar a mano, sin pasar por la terminal — Alt+M',
            child: _BotonAMano(onTap: () => cobrarAMano(context, c)),
          ),
        ] else if (!compacto)
          const SizedBox(height: 54),
      ],
    );
  }

  void _elegir(BuildContext context, ComposicionPago medio) {
    final c = context.read<VentaControlador>();
    c.elegirMedio(medio);
    c.focoCampoPrincipal.requestFocus();
  }

  // QR y Débito eligen el canal nada más (El dueño, 2026-09-08: volvió a ser
  // de dos pasos) — mismo criterio que el atajo de teclado
  // (`pantalla_venta.dart`): "Cobrar" (o Alt+M para cobro manual) es quien
  // dispara algo de verdad.
  void _elegirCanal(BuildContext context, String canal) {
    final c = context.read<VentaControlador>();
    c.elegirCanalDirecto(canal);
    c.focoCampoPrincipal.requestFocus();
  }

  Future<void> _cobrar(BuildContext context) async {
    final c = context.read<VentaControlador>();
    if (c.medioElegido == ComposicionPago.mixto &&
        c.montoEfectivoMixtoCentavos == null) {
      await abrirMixto(context, c);
      if (!context.mounted) return;
      // `confirmarMixto` reclasifica el medio según cómo terminó pagando el
      // cliente (`domain/medio_pago.dart::clasificarComposicion`): si dio
      // puro efectivo o puro virtual, `medioElegido` ya NO es mixto acá,
      // aunque `montoEfectivoMixtoCentavos` siga en null (correcto, no hay
      // parte mixta que llevar). Bug real: chequear solo
      // `montoEfectivoMixtoCentavos == null` cortaba también ese caso y
      // cobraba nada, en vez de solo cuando el diálogo se cerró sin
      // confirmar (que es el único caso donde sigue en mixto sin monto).
      if (c.medioElegido == ComposicionPago.mixto &&
          c.montoEfectivoMixtoCentavos == null) {
        return;
      }
    }
    await cobrarOAbrirPosnet(context, c);
    c.focoCampoPrincipal.requestFocus();
  }
}

/// El total (`.tot` del mock): bloque de tinta de radio 44 con "Total a cobrar" y el botón de descuento arriba, el importe enorme y debajo
/// las cápsulas del desglose (descuento, recargo, redondeo, seña). El importe cuenta hasta su valor nuevo cuando cambia.
class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.controlador, required this.compacto});

  final VentaControlador controlador;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    final resultado = c.resultado;
    final totalAMostrar = resultado?.totalCentavos ?? c.subtotalCentavos;
    final acentos = context.acentosPlazoleta;
    final textoSobre = acentos.textoSobreColor;
    final chip = textoSobre.withValues(alpha: 0.1);
    final desglose = resultado == null
        ? const DesgloseTicket()
        : DesgloseTicket(
            recargoCigarrillosCentavos: resultado.recargoCigarrillosCentavos,
            descuentoCentavos: resultado.descuentoCentavos,
            redondeoCentavos: resultado.redondeoCentavos,
          );
    final cipas = <String>[
      if (desglose.descuentoCentavos > 0) 'Descuento −${formatearARS(desglose.descuentoCentavos)}',
      if (desglose.recargoCigarrillosCentavos > 0) 'Recargo cigarrillos +${formatearARS(desglose.recargoCigarrillosCentavos)}',
      if (desglose.redondeoCentavos > 0) 'Redondeo +${formatearARS(desglose.redondeoCentavos)}',
    ];
    final hayDescuento = desglose.descuentoCentavos > 0;

    return Container(
      padding: EdgeInsets.fromLTRB(30, compacto ? 14 : 20, 30, compacto ? 12 : 18),
      decoration: BoxDecoration(color: acentos.gradienteDinero.first, borderRadius: BorderRadius.circular(compacto ? 32 : 44)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total a cobrar',
                  style: TextStyle(fontSize: 16, fontWeight: Pesos.medium, color: textoSobre.withValues(alpha: 0.62)),
                ),
              ),
              _BotonDescuento(controlador: c, colorTexto: textoSobre, fondo: chip, cambiar: hayDescuento),
            ],
          ),
          // Late cuando cambia (2026-10-03) y cuenta hasta el valor nuevo: el número nuevo ya es el real desde el primer cuadro del latido.
          Pulso(
            valor: totalAMostrar,
            alineacion: Alignment.centerLeft,
            escala: 1.02,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: compacto ? 2 : 6),
                child: NumeroAnimado(
                  valor: totalAMostrar,
                  formato: formatearARS,
                  estilo: TextStyle(
                    fontSize: compacto ? 56 : 76,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    letterSpacing: compacto ? -3.4 : -4.5,
                    color: textoSobre,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Animaciones.corta,
            curve: Animaciones.curva,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: double.infinity,
              height: cipas.isEmpty && compacto ? 0 : null,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final t in cipas)
                    Entrada(
                      key: ValueKey('cipa-$t'),
                      desplazamiento: 4,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(999)),
                        child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: Pesos.medium, color: textoSobre).tabular),
                      ),
                    ),
                  // Entrega de un encargue con seña: lo que ya dejó el cliente y lo que falta (la seña ya está en la caja).
                  if (c.senaAplicadaCentavos > 0)
                    Container(
                      key: const Key('sena_cobro'),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        'Seña -${formatearARS(c.senaAplicadaCentavos)} · A cobrar ${formatearARS(c.aCobrarCentavos!)}',
                        style: TextStyle(fontSize: 13.5, fontWeight: Pesos.medium, color: textoSobre).tabular,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (cipas.isEmpty && c.senaAplicadaCentavos == 0 && !compacto) const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/// "% Descuento" dentro del total (`.dbtn`): cápsula translúcida; con un descuento aplicado dice "Cambiar descuento".
class _BotonDescuento extends StatelessWidget {
  const _BotonDescuento({required this.controlador, required this.colorTexto, required this.fondo, required this.cambiar});

  final VentaControlador controlador;
  final Color colorTexto;
  final Color fondo;
  final bool cambiar;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Descuento',
      child: SuperficieTactil(
        etiqueta: 'Descuento',
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        onTap: () => mostrarModal<void>(context, builder: (_) => _ModalDescuento(controlador: controlador)),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconoPlz(IconosPlazoleta.sellOutlined, size: 15, color: colorTexto),
              const SizedBox(width: 7),
              Text(cambiar ? 'Cambiar descuento' : 'Descuento', style: TextStyle(fontSize: 14, fontWeight: Pesos.medium, color: colorTexto)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un medio de pago como el mock (`.medio`): tarjeta blanca de radio 30 con el ícono en un círculo gris, el nombre y el atajo; elegido,
/// se llena con el color de su medio (verde, azul, gris, ámbar) y el círculo pasa a blanco translúcido. Late una vez al elegirse.
class _BotonMedioMock extends StatefulWidget {
  const _BotonMedioMock({
    required this.alto,
    required this.icono,
    required this.etiqueta,
    required this.atajo,
    required this.seleccionado,
    required this.colorSeleccionado,
    required this.onPressed,
  });

  final double alto;
  final IconData icono;
  final String etiqueta;
  final String atajo;
  final bool seleccionado;
  final Color colorSeleccionado;
  final VoidCallback onPressed;

  @override
  State<_BotonMedioMock> createState() => _BotonMedioMockState();
}

class _BotonMedioMockState extends State<_BotonMedioMock> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final sel = widget.seleccionado;
    final colorContenido = sel ? context.acentosPlazoleta.textoSobreColor : colores.textoPrimario;
    final caja = (widget.alto * 0.64).clamp(34.0, 46.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Pulso(
        valor: sel,
        escala: 1.045,
        child: AnimatedSlide(
          duration: Animaciones.corta,
          curve: Animaciones.curva,
          offset: _encima && !sel ? const Offset(0, -0.03) : Offset.zero,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: sel ? widget.colorSeleccionado : colores.fondo),
            duration: Animaciones.media,
            curve: Animaciones.curva,
            builder: (context, fondo, _) => SizedBox(
              height: widget.alto,
              child: SuperficieTactil(
                etiqueta: '${widget.etiqueta} (${widget.atajo.replaceFirst('ALT+', 'Alt+')})',
                color: fondo ?? colores.fondo,
                borderRadius: BorderRadius.circular(30),
                onTap: widget.onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: caja,
                        height: caja,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? Colors.white.withValues(alpha: 0.22) : colores.fondoBloque,
                        ),
                        child: IconoPlz(widget.icono, size: 22, color: colorContenido),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.etiqueta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 20, fontWeight: Pesos.medium, letterSpacing: -0.4, color: colorContenido, height: 1.15),
                            ),
                            Text(
                              widget.atajo,
                              style: TextStyle(fontSize: 12, fontWeight: Pesos.medium, letterSpacing: 0.6, color: colorContenido.withValues(alpha: 0.55)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Cobrar · Enter →" (`.cobrar` del mock): píldora azul de 78 px con una flecha en un círculo; apagada, a 38 % de opacidad.
class _BotonCobrar extends StatefulWidget {
  const _BotonCobrar({required this.habilitado, required this.alto, required this.onTap});

  final bool habilitado;
  final double alto;
  final VoidCallback onTap;

  @override
  State<_BotonCobrar> createState() => _BotonCobrarState();
}

class _BotonCobrarState extends State<_BotonCobrar> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.habilitado;
    final circulo = widget.alto * 0.69;
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: AnimatedSlide(
        duration: Animaciones.corta,
        curve: Animaciones.curva,
        offset: _encima && habilitado ? const Offset(0, -0.03) : Offset.zero,
        child: AnimatedOpacity(
          duration: Animaciones.corta,
          opacity: habilitado ? 1 : 0.38,
          child: AnimatedContainer(
            duration: Animaciones.corta,
            decoration: BoxDecoration(
              color: _encima && habilitado ? azulMarcaOscuro : azulMarca,
              borderRadius: BorderRadius.circular(999),
              boxShadow: _encima && habilitado ? [BoxShadow(color: azulMarca.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 18))] : null,
            ),
            child: SuperficieTactil(
              etiqueta: 'Cobrar',
              borderRadius: BorderRadius.circular(999),
              onTap: habilitado ? widget.onTap : null,
              child: SizedBox(
                height: widget.alto,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(widget.alto * 0.49, 0, widget.alto * 0.18, 0),
                  child: Row(
                    children: [
                      const Text('Cobrar', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(width: 12),
                      TeclaAtajo(texto: 'Enter', color: Colors.white, tamano: 13),
                      const Spacer(),
                      Container(
                        width: circulo,
                        height: circulo,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
                        child: IconoPlz(IconosPlazoleta.arrowForwardRounded, size: 26, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Cobrar a mano, sin terminal · Alt+M" (`.btn.out.wide`): botón de contorno a todo el ancho, debajo de "Cobrar".
class _BotonAMano extends StatelessWidget {
  const _BotonAMano({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colores.textoPrimario.withValues(alpha: 0.12), width: 1.5),
      ),
      child: SuperficieTactil(
        etiqueta: 'Cobrar a mano',
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cobrar a mano, sin terminal', style: TextStyle(fontSize: 15, fontWeight: Pesos.medium, color: colores.textoPrimario)),
              const SizedBox(width: 10),
              TeclaAtajo(texto: 'Alt+M', color: colores.textoPrimario),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalDescuento extends StatelessWidget {
  const _ModalDescuento({required this.controlador});

  final VentaControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    return Modal(
      titulo: 'Descuento',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _BotonMedio(
                  etiqueta: r'$',
                  seleccionado: c.tipoDescuento == TipoDescuento.monto,
                  onPressed: () => c.elegirTipoDescuento(TipoDescuento.monto),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: _BotonMedio(
                  etiqueta: '%',
                  seleccionado: c.tipoDescuento == TipoDescuento.porcentaje,
                  onPressed: () => c.elegirTipoDescuento(TipoDescuento.porcentaje),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          TextField(
            key: const Key('campo_descuento'),
            controller: c.campoDescuentoCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: c.tipoDescuento == TipoDescuento.monto ? 'Monto del descuento' : 'Porcentaje de descuento',
            ),
          ),
        ],
      ),
      // `BotonPrimario`, no `FilledButton` crudo (bug real, encontrado
      // corriendo los tests): `FilledButtonThemeData.minimumSize` es
      // `Size.fromHeight(...)` (ancho infinito, pensado para un botón que
      // ocupa todo el ancho de su contenedor, ej. `EstadoError`) — un
      // `FilledButton` suelto en el `Row` de `Modal.botones` (sin
      // `Expanded`/ancho fijo alrededor) hereda ese ancho infinito y
      // `BoxConstraints forces an infinite width` revienta el layout.
      // `BotonPrimario` ya trae su propio `SizedBox` de ancho acotado — es
      // el botón que usa el resto de los modales de la app.
      botones: [
        BotonPrimario(
          texto: 'Listo',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Botón de dos estados del modal de descuento ("$" / "%"): neutro, o de acento cuando está elegido.
class _BotonMedio extends StatelessWidget {
  const _BotonMedio({required this.etiqueta, required this.seleccionado, required this.onPressed});

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return SizedBox(
      height: TactoVenta.alturaControl,
      child: SuperficieTactil(
        color: seleccionado ? colores.acento : colores.fondoBloque,
        borderRadius: BorderRadius.circular(TactoVenta.radio),
        onTap: onPressed,
        child: Center(
          child: Text(
            etiqueta,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(color: seleccionado ? colores.acentoTexto : colores.textoPrimario),
          ),
        ),
      ),
    );
  }
}
