// Piezas base del mock (docs/01 §6): botones, chips, segmentos, campos,
// interruptores, steppers, avisos, listas agrupadas y tarjetas. Las medidas
// (alturas 44/48/52/56/60/64/68, radios 999/34/28/26/24/22) son las del doc;
// los colores salen de `TokensNs`, nunca de un hex suelto.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/dinero.dart' show formatearARS;

import 'iconos_ns.dart';
import 'movimiento_ns.dart';
import 'texto_ns.dart';
import 'tokens_ns.dart';

const double margenNs = 20;

// ───────────────────────── Botones ─────────────────────────

/// Botón píldora del mock. Las variantes fijan alto, tamaño y colores.
class BotonNs extends StatelessWidget {
  const BotonNs({
    super.key,
    required this.texto,
    required this.onTap,
    required this.alto,
    required this.tamanio,
    required this.fondo,
    required this.color,
    this.peso = FontWeight.w600,
    this.icono,
    this.rellenar = true,
    this.paddingH = 0,
    this.habilitado = true,
    this.alineacion = Alignment.center,
    this.contorno = false,
    this.tracking = 0,
  });

  /// Primario de página u hoja: 60, `prim`, 17/600.
  factory BotonNs.primario(BuildContext context, String texto, VoidCallback? onTap, {bool habilitado = true, double alto = 60, double tamanio = 17, IconoNs? icono}) {
    final ns = context.ns;
    return BotonNs(
      texto: texto,
      onTap: onTap,
      alto: alto,
      tamanio: tamanio,
      fondo: habilitado ? ns.prim : ns.s,
      color: habilitado ? TokensNs.blanco : ns.mute,
      habilitado: habilitado,
      icono: icono,
    );
  }

  /// Secundario de hoja: 54, `s`, 16/600.
  factory BotonNs.secundario(BuildContext context, String texto, VoidCallback? onTap, {double alto = 54, double tamanio = 16, IconoNs? icono}) {
    final ns = context.ns;
    return BotonNs(texto: texto, onTap: onTap, alto: alto, tamanio: tamanio, fondo: ns.s, color: ns.ink, icono: icono);
  }

  /// Peligro suave: 54, `bbg`/`b`.
  factory BotonNs.peligroSuave(BuildContext context, String texto, VoidCallback? onTap) {
    final ns = context.ns;
    return BotonNs(texto: texto, onTap: onTap, alto: 54, tamanio: 16, fondo: ns.bbg, color: ns.b);
  }

  /// Peligro sólido: 60, `b`/blanco.
  factory BotonNs.peligroSolido(BuildContext context, String texto, VoidCallback? onTap) {
    final ns = context.ns;
    return BotonNs(texto: texto, onTap: onTap, alto: 60, tamanio: 17, fondo: ns.b, color: ns.oscuro ? ns.bbg : TokensNs.blanco);
  }

  /// Texto sin fondo (p. ej. "Volver al inicio", 44, 15/600, `mute`).
  factory BotonNs.texto(BuildContext context, String texto, VoidCallback? onTap, {Color? color}) {
    final ns = context.ns;
    return BotonNs(texto: texto, onTap: onTap, alto: 44, tamanio: 15, fondo: Colors.transparent, color: color ?? ns.mute);
  }

  final String texto;
  final VoidCallback? onTap;
  final double alto;
  final double tamanio;
  final Color fondo;
  final Color color;
  final FontWeight peso;
  final IconoNs? icono;
  final bool rellenar;
  final double paddingH;
  final bool habilitado;
  final Alignment alineacion;
  final bool contorno;
  final double tracking;

  @override
  Widget build(BuildContext context) {
    final contenido = Row(
      mainAxisSize: rellenar ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: alineacion == Alignment.centerLeft ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        if (icono != null) ...[IconoNsWidget(icono!, tamanio: tamanio + 3, color: color), const SizedBox(width: 10)],
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estiloNs(tamanio, peso: peso, color: color, track: tracking),
          ),
        ),
      ],
    );
    return PresionNs(
      onTap: onTap,
      habilitado: habilitado && onTap != null,
      etiqueta: texto,
      child: Container(
        height: alto,
        padding: EdgeInsets.symmetric(horizontal: paddingH),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(999),
          border: contorno ? Border.all(color: TokensNs.contorno, width: 1.5) : null,
        ),
        alignment: rellenar ? alineacion : null,
        child: rellenar ? contenido : Center(widthFactor: 1, child: contenido),
      ),
    );
  }
}

/// Botón circular de cabecera (volver, campana, lupa): 44 o 48, fondo `s`.
class BotonCircularNs extends StatelessWidget {
  const BotonCircularNs({
    super.key,
    required this.icono,
    required this.onTap,
    required this.etiqueta,
    this.tamanio = 44,
    this.fondo,
    this.colorIcono,
    this.tamanioIcono = 22,
    this.grosor = 2,
    this.globo,
  });

  final IconoNs icono;
  final VoidCallback? onTap;
  final String etiqueta;
  final double tamanio;
  final Color? fondo;
  final Color? colorIcono;
  final double tamanioIcono;
  final double grosor;

  /// Número del globo rojo (campana). `null` o 0 = sin globo.
  final int? globo;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: etiqueta,
      child: SizedBox(
        width: tamanio,
        height: tamanio,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: tamanio,
              height: tamanio,
              decoration: BoxDecoration(color: fondo ?? ns.s, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: IconoNsWidget(icono, tamanio: tamanioIcono, color: colorIcono ?? ns.ink, grosor: grosor),
            ),
            if (globo != null && globo! > 0) Positioned(top: 2, right: 0, child: GloboNs(globo!)),
          ],
        ),
      ),
    );
  }
}

/// Globo rojo de la campana: mínimo 20×20, 12/700 blanco, aro de 2 px `paper`.
class GloboNs extends StatelessWidget {
  const GloboNs(this.cantidad, {super.key});
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: TokensNs.globo,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: ns.paper, spreadRadius: 2)],
      ),
      alignment: Alignment.center,
      child: Text('$cantidad', style: estiloNs(12, peso: FontWeight.w700, color: TokensNs.blanco, tabular: true)),
    );
  }
}

/// Cabecera de sub-pantalla o página: botón volver (44) + título.
class CabeceraSubNs extends StatelessWidget {
  const CabeceraSubNs({super.key, required this.titulo, required this.onVolver, this.tamanio = 34, this.track = -0.05, this.derecha});

  final String titulo;
  final VoidCallback onVolver;
  final double tamanio;
  final double track;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BotonCircularNs(icono: IconoNs.volver, onTap: onVolver, etiqueta: 'Volver', tamanioIcono: 18, grosor: 2.4),
        const SizedBox(width: 12),
        Expanded(child: Text(titulo, style: tituloNs(tamanio, track: track, altura: 1.02, color: context.ns.ink))),
        ?derecha,
      ],
    );
  }
}

// ───────────────────────── Chips y segmentos ─────────────────────────

/// Píldora de filtro: 44, padding 18, 15/600.
class ChipNs extends StatelessWidget {
  const ChipNs({super.key, required this.texto, required this.activo, required this.onTap});

  final String texto;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Semantics(
      selected: activo,
      child: PresionNs(
        onTap: onTap,
        etiqueta: texto,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: activo ? ns.prim : ns.s, borderRadius: BorderRadius.circular(999)),
          child: Center(widthFactor: 1, child: Text(texto, maxLines: 1, style: estiloNs(15, peso: FontWeight.w600, color: activo ? TokensNs.blanco : ns.ink))),
        ),
      ),
    );
  }
}

/// Fila de chips que scrollea en horizontal sin barra (`margin 0 -20; padding 0 20`).
class FilaChipsNs extends StatelessWidget {
  const FilaChipsNs({super.key, required this.chips});
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: margenNs),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

/// Selector de 2–3 opciones: contenedor `s` (padding 5, gap 6), opciones de 46.
class SegmentoNs extends StatelessWidget {
  const SegmentoNs({super.key, required this.opciones, required this.indice, required this.onCambio, this.alto = 46});

  final List<String> opciones;
  final int indice;
  final ValueChanged<int> onCambio;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          for (var n = 0; n < opciones.length; n++) ...[
            if (n > 0) const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                selected: n == indice,
                child: PresionNs(
                  onTap: () => onCambio(n),
                  etiqueta: opciones[n],
                  child: Container(
                    height: alto,
                    decoration: BoxDecoration(color: n == indice ? ns.prim : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                    alignment: Alignment.center,
                    child: Text(opciones[n], maxLines: 1, style: estiloNs(15, peso: FontWeight.w600, color: n == indice ? TokensNs.blanco : ns.ink)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Campos ─────────────────────────

/// Campo de formulario: etiqueta 13/600 `mute` arriba y valor 20/500 (o
/// "grande" 40/450, alto 54). Fondo `s`, radio 28, padding 14/22/16.
class CampoNs extends StatelessWidget {
  const CampoNs({
    super.key,
    required this.etiqueta,
    this.controller,
    this.placeholder,
    this.grande = false,
    this.teclado,
    this.formatos,
    this.onChanged,
    this.oculto = false,
    this.radio = 28,
    this.foco,
    this.autofoco = false,
    this.habilitado = true,
    this.alineadoDerecha = false,
    this.onSubmit,
  });

  final String etiqueta;
  final TextEditingController? controller;
  final String? placeholder;
  final bool grande;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;
  final ValueChanged<String>? onChanged;
  final bool oculto;
  final double radio;
  final FocusNode? foco;
  final bool autofoco;
  final bool habilitado;
  final bool alineadoDerecha;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(radio)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: estiloNs(13, peso: FontWeight.w600, color: ns.mute)),
          const SizedBox(height: 4),
          SizedBox(
            height: grande ? 54 : null,
            child: TextField(
              controller: controller,
              focusNode: foco,
              autofocus: autofoco,
              enabled: habilitado,
              obscureText: oculto,
              keyboardType: teclado,
              inputFormatters: formatos,
              onChanged: onChanged,
              onSubmitted: onSubmit,
              textAlign: alineadoDerecha ? TextAlign.right : TextAlign.left,
              cursorColor: ns.ink,
              style: grande ? tituloNs(40, track: -0.05, color: ns.ink) : estiloNs(20, peso: FontWeight.w500, color: ns.ink, tabular: true),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: (grande ? tituloNs(40, track: -0.05) : estiloNs(20, peso: FontWeight.w500)).copyWith(color: ns.mute, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Solo dígitos (los importes y cantidades del mock se toman así).
final List<TextInputFormatter> soloDigitosNs = [FilteringTextInputFormatter.digitsOnly];

/// Campo de búsqueda: píldora `s`, lupa y texto; alto 52 (Productos) o 56.
class BuscadorNs extends StatelessWidget {
  const BuscadorNs({
    super.key,
    required this.controller,
    required this.placeholder,
    this.alto = 56,
    this.onChanged,
    this.tamanioTexto = 17,
    this.tamanioLupa = 20,
    this.foco,
    this.autofoco = false,
    this.conBorrar = false,
    this.onBorrar,
  });

  final TextEditingController controller;
  final String placeholder;
  final double alto;
  final ValueChanged<String>? onChanged;
  final double tamanioTexto;
  final double tamanioLupa;
  final FocusNode? foco;
  final bool autofoco;
  final bool conBorrar;
  final VoidCallback? onBorrar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      height: alto,
      padding: const EdgeInsets.only(left: 18, right: 6),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          IconoNsWidget(IconoNs.lupa, tamanio: tamanioLupa, color: ns.mute),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: foco,
              autofocus: autofoco,
              onChanged: onChanged,
              cursorColor: ns.ink,
              style: estiloNs(tamanioTexto, peso: FontWeight.w500, color: ns.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: estiloNs(tamanioTexto, peso: FontWeight.w500, color: ns.mute),
              ),
            ),
          ),
          if (conBorrar) BotonCircularNs(icono: IconoNs.cerrar, onTap: onBorrar, etiqueta: 'Borrar', fondo: Colors.transparent, tamanioIcono: 18),
        ],
      ),
    );
  }
}

// ───────────────────────── Interruptor y stepper ─────────────────────────

/// Interruptor: fila píldora (mín. 64) con pista 56×32 y perilla 26.
class InterruptorNs extends StatelessWidget {
  const InterruptorNs({super.key, required this.etiqueta, required this.encendido, required this.onCambio, this.descripcion});

  final String etiqueta;
  final String? descripcion;
  final bool encendido;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final reducido = sinMovimiento(context);
    return Semantics(
      toggled: encendido,
      child: PresionNs(
        onTap: () => onCambio(!encendido),
        etiqueta: etiqueta,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(etiqueta, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                    if (descripcion != null) ...[
                      const SizedBox(height: 2),
                      Text(descripcion!, style: estiloNs(14, color: ns.mute)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              AnimatedContainer(
                duration: reducido ? Duration.zero : const Duration(milliseconds: 200),
                width: 56,
                height: 32,
                padding: const EdgeInsets.all(3),
                alignment: encendido ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(color: encendido ? ns.ink : ns.line, borderRadius: BorderRadius.circular(999)),
                child: Container(width: 26, height: 26, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stepper − n +: contenedor con padding 3, botones de 44 y cantidad de ancho
/// mínimo [anchoCantidad].
class StepperNs extends StatelessWidget {
  const StepperNs({super.key, required this.cantidad, required this.onMenos, required this.onMas, this.fondo, this.anchoCantidad = 60, this.tamanioCantidad = 16});

  final String cantidad;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;
  final Color? fondo;
  final double anchoCantidad;
  final double tamanioCantidad;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: fondo ?? ns.paper, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotonCircularNs(icono: IconoNs.menos, onTap: onMenos, etiqueta: 'Menos', tamanioIcono: 14, grosor: 2.6, colorIcono: ns.ink),
          SizedBox(
            width: anchoCantidad,
            child: Text(cantidad, textAlign: TextAlign.center, maxLines: 1, style: estiloNs(tamanioCantidad, peso: FontWeight.w700, tabular: true, color: ns.ink)),
          ),
          BotonCircularNs(icono: IconoNs.masMas, onTap: onMas, etiqueta: 'Más', tamanioIcono: 14, grosor: 2.6, colorIcono: ns.ink),
        ],
      ),
    );
  }
}

// ───────────────────────── Avisos y tarjetas ─────────────────────────

enum TonoNs { neutro, warn, good, bad, info }

/// Aviso informativo: padding 14/18, radio 22, 14/1.4.
class InfoNs extends StatelessWidget {
  const InfoNs(this.texto, {super.key, this.tono = TonoNs.neutro, this.tamanio = 14, this.radio = 22, this.peso = FontWeight.w400});

  final String texto;
  final TonoNs tono;
  final double tamanio;
  final double radio;
  final FontWeight peso;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final (fondo, color) = switch (tono) {
      TonoNs.neutro => (ns.s, ns.mute),
      TonoNs.warn => (ns.wbg, ns.w),
      TonoNs.good => (ns.gbg, ns.g),
      TonoNs.bad => (ns.bbg, ns.b),
      TonoNs.info => (ns.ibg, ns.i),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(radio)),
      child: Text(texto, style: estiloNs(tamanio, peso: peso, altura: 1.4, color: color)),
    );
  }
}

/// Rótulo de sección en mayúsculas.
class SeccionNs extends StatelessWidget {
  const SeccionNs(this.texto, {super.key, this.derecha});
  final String texto;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    final t = Text(mayusculasNs(texto), style: seccionNs(context.ns.mute));
    if (derecha == null) return t;
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [t, derecha!]);
  }
}

/// Tarjeta oscura "héroe": fondo `hero`, texto blanco, radio 34 por defecto.
class HeroNs extends StatelessWidget {
  const HeroNs({super.key, required this.child, this.radio = 34, this.padding = const EdgeInsets.fromLTRB(24, 22, 24, 22), this.alto, this.ancho});

  final Widget child;
  final double radio;
  final EdgeInsets padding;
  final double? alto;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      height: alto,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: context.ns.hero, borderRadius: BorderRadius.circular(radio)),
      child: DefaultTextStyle.merge(style: const TextStyle(color: TokensNs.blanco), child: child),
    );
  }
}

/// Lista agrupada: un solo bloque con líneas finas de 1 px entre filas.
class ListaAgrupadaNs extends StatelessWidget {
  const ListaAgrupadaNs({super.key, required this.filas});
  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        color: TokensNs.lineaFina,
        child: Column(
          children: [
            for (var n = 0; n < filas.length; n++) ...[
              if (n > 0) const SizedBox(height: 1),
              ColoredBox(color: ns.s, child: filas[n]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila de clave/valor con línea inferior fina (Resumen de Caja, cierre).
class FilaClaveValorNs extends StatelessWidget {
  const FilaClaveValorNs({super.key, required this.clave, required this.valor, this.colorValor, this.tamanioValor = 19, this.sinLinea = false, this.padding = const EdgeInsets.symmetric(vertical: 14)});

  final String clave;
  final String valor;
  final Color? colorValor;
  final double tamanioValor;
  final bool sinLinea;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: padding,
      decoration: BoxDecoration(border: sinLinea ? null : const Border(bottom: BorderSide(color: TokensNs.lineaFina))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(clave, style: estiloNs(15, color: ns.mute))),
          const SizedBox(width: 14),
          Text(valor, style: estiloNs(tamanioValor, peso: FontWeight.w600, color: colorValor ?? ns.ink, tabular: true)),
        ],
      ),
    );
  }
}

/// Tarjeta de lista / fila navegable: círculo de icono 44 (`paper`), título
/// 17/500, subtítulo 14 `mute` y chevrón.
class TarjetaFilaNs extends StatelessWidget {
  const TarjetaFilaNs({
    super.key,
    required this.titulo,
    required this.onTap,
    this.subtitulo,
    this.icono,
    this.derecha,
    this.chevron = true,
    this.fondo,
    this.colorTexto,
    this.colorSubtitulo,
    this.radio = 28,
    this.minAlto = 64,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 20, 12),
    this.tamanioTitulo = 17,
    this.colorIcono,
    this.fondoIcono,
  });

  final String titulo;
  final String? subtitulo;
  final IconoNs? icono;
  final Widget? derecha;
  final bool chevron;
  final VoidCallback? onTap;
  final Color? fondo;
  final Color? colorTexto;
  final Color? colorSubtitulo;
  final double radio;
  final double minAlto;
  final EdgeInsets padding;
  final double tamanioTitulo;
  final Color? colorIcono;
  final Color? fondoIcono;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final texto = colorTexto ?? ns.ink;
    return PresionNs(
      onTap: onTap,
      etiqueta: titulo,
      child: Container(
        constraints: BoxConstraints(minHeight: minAlto),
        padding: padding,
        decoration: BoxDecoration(color: fondo ?? ns.s, borderRadius: BorderRadius.circular(radio)),
        child: Row(
          children: [
            if (icono != null) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: fondoIcono ?? ns.paper, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: IconoNsWidget(icono!, tamanio: 20, color: colorIcono ?? texto),
              ),
              const SizedBox(width: 14),
            ] else
              const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titulo, style: estiloNs(tamanioTitulo, peso: FontWeight.w500, track: -0.02, color: texto)),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitulo!, style: estiloNs(14, color: colorSubtitulo ?? ns.mute, altura: 1.3)),
                  ],
                ],
              ),
            ),
            ?derecha,
            if (chevron) ...[const SizedBox(width: 8), IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.mute, grosor: 2.2)],
          ],
        ),
      ),
    );
  }
}

/// Casilla circular de selección (26) o de "separado" (30).
class CasillaNs extends StatelessWidget {
  const CasillaNs({super.key, required this.marcada, this.tamanio = 26});
  final bool marcada;
  final double tamanio;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      width: tamanio,
      height: tamanio,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: marcada ? ns.prim : ns.paper,
        border: marcada ? null : Border.all(color: ns.line, width: 2),
      ),
      alignment: Alignment.center,
      child: marcada ? IconoNsWidget(IconoNs.tilde, tamanio: tamanio * 0.6, color: TokensNs.blanco, grosor: 2.6) : null,
    );
  }
}

/// Etiqueta chica "Sin stock" / "Poco stock": 12/700, radio 999, padding 2/9.
class EtiquetaStockNs extends StatelessWidget {
  const EtiquetaStockNs(this.texto, {super.key, required this.sinStock});
  final String texto;
  final bool sinStock;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: sinStock ? ns.bbg : ns.wbg, borderRadius: BorderRadius.circular(999)),
      child: Text(texto, style: estiloNs(12, peso: FontWeight.w700, color: sinStock ? ns.b : ns.w)),
    );
  }
}

// ───────────────────────── Plata ─────────────────────────

/// Plata con el formato del mock: `$ 1.234.567`, punto de miles, sin
/// decimales y **espacio duro** entre el signo y el número (docs/00).
/// [centavos] es el monto de la app (centavos); negativo lleva "-" adelante.
String plataNs(int centavos) {
  final texto = formatearARS(centavos.abs(), conSigno: false);
  return '${centavos < 0 ? '-' : ''}\$\u00A0$texto';
}
