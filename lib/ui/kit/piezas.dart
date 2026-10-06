// Las piezas comunes del mock v4 (`p1_head.html`, "tipografía y piezas comunes" y "listas maestro/detalle"), una por
// clase CSS, con sus medidas exactas. Las pantallas se arman SOLO con esto: si a una pantalla le falta algo, se agrega
// acá con su nombre del mock, no se dibuja suelto.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ic.dart';
import 'mov.dart';
import 'paleta.dart';
import 'texto.dart';
import 'tocable.dart';

// ───────────────────────────── botón (.btn) ─────────────────────────────

enum VarBtn { prim, blue, dark, ton, out, ai, red }

enum TamBtn { xs, sm, md, lg }

/// `.btn` con sus variantes (`.blue`, `.dark`, `.ton`, `.out`, `.ai`, `.red`) y tamaños (`.xs` 36, `.sm` 44, normal 56,
/// `.lg` 76). [kbd] es el atajo impreso; [flecha] el círculo con la flecha de los botones grandes (`.go`).
class Btn extends StatelessWidget {
  const Btn(
    this.texto, {
    super.key,
    required this.onTap,
    this.variante = VarBtn.prim,
    this.tam = TamBtn.md,
    this.icono,
    this.kbd,
    this.ancho = false,
    this.flecha = false,
    this.sobreGris = false,
    this.tooltip,
    this.etiqueta,
    this.focusNode,
    this.alto,
    this.tamanioTexto,
    this.padding,
  });

  final String texto;
  final VoidCallback? onTap;
  final VarBtn variante;
  final TamBtn tam;
  final Ic? icono;
  final String? kbd;

  /// `.wide`: ocupa todo el ancho.
  final bool ancho;
  final bool flecha;

  /// `.card .btn.ton`: un botón tonal dentro de un bloque gris va blanco.
  final bool sobreGris;
  final String? tooltip;
  final String? etiqueta;
  final FocusNode? focusNode;

  /// Para los pocos lugares donde el mock pisa la medida (`style="height:72px"`).
  final double? alto;
  final double? tamanioTexto;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (h, pad, fs) = switch (tam) {
      TamBtn.xs => (36.0, 15.0, 14.0),
      TamBtn.sm => (44.0, 20.0, 15.0),
      TamBtn.md => (56.0, 28.0, 17.0),
      TamBtn.lg => (76.0, 34.0, 21.0),
    };
    final habilitado = onTap != null;
    final (Color fondo, Color fondoEncima, Color cTexto, Color? sombra, bool borde) = switch (variante) {
      VarBtn.prim => (p.prim, p.prim, p.sobrePrim, const Color(0x33121317), false),
      VarBtn.blue => (p.azul, p.azulOscuro, Colors.white, const Color(0x522F5BE8), false),
      VarBtn.dark => (p.tinta, p.tinta, p.papel, const Color(0x33121317), false),
      VarBtn.ton => (sobreGris ? p.papel : p.s, p.s2, p.tinta, null, false),
      VarBtn.out => (Colors.transparent, p.s, p.tinta, null, true),
      // En oscuro el azul sobre su fondo azul oscuro no llega a 4,5:1: la letra va más clara.
      VarBtn.ai => (p.azulClaro, Color.alphaBlend(p.azul.withValues(alpha: .18), p.azulClaro), p.oscuro ? Color.lerp(p.azul, Colors.white, .45)! : p.azul, null, false),
      VarBtn.red => (p.bbg, p.bbg, p.b, null, false),
    };
    final altura = alto ?? h;
    final tamTexto = tamanioTexto ?? fs;
    return Opacity(
      opacity: habilitado ? 1 : .38,
      child: Levantable(
        habilitado: habilitado,
        dy: (variante == VarBtn.ton || variante == VarBtn.out) ? 2 : 2,
        builder: (context, encima) => Tocable(
          onTap: onTap,
          radio: altura / 2,
          tooltip: tooltip,
          etiqueta: etiqueta,
          focusNode: focusNode,
          child: AnimatedContainer(
            duration: ms(300),
            curve: curvaEase,
            height: altura,
            width: ancho ? double.infinity : null,
            padding: padding ?? EdgeInsets.only(left: pad, right: flecha ? pad - 20 : pad),
            decoration: BoxDecoration(
              color: encima ? fondoEncima : fondo,
              borderRadius: BorderRadius.circular(999),
              border: borde ? Border.all(color: p.linea, width: 1.5) : null,
              boxShadow: encima && sombra != null ? [BoxShadow(color: sombra, blurRadius: 34, offset: const Offset(0, 14))] : null,
            ),
            child: Row(
              mainAxisSize: ancho ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: flecha ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icono != null) ...[Icono(icono!, size: tamTexto + 1, color: cTexto), const SizedBox(width: 10)],
                    Flexible(
                      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(tamTexto, 600, color: cTexto)),
                    ),
                    if (kbd != null) ...[const SizedBox(width: 10), Kbd(kbd!, color: cTexto)],
                  ],
                ),
                ),
                if (flecha) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: tam == TamBtn.lg ? 54 : 44,
                    height: tam == TamBtn.lg ? 54 : 44,
                    decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Icono(Ic.arrow, size: 24, color: cTexto, grosor: 2.3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.kbd`: el atajo impreso en chiquito, con un fondo del 9 % del color del texto.
class Kbd extends StatelessWidget {
  const Kbd(this.texto, {super.key, this.color, this.tamanio = 12, this.fondo, this.opacidad = .8});

  final String texto;
  final Color? color;
  final double tamanio;
  final Color? fondo;
  final double opacidad;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? context.p.tinta;
    return Opacity(
      opacity: opacidad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fondo ?? c.withValues(alpha: .09), borderRadius: BorderRadius.circular(8)),
        child: Text(texto, maxLines: 1, softWrap: false, style: Tipos.kbd(c, tamanio: tamanio)),
      ),
    );
  }
}

// ───────────────────────────── chip (.chip) ─────────────────────────────

/// `.chip`: píldora con contorno; elegida (`aria-pressed`) se llena de tinta. [chico] = `.chip.sm`.
class ChipMock extends StatelessWidget {
  const ChipMock(
    this.texto, {
    super.key,
    required this.onTap,
    this.elegido = false,
    this.chico = false,
    this.icono,
    this.kbd,
    this.colorTexto,
    this.tooltip,
  });

  final String texto;
  final VoidCallback? onTap;
  final bool elegido;
  final bool chico;
  final Ic? icono;
  final String? kbd;
  final Color? colorTexto;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final h = chico ? 38.0 : 46.0;
    final fs = chico ? 14.5 : 16.0;
    final pad = chico ? 16.0 : 17.0;
    return Levantable(
      dy: 1,
      achicarAlApretar: false,
      habilitado: onTap != null,
      builder: (context, encima) {
        final fondo = elegido ? p.tinta : (encima ? p.s : p.papel);
        final cTexto = elegido ? p.papel : (colorTexto ?? p.tinta);
        return Tocable(
          onTap: onTap,
          radio: h / 2,
          seleccionado: elegido,
          tooltip: tooltip,
          child: AnimatedContainer(
            duration: ms(200),
            height: h,
            padding: EdgeInsets.symmetric(horizontal: pad),
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(999),
              border: elegido ? null : Border.all(color: p.linea),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icono != null) ...[Icono(icono!, size: fs + 2, color: cTexto), const SizedBox(width: 8)],
                Text(texto, maxLines: 1, softWrap: false, style: estilo(fs, 500, color: cTexto)),
                if (kbd != null) ...[const SizedBox(width: 8), Kbd(kbd!, color: cTexto)],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────── segmentado (.seg) ─────────────────────────────

/// `.seg`: cápsula gris con opciones; la elegida es blanca con sombrita. [llenar] = `.seg.fill` (todas del mismo ancho).
class Seg<V> extends StatelessWidget {
  const Seg({
    super.key,
    required this.opciones,
    required this.valor,
    required this.onCambio,
    this.llenar = false,
    this.alto = 46,
    this.tamanioTexto = 16,
    this.paddingOpcion = 24,
  });

  final List<(V, String)> opciones;
  final V valor;
  final ValueChanged<V>? onCambio;
  final bool llenar;
  final double alto;
  final double tamanioTexto;
  final double paddingOpcion;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final botones = [
      for (final (i, (v, t)) in opciones.indexed) ...[
        if (i > 0) const SizedBox(width: 2),
        _opcion(p, v, t),
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: llenar ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final b in botones)
            if (llenar && b is! SizedBox) Expanded(child: b) else b,
        ],
      ),
    );
  }

  Widget _opcion(PaletaMock p, V v, String t) {
    final elegido = v == valor;
    return Tocable(
      onTap: onCambio == null ? null : () => onCambio!(v),
      radio: alto / 2,
      seleccionado: elegido,
      child: AnimatedContainer(
        duration: ms(250),
        curve: curvaEase,
        height: alto,
        padding: EdgeInsets.symmetric(horizontal: paddingOpcion),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: elegido ? p.papel : p.papel.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(999),
          boxShadow: elegido ? const [BoxShadow(color: Color(0x1A0D1017), blurRadius: 10, offset: Offset(0, 2))] : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: ms(200),
          style: estilo(tamanioTexto, 600, color: elegido ? p.tinta : p.mute),
          child: Text(t, maxLines: 1, softWrap: false, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// ───────────────────────────── etiqueta (.tag) ─────────────────────────────

enum TonoMock { neutro, g, b, w, i, dark }

extension ColoresDeTono on TonoMock {
  (Color fondo, Color texto) colores(PaletaMock p) => switch (this) {
        TonoMock.neutro => (p.s2, p.mute),
        TonoMock.g => (p.gbg, p.g),
        TonoMock.b => (p.bbg, p.b),
        TonoMock.w => (p.wbg, p.w),
        TonoMock.i => (p.ibg, p.i),
        TonoMock.dark => (p.tinta, p.papel),
      };
}

/// `.tag`: etiqueta de 30 px ("Al día", "Le debés $ 54.000", "Sin stock").
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.tono = TonoMock.neutro, this.icono, this.alto = 30, this.tamanioTexto = 13.5, this.padding = 13});

  final String texto;
  final TonoMock tono;
  final Ic? icono;
  final double alto;
  final double tamanioTexto;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final (fondo, texto_) = tono.colores(context.p);
    return Container(
      height: alto,
      padding: EdgeInsets.symmetric(horizontal: padding),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icono(icono!, size: 15, color: texto_, grosor: 2.2), const SizedBox(width: 6)],
          Flexible(child: Text(texto, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: estilo(tamanioTexto, 600, color: texto_))),
        ],
      ),
    );
  }
}

// ───────────────────────────── bloques ─────────────────────────────

/// `.card`: bloque gris de radio 32 (o `.card.line` blanco con contorno; o con tono `.card.w/.g/.b/.i`).
class Tarjeta extends StatelessWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
    this.linea = false,
    this.tono,
    this.radio = 32,
    this.color,
    this.alto,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool linea;
  final TonoMock? tono;
  final double radio;
  final Color? color;
  final double? alto;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (Color fondo, Color? texto) = tono != null ? tono!.colores(p) : (linea ? p.papel : (color ?? p.s), null);
    Widget hijo = child;
    if (texto != null) hijo = DefaultTextStyle.merge(style: TextStyle(color: texto), child: IconTheme.merge(data: IconThemeData(color: texto), child: hijo));
    return Container(
      height: alto,
      padding: padding,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(radio),
        border: linea ? Border.all(color: p.linea, width: 1.5) : null,
      ),
      child: hijo,
    );
  }
}

/// `.hero`: el bloque oscuro (o `.hero.blue`) con la cifra importante.
class BloqueHero extends StatelessWidget {
  const BloqueHero({super.key, required this.child, this.azul = false, this.padding = const EdgeInsets.symmetric(horizontal: 30, vertical: 24), this.radio = 34});

  final Widget child;
  final bool azul;
  final EdgeInsets padding;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: azul ? p.azul : p.hero, borderRadius: BorderRadius.circular(radio)),
      child: DefaultTextStyle.merge(style: TextStyle(color: p.sobreHero, fontFamily: familiaMock), child: child),
    );
  }
}

/// `.list`: filas sobre gris separadas por una línea finísima, todo con radio 30.
class Lista extends StatelessWidget {
  const Lista({super.key, required this.filas, this.radio = 30, this.color});

  final List<Widget> filas;
  final double radio;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: ColoredBox(
        color: p.pelo,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, f) in filas.indexed) ...[
              if (i > 0) const SizedBox(height: 1),
              ColoredBox(color: color ?? p.s, child: f),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.kv`: fila clave/valor ("Debería haber · $ 253.000"). Con [onTap] es `button.kv` (se ilumina al pasar).
class Kv extends StatelessWidget {
  const Kv(this.clave, this.valor, {super.key, this.valorWidget, this.onTap, this.colorValor, this.tamanioValor, this.claveWidget});

  final String clave;
  final String valor;
  final Widget? valorWidget;
  final Widget? claveWidget;
  final VoidCallback? onTap;
  final Color? colorValor;
  final double? tamanioValor;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget fila(bool encima) => AnimatedContainer(
          duration: ms(200),
          color: encima ? p.s2 : Colors.transparent,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Expanded(child: claveWidget ?? Text(clave, style: estilo(16, 400, color: p.mute))),
              const SizedBox(width: 16),
              valorWidget ?? Text(valor, style: estilo(tamanioValor ?? 16, 600, color: colorValor ?? p.tinta, num: true)),
            ],
          ),
        );
    if (onTap == null) return fila(false);
    return _Encima(builder: (encima) => Tocable(onTap: onTap, radio: 0, child: fila(encima)));
  }
}

/// `.rowb`: fila elegible (proveedor, venta del historial). Elegida = azul claro con aro azul.
class Rowb extends StatelessWidget {
  const Rowb({
    super.key,
    required this.titulo,
    this.detalle,
    this.izquierda,
    this.derecha,
    this.elegida = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.tamanioTitulo = 17,
    this.tamanioDetalle = 14.5,
    this.lineasTitulo = 1,
    this.lineasDetalle = 1,
  });

  final String titulo;
  final String? detalle;
  final Widget? izquierda;
  final Widget? derecha;
  final bool elegida;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double tamanioTitulo;
  final double tamanioDetalle;
  final int lineasTitulo;
  final int lineasDetalle;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return _Encima(
      builder: (encima) => Tocable(
        onTap: onTap,
        radio: 26,
        seleccionado: elegida,
        child: AnimatedContainer(
          duration: ms(200),
          padding: padding,
          decoration: BoxDecoration(
            color: elegida ? p.azulClaro : (encima ? p.s2 : p.s),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: elegida ? p.azul : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              if (izquierda != null) ...[izquierda!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, maxLines: lineasTitulo, overflow: TextOverflow.ellipsis, style: estilo(tamanioTitulo, 550, color: p.tinta)),
                    if (detalle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(detalle!, maxLines: lineasDetalle, overflow: TextOverflow.ellipsis, style: estilo(tamanioDetalle, 400, color: p.mute)),
                      ),
                  ],
                ),
              ),
              if (derecha != null) ...[const SizedBox(width: 14), derecha!],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.note`: aviso en bloque (gris, o con tono).
class Nota extends StatelessWidget {
  const Nota({super.key, this.texto, this.child, this.tono, this.icono});

  final String? texto;
  final Widget? child;
  final TonoMock? tono;
  final Ic? icono;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (fondo, color) = tono == null ? (p.s, p.mute) : tono!.colores(p);
    final cuerpo = child ?? Text(texto ?? '', style: estilo(15, 400, color: color, alto: 1.5));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(24)),
      child: DefaultTextStyle.merge(
        style: estilo(15, 400, color: color, alto: 1.5),
        child: icono == null
            ? cuerpo
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 2, right: 10), child: Icono(icono!, size: 18, color: color)),
                Expanded(child: cuerpo),
              ]),
      ),
    );
  }
}

/// `.sec`: título de sección con el puntito azul.
class Sec extends StatelessWidget {
  const Sec(this.texto, {super.key, this.extra});
  final String texto;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: p.azul, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Flexible(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(15, 600, color: p.mute))),
        if (extra != null) ...[const SizedBox(width: 10), extra!],
      ],
    );
  }
}

/// `.av`: avatar redondo con la inicial.
class Avatar extends StatelessWidget {
  const Avatar(this.texto, {super.key, this.fondo, this.color, this.diametro = 44, this.tamanioTexto = 17});

  final String texto;
  final Color? fondo;
  final Color? color;
  final double diametro;
  final double tamanioTexto;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final inicial = texto.trim().isEmpty ? '?' : texto.trim().characters.first.toUpperCase();
    return Container(
      width: diametro,
      height: diametro,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fondo ?? p.papel, shape: BoxShape.circle),
      child: Text(inicial, style: estilo(tamanioTexto, 700, color: color ?? p.tinta)),
    );
  }
}

/// `.ibox`: círculo blanco con un ícono adentro (46, o 38 con [chico]).
class Ibox extends StatelessWidget {
  const Ibox(this.icono, {super.key, this.chico = false, this.fondo, this.color, this.tamanioIcono});

  final Ic icono;
  final bool chico;
  final Color? fondo;
  final Color? color;
  final double? tamanioIcono;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final d = chico ? 38.0 : 46.0;
    return AnimatedContainer(
      duration: ms(300),
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fondo ?? p.papel, shape: BoxShape.circle),
      child: Icono(icono, size: tamanioIcono ?? (chico ? 18 : 22), color: color ?? p.tinta),
    );
  }
}

/// `.bar`: barra de 16 px con tramos de color que crecen desde 0 (700 ms).
class BarraTramos extends StatelessWidget {
  const BarraTramos({super.key, required this.tramos, this.alto = 16});

  /// (proporción 0..1, color).
  final List<(double, Color)> tramos;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: alto,
        color: context.p.s3,
        child: LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              for (final (f, color) in tramos)
                Crecer(
                  factor: f.clamp(0.0, 1.0),
                  builder: (context, k) => SizedBox(width: c.maxWidth * k, height: alto, child: ColoredBox(color: color)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.empty`: estado vacío centrado (ícono + texto).
class Vacio extends StatelessWidget {
  const Vacio({super.key, required this.texto, this.icono = Ic.check, this.tamanioIcono = 40, this.padding = const EdgeInsets.symmetric(vertical: 30)});

  final String texto;
  final Ic? icono;
  final double tamanioIcono;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icono(icono!, size: tamanioIcono, color: p.mute, grosor: 1.6), const SizedBox(height: 14)],
          Text(texto, textAlign: TextAlign.center, style: estilo(19, 400, color: p.mute, alto: 1.4)),
        ],
      ),
    );
  }
}

// ───────────────────────────── controles ─────────────────────────────

/// `.field`: campo apilado (etiqueta chica arriba, valor grande abajo) sobre gris, con aro azul al enfocar. [grande] es
/// `.field.big` (56 px). Sin [controller] muestra [valor] fijo (`.field .val`).
class Campo extends StatefulWidget {
  const Campo({
    super.key,
    required this.etiqueta,
    this.controller,
    this.focusNode,
    this.valor,
    this.pista,
    this.grande = false,
    this.autofocus = false,
    this.teclado,
    this.formatos,
    this.onChanged,
    this.onSubmitted,
    this.derecha,
    this.campoKey,
    this.textInputAction,
    this.maxLineas = 1,
    this.obscuro = false,
    this.color,
    this.enabled = true,
  });

  final String etiqueta;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? valor;
  final String? pista;
  final bool grande;
  final bool autofocus;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Algo a la derecha del valor ("Traer saldo").
  final Widget? derecha;

  /// Llave del `TextField` de adentro (para los tests).
  final Key? campoKey;
  final TextInputAction? textInputAction;
  final int maxLineas;
  final bool obscuro;
  final Color? color;
  final bool enabled;

  @override
  State<Campo> createState() => _CampoState();
}

class _CampoState extends State<Campo> {
  FocusNode? _propio;
  FocusNode get _foco => widget.focusNode ?? (_propio ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _foco.addListener(_alCambiarFoco);
  }

  @override
  void didUpdateWidget(Campo old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _propio)?.removeListener(_alCambiarFoco);
      _foco.addListener(_alCambiarFoco);
    }
  }

  void _alCambiarFoco() => setState(() {});

  @override
  void dispose() {
    _foco.removeListener(_alCambiarFoco);
    _propio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final g = widget.grande;
    final estiloValor = g ? estilo(56, 450, color: p.tinta, em: -.05, alto: 1.15, num: true) : estilo(21, 500, color: p.tinta, em: -.01);
    final valor = widget.controller == null
        ? Text(widget.valor ?? '', style: estiloValor, maxLines: 1, overflow: TextOverflow.ellipsis)
        : AreaMinimaToque(
            child: TextField(
            key: widget.campoKey,
            controller: widget.controller,
            focusNode: _foco,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            keyboardType: widget.teclado,
            inputFormatters: widget.formatos,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            textInputAction: widget.textInputAction,
            maxLines: widget.maxLineas,
            minLines: 1,
            obscureText: widget.obscuro,
            style: estiloValor,
            cursorColor: p.azul,
            decoration: decoracionSinBorde(widget.pista, estiloValor.copyWith(color: p.soft)),
          ),
          );
    return GestureDetector(
      onTap: widget.controller == null ? null : () => _foco.requestFocus(),
      excludeFromSemantics: true,
      child: AnimatedContainer(
        duration: ms(200),
        padding: g ? const EdgeInsets.fromLTRB(28, 16, 28, 14) : const EdgeInsets.fromLTRB(24, 14, 24, 12),
        decoration: BoxDecoration(
          color: widget.color ?? p.s,
          borderRadius: BorderRadius.circular(28),
          boxShadow: _foco.hasFocus ? const [BoxShadow(color: PaletaMock.foco, spreadRadius: 2.5)] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.etiqueta, style: estilo(13, 600, color: p.mute)),
            const SizedBox(height: 3),
            if (widget.derecha == null) valor else Row(children: [Expanded(child: valor), widget.derecha!]),
          ],
        ),
      ),
    );
  }
}

/// `.tg` + `.track`: fila con título y detalle y el interruptor a la derecha (la bolita rebota con `--back`).
class Interruptor extends StatelessWidget {
  const Interruptor({super.key, required this.titulo, this.detalle, required this.valor, required this.onCambio, this.color});

  final String titulo;
  final String? detalle;
  final bool valor;
  final ValueChanged<bool>? onCambio;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Semantics(
      toggled: valor,
      child: Tocable(
        onTap: onCambio == null ? null : () => onCambio!(!valor),
        radio: 0,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: color ?? p.s,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, style: estilo(18, 600, color: p.tinta)),
                    if (detalle != null)
                      Padding(padding: const EdgeInsets.only(top: 3), child: Text(detalle!, style: estilo(14.5, 400, color: p.mute, alto: 1.35))),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Riel(encendido: valor),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.track`: el interruptor solo (56×32).
class Riel extends StatelessWidget {
  const Riel({super.key, required this.encendido});
  final bool encendido;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnimatedContainer(
      duration: ms(300),
      curve: curvaEase,
      width: 56,
      height: 32,
      decoration: BoxDecoration(color: encendido ? p.azul : p.s3, borderRadius: BorderRadius.circular(999)),
      child: AnimatedAlign(
        duration: ms(350),
        curve: curvaBack,
        alignment: encendido ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(3),
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}

/// `.ckb`: casilla de 24 con radio 8; tildada se llena de azul.
class Casilla extends StatelessWidget {
  const Casilla({super.key, required this.valor, required this.onCambio, this.etiqueta});

  final bool valor;
  final ValueChanged<bool>? onCambio;
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Semantics(
      checked: valor,
      child: Tocable(
        onTap: onCambio == null ? null : () => onCambio!(!valor),
        radio: 8,
        etiqueta: etiqueta,
        child: AnimatedContainer(
          duration: ms(150),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: valor ? p.azul : p.papel,
            borderRadius: BorderRadius.circular(8),
            border: valor ? null : Border.all(color: p.linea, width: 1.8),
          ),
          child: valor ? const Icono(Ic.check, size: 16, color: Colors.white, grosor: 3) : null,
        ),
      ),
    );
  }
}

/// `.ci`: botón redondo de 46 (campanita, tuerca, cerrar de un modal) que sube al pasar; [activo] lo llena de tinta.
class BotonCirculo extends StatelessWidget {
  const BotonCirculo({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.onTap,
    this.activo = false,
    this.insignia,
    this.diametro = 46,
    this.tamanioIcono = 22,
    this.grosor = 2,
    this.fondo,
    this.girarAlPasar = false,
  });

  final Ic icono;
  final String etiqueta;
  final VoidCallback? onTap;
  final bool activo;

  /// Número de la insignia roja (`.bd`); null o 0 sin insignia.
  final int? insignia;
  final double diametro;
  final double tamanioIcono;
  final double grosor;
  final Color? fondo;

  /// `.mhead .x:hover{transform:rotate(90deg)}`: la cruz de un modal gira en vez de subir.
  final bool girarAlPasar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Levantable(
      dy: girarAlPasar ? 0 : 2,
      habilitado: onTap != null,
      builder: (context, encima) => Tocable(
        onTap: onTap,
        radio: diametro / 2,
        etiqueta: etiqueta,
        tooltip: etiqueta,
        seleccionado: activo ? true : null,
        child: AnimatedContainer(
          duration: ms(200),
          width: diametro,
          height: diametro,
          decoration: BoxDecoration(color: activo ? p.tinta : (encima ? p.s2 : (fondo ?? p.s)), shape: BoxShape.circle),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedRotation(
                turns: girarAlPasar && encima ? .25 : 0,
                duration: ms(300),
                curve: curvaEase,
                child: Icono(icono, size: tamanioIcono, color: activo ? p.papel : p.tinta, grosor: grosor),
              ),
              if ((insignia ?? 0) > 0)
                Positioned(
                  top: 8 - 4,
                  right: 9 - 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PaletaMock.rojoInsignia,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: p.navbg2, width: 2),
                    ),
                    child: Text('$insignia', style: estilo(11, 700, color: Colors.white, alto: 1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── tabla (.tbl) ─────────────────────────────

class ColumnaTabla {
  const ColumnaTabla(this.titulo, {this.flex = 1, this.ancho, this.derecha = false});
  final String titulo;
  final int flex;
  final double? ancho;
  final bool derecha;
}

/// `.tbl` dentro de `.list.scrl`: cabecera fija gris (13/600 tenue), filas con línea finísima arriba que se iluminan al
/// pasar. Las filas se construyen a demanda (`ListView.builder`: lista larga, regla del proyecto).
class Tabla extends StatelessWidget {
  const Tabla({
    super.key,
    required this.columnas,
    required this.cantidad,
    required this.celdas,
    this.onTapFila,
    this.altoFila,
    this.encogerse = true,
    this.radio = 30,
    this.vacio,
    this.cabeceraPrimera,
    this.dentroDeScroll = false,
  });

  /// Adentro de algo que ya scrollea (una pantalla baja de 1366×768): la tabla mide todas sus filas y no scrollea sola.
  final bool dentroDeScroll;

  final List<ColumnaTabla> columnas;

  /// Algo en vez del título de la primera columna (el casillero de "seleccionar todos").
  final Widget? cabeceraPrimera;
  final int cantidad;

  /// Las celdas de la fila [i], una por columna.
  final List<Widget> Function(BuildContext context, int i) celdas;
  final ValueChanged<int>? onTapFila;
  final double? altoFila;

  /// `.list.scrl:has(>table){flex:0 1 auto}`: la tabla mide lo que sus filas y scrollea solo si no entra.
  final bool encogerse;
  final double radio;
  final Widget? vacio;

  Widget _fila(List<Widget> hijos, {required EdgeInsets padding}) {
    return Row(
      children: [
        for (final (i, c) in columnas.indexed)
          if (c.ancho != null)
            SizedBox(width: c.ancho, child: Padding(padding: padding, child: Align(alignment: c.derecha ? Alignment.centerRight : Alignment.centerLeft, child: hijos[i])))
          else
            Expanded(
              flex: c.flex,
              child: Padding(padding: padding, child: Align(alignment: c.derecha ? Alignment.centerRight : Alignment.centerLeft, child: hijos[i])),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final cabecera = Container(
      color: p.s,
      child: _fila(
        [
          for (final (i, c) in columnas.indexed)
            if (i == 0 && cabeceraPrimera != null)
              cabeceraPrimera!
            else
              // `--soft` en el mock, pero sobre el gris de la cabecera no llega a 4,5:1 a 13 px: va `mute` (contraste medido, DISENO.md).
              Text(c.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(13, 600, color: p.mute)),
        ],
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    );
    final cuerpo = cantidad == 0 && vacio != null
        // En una lista de un solo elemento: si el alto no alcanza, se corta en vez de desbordar.
        ? ListView(
            shrinkWrap: encogerse || dentroDeScroll,
            physics: dentroDeScroll ? const NeverScrollableScrollPhysics() : null,
            padding: EdgeInsets.zero,
            children: [ColoredBox(color: p.s, child: vacio!)],
          )
        : ListView.builder(
            shrinkWrap: encogerse || dentroDeScroll,
            physics: dentroDeScroll ? const NeverScrollableScrollPhysics() : null,
            padding: EdgeInsets.zero,
            itemCount: cantidad,
            itemExtent: altoFila,
            itemBuilder: (context, i) => _FilaTabla(
              onTap: onTapFila == null ? null : () => onTapFila!(i),
              child: _fila(celdas(context, i), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11)),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: ColoredBox(
        color: p.s,
        child: Column(
          mainAxisSize: encogerse || dentroDeScroll ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cabecera,
            if (dentroDeScroll)
              cuerpo
            else if (encogerse)
              Flexible(child: cuerpo)
            else
              Expanded(child: cuerpo),
          ],
        ),
      ),
    );
  }
}

class _FilaTabla extends StatelessWidget {
  const _FilaTabla({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return _Encima(
      builder: (encima) {
        final fila = AnimatedContainer(
          duration: ms(150),
          decoration: BoxDecoration(color: encima ? p.s2 : p.s, border: Border(top: BorderSide(color: p.pelo))),
          child: child,
        );
        return onTap == null ? fila : Tocable(onTap: onTap, radio: 0, child: fila);
      },
    );
  }
}

/// Texto de celda con el estilo de `.tbl td` (16; `.r` a la derecha y tabular).
Widget celda(BuildContext context, String texto, {bool num = false, Color? color, double peso = 400, double tamanio = 16, int lineas = 1}) {
  return Text(texto, maxLines: lineas, overflow: TextOverflow.ellipsis, style: estilo(tamanio, peso, color: color ?? context.p.tinta, num: num));
}

// ───────────────────────────── utilidades ─────────────────────────────

/// Reconstruye con `encima` = el mouse está sobre el área.
class _Encima extends StatefulWidget {
  const _Encima({required this.builder});
  final Widget Function(bool encima) builder;

  @override
  State<_Encima> createState() => _EncimaState();
}

class _EncimaState extends State<_Encima> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: widget.builder(_encima),
      );
}

/// Igual que `_Encima` pero público, para las pantallas que tienen su propio hover (tarjetas de producto, filas).
class AlPasar extends StatelessWidget {
  const AlPasar({super.key, required this.builder});
  final Widget Function(bool encima) builder;

  @override
  Widget build(BuildContext context) => _Encima(builder: builder);
}

/// `.stp`: cápsula gris con − valor + (la ganancia de cada categoría en Configuración). Botones de 34 que se oscurecen
/// al pasar; el valor en el medio, 16/600 tabular.
class Stp extends StatelessWidget {
  const Stp({super.key, required this.valor, required this.onMenos, required this.onMas, this.etiquetaMenos = 'Menos', this.etiquetaMas = 'Más'});

  final String valor;
  final VoidCallback? onMenos;
  final VoidCallback? onMas;
  final String etiquetaMenos;
  final String etiquetaMas;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget boton(Ic icono, String etiqueta, VoidCallback? onTap) => _Encima(
          builder: (encima) => Tocable(
            onTap: onTap,
            radio: 17,
            etiqueta: etiqueta,
            tooltip: etiqueta,
            child: AnimatedContainer(
              duration: ms(150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: encima && onTap != null ? p.s3 : Colors.transparent, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Opacity(opacity: onTap == null ? .38 : 1, child: Icono(icono, size: 14, color: p.tinta, grosor: 2.6)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(Ic.minus, etiquetaMenos, onMenos),
          const SizedBox(width: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 54),
            child: Text(valor, textAlign: TextAlign.center, style: estilo(16, 600, color: p.tinta, num: true)),
          ),
          const SizedBox(width: 2),
          boton(Ic.plus, etiquetaMas, onMas),
        ],
      ),
    );
  }
}
