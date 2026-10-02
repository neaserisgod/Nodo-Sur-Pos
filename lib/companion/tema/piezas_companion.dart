// Piezas de composición del rediseño "antigravity" de la companion: titulares
// grandes y livianos alineados a la izquierda, bloques gris muy redondeados,
// un bloque negro con partículas para lo más importante de cada pantalla, y
// líneas finas en vez de cajas dentro de cada bloque.
//
// Son solo de la companion: el escritorio sigue usando `lib/ui/comun`.

import 'package:flutter/material.dart';

import '../../ui/comun/tarjetas.dart' show Tono;
import '../../ui/tema/acentos.dart';
import '../../ui/tema/tokens.dart';
import 'campo_particulas.dart';
import 'presionable.dart';
import 'tema_companion.dart';

/// Rótulo de sección: punto con degradé + texto chico (el "eyebrow" de la web).
class EtiquetaSeccion extends StatelessWidget {
  const EtiquetaSeccion(this.texto, {super.key, this.derecha});

  final String texto;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFF3B6CFF), Color(0xFF8A5CF6), Color(0xFF18C3A4)]),
          ),
        ),
        const SizedBox(width: EspacioCompanion.sm),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colores.textoSecundario, fontWeight: FontWeight.w600),
          ),
        ),
        ?derecha,
      ],
    );
  }
}

/// Cifra grande con su etiqueta: el titular numérico de una pantalla.
class CifraGrande extends StatelessWidget {
  const CifraGrande({super.key, required this.etiqueta, required this.valor, this.nota, this.tono});

  final String etiqueta;
  final String valor;
  final String? nota;
  final Tono? tono;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final color = switch (tono) {
      Tono.ganancia => acentos.ganancia,
      Tono.alerta => acentos.alerta,
      Tono.error => colores.error,
      _ => colores.textoPrimario,
    };
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valor, maxLines: 1, style: textTheme.headlineLarge?.copyWith(color: color).tabular),
        ),
        if (nota != null) ...[
          const SizedBox(height: 2),
          Text(nota!, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Fila de cifras separadas por líneas verticales finas (sin cajas).
class FilaCifras extends StatelessWidget {
  const FilaCifras({super.key, required this.cifras});

  final List<Widget> cifras;

  @override
  Widget build(BuildContext context) {
    final borde = context.colores.borde;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cifras.length; i++) ...[
            if (i > 0) VerticalDivider(width: EspacioCompanion.xl, thickness: 1, color: borde),
            Expanded(child: cifras[i]),
          ],
        ],
      ),
    );
  }
}

/// Bloque gris muy redondeado con rótulo y contenido — reemplaza a
/// `TarjetaSeccion` del escritorio dentro de la companion.
class SeccionCompanion extends StatelessWidget {
  const SeccionCompanion({super.key, required this.titulo, required this.child, this.derecha});

  final String titulo;
  final Widget child;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EspacioCompanion.xl),
      decoration: BoxDecoration(
        color: context.colores.fondoBloque,
        borderRadius: BorderRadius.circular(radioSuperficieCompanion),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          EtiquetaSeccion(titulo, derecha: derecha),
          const SizedBox(height: EspacioCompanion.lg),
          child,
        ],
      ),
    );
  }
}

/// El bloque negro con partículas: lo más importante de cada pantalla (el
/// CTA de vender, lo que falta separar, el total a cobrar). Siempre oscuro,
/// también en modo claro, como el cierre de la web.
class BloqueHero extends StatelessWidget {
  const BloqueHero({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(EspacioCompanion.xl),
    this.minAlto = 0,
    this.animar = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double minAlto;
  final bool animar;

  @override
  Widget build(BuildContext context) {
    final fondo = context.acentosPlazoleta.gradienteAcento;
    final contenido = Container(
      constraints: BoxConstraints(minHeight: minAlto),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radioSuperficieCompanion + 4),
        gradient: LinearGradient(colors: fondo, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radioSuperficieCompanion + 4),
        child: Stack(
          children: [
            Positioned.fill(child: CampoParticulas(colores: particulasSobreNegro, animar: animar, densidad: 0.9)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
    if (onTap == null) return contenido;
    return Presionable(radio: radioSuperficieCompanion + 4, onTap: onTap!, child: contenido);
  }
}

/// Círculo blanco con flecha: el "ir" de los bloques hero.
class BotonFlecha extends StatelessWidget {
  const BotonFlecha({super.key, this.icono = Icons.arrow_forward_rounded, this.tamanio = 48});

  final IconData icono;
  final double tamanio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanio,
      height: tamanio,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(icono, color: const Color(0xFF121317), size: tamanio * 0.46),
    );
  }
}

/// Línea fina que separa filas dentro de un bloque.
class LineaFina extends StatelessWidget {
  const LineaFina({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: context.colores.borde);
}

/// Encabezado de pantalla: rótulo chico, titular grande y liviano y, si hace
/// falta, una bajada. Con `particulas` dibuja el campo de partículas detrás,
/// como el encabezado de las páginas de la web.
class EncabezadoCompanion extends StatelessWidget {
  const EncabezadoCompanion({
    super.key,
    required this.titulo,
    this.rotulo,
    this.bajada,
    this.particulas = false,
    this.derecha,
    this.padding = const EdgeInsets.fromLTRB(EspacioCompanion.xl, EspacioCompanion.xl, EspacioCompanion.xl, EspacioCompanion.lg),
  });

  final String titulo;
  final String? rotulo;
  final String? bajada;
  final bool particulas;
  final Widget? derecha;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final contenido = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rotulo != null) ...[EtiquetaSeccion(rotulo!), const SizedBox(height: EspacioCompanion.sm)],
                Text(titulo, style: textTheme.headlineLarge),
                if (bajada != null) ...[
                  const SizedBox(height: EspacioCompanion.sm),
                  Text(bajada!, style: textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario)),
                ],
              ],
            ),
          ),
          ?derecha,
        ],
      ),
    );
    if (!particulas) return contenido;
    return Stack(
      children: [
        Positioned.fill(
          child: CampoParticulas(
            colores: oscuro ? particulasSobreNegro : particulasSobreClaro,
            centro: const Alignment(0.75, -0.2),
            densidad: 0.7,
          ),
        ),
        contenido,
      ],
    );
  }
}

/// Fila de lista dentro de un bloque gris: círculo con inicial, título,
/// subtítulo opcional y chevron. Para elegir un usuario, un proveedor, etc.
class FilaElegible extends StatelessWidget {
  const FilaElegible({super.key, required this.titulo, required this.onTap, this.subtitulo, this.inicial});

  final String titulo;
  final String? subtitulo;
  final String? inicial;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Presionable(
      radio: radioSuperficieCompanion,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.lg, vertical: EspacioCompanion.lg),
        decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colores.fondo, shape: BoxShape.circle),
              child: Text(
                (inicial ?? titulo).trim().isEmpty ? '?' : (inicial ?? titulo).trim().characters.first.toUpperCase(),
                style: textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: EspacioCompanion.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: textTheme.titleMedium),
                  if (subtitulo != null) Text(subtitulo!, style: textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: colores.textoTenue, size: 22),
          ],
        ),
      ),
    );
  }
}
