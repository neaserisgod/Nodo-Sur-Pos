// Piezas del "Lenguaje de diseño" (Bruno, 2026-09-26, carpeta de mocks) que
// se repiten en Inicio, Separaciones, Proveedores e Historial: la tarjeta de
// un indicador, la tarjeta de sección con título e insignia, el grupo de
// pastillas para elegir vista o período, el punto de color, la fila
// suave de un medio de pago y la insignia. Ninguna pantalla arma estas
// formas a mano (regla del kit, ver `feedback_kit_comun`).

import 'package:flutter/material.dart';

import '../tema/acentos.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';

/// Tono de una [Insignia] o de la nota de una [TarjetaIndicador].
enum Tono { neutro, ganancia, alerta, error, acento }

({Color texto, Color fondo}) _colores(BuildContext context, Tono tono) {
  final c = context.colores;
  final a = context.acentosPlazoleta;
  return switch (tono) {
    Tono.neutro => (texto: c.textoSecundario, fondo: c.fondo),
    Tono.ganancia => (texto: a.ganancia, fondo: a.gananciaSuave),
    Tono.alerta => (texto: a.alerta, fondo: a.alertaSuave),
    Tono.error => (texto: c.error, fondo: c.error.withValues(alpha: 0.12)),
    Tono.acento => (texto: c.acento, fondo: c.acento.withValues(alpha: 0.12)),
  };
}

/// Punto de color que identifica una caja o un medio (efectivo, MP).
class PuntoColor extends StatelessWidget {
  const PuntoColor({super.key, required this.color, this.tamanio = 10});

  final Color color;
  final double tamanio;

  @override
  Widget build(BuildContext context) => Container(
    width: tamanio,
    height: tamanio,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Chip chico con texto ("4 productos", "Anulada", "+38%").
class Insignia extends StatelessWidget {
  const Insignia({super.key, required this.texto, this.tono = Tono.neutro});

  final String texto;
  final Tono tono;

  @override
  Widget build(BuildContext context) {
    final c = _colores(context, tono);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Espaciado.xs),
      decoration: BoxDecoration(color: c.fondo, borderRadius: BorderRadius.circular(10)),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.texto, fontWeight: Pesos.fuerte),
      ),
    );
  }
}

/// Un indicador de la fila de arriba de una pantalla: etiqueta, cifra grande
/// y una nota abajo. `destacada` es la tarjeta oscura del mock (la que lleva
/// a la acción principal); con [onTap] toda la tarjeta se toca.
class TarjetaIndicador extends StatelessWidget {
  const TarjetaIndicador({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.nota,
    this.tonoNota = Tono.neutro,
    this.tonoValor,
    this.destacada = false,
    this.onTap,
  });

  final String etiqueta;
  final String valor;
  final String? nota;
  final Tono tonoNota;

  /// Null: el color de texto normal. `Tono.ganancia` pinta la cifra de verde.
  final Tono? tonoValor;
  final bool destacada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final sobreOscuro = acentos.textoSobreColor;
    final colorEtiqueta = destacada ? sobreOscuro.withValues(alpha: 0.75) : colores.textoSecundario;
    final colorValor = destacada
        ? sobreOscuro
        : (tonoValor == null ? colores.textoPrimario : _colores(context, tonoValor!).texto);
    final colorNota = destacada
        ? sobreOscuro.withValues(alpha: 0.75)
        : (tonoNota == Tono.neutro ? colores.textoSecundario : _colores(context, tonoNota).texto);

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: colorEtiqueta, fontWeight: Pesos.medium),
              ),
            ),
            if (onTap != null) Icon(Icons.arrow_forward, size: 20, color: colorEtiqueta),
          ],
        ),
        const SizedBox(height: Espaciado.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valor, maxLines: 1, style: textTheme.headlineMedium?.copyWith(color: colorValor).tabular),
        ),
        if (nota != null) ...[
          const SizedBox(height: Espaciado.xs),
          Text(
            nota!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: colorNota, fontWeight: Pesos.medium),
          ),
        ],
      ],
    );

    final tarjeta = Superficie(
      padding: const EdgeInsets.all(Espaciado.xl - Espaciado.xs),
      degrade: destacada ? acentos.gradienteAcento : null,
      child: contenido,
    );
    if (onTap == null) return tarjeta;
    return Presionable(radio: radioSuperficieEscritorio, onTap: onTap!, child: tarjeta);
  }
}

/// Tarjeta de una sección de la pantalla: título, insignia o acción a la
/// derecha, y el contenido abajo.
class TarjetaSeccion extends StatelessWidget {
  const TarjetaSeccion({super.key, required this.titulo, this.insignia, this.accion, required this.child});

  final String titulo;
  final Widget? insignia;
  final Widget? accion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.lg + Espaciado.xs, Espaciado.xl, Espaciado.lg + Espaciado.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
              ),
              ?insignia,
              if (accion != null) ...[const SizedBox(width: Espaciado.sm), accion!],
            ],
          ),
          const SizedBox(height: Espaciado.md + Espaciado.xs / 2),
          child,
        ],
      ),
    );
  }
}

/// Fila suave con el color de un medio: punto + etiqueta a la izquierda,
/// monto a la derecha (la de "Efectivo"/"Mercado Pago" de los mocks).
class FilaMedio extends StatelessWidget {
  const FilaMedio({super.key, required this.color, required this.etiqueta, required this.monto, this.apagada = false});

  final Color color;
  final String etiqueta;
  final String monto;
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.md + Espaciado.xs / 2, vertical: Espaciado.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: apagada ? 0.05 : 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          PuntoColor(color: color.withValues(alpha: apagada ? 0.5 : 1)),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: apagada ? colores.textoTenue : Color.lerp(color, colores.textoPrimario, 0.35),
                fontWeight: Pesos.medium,
              ),
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                monto,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: Pesos.fuerte, color: apagada ? colores.textoTenue : colores.textoPrimario)
                    .tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila dentro de una [TarjetaSeccion] (stock bajo, pendientes): fondo apenas
/// distinto, título y subtítulo a la izquierda, algo a la derecha.
class FilaSuave extends StatelessWidget {
  const FilaSuave({super.key, required this.titulo, this.subtitulo, this.icono, this.derecha});

  final String titulo;
  final String? subtitulo;
  final IconData? icono;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.md + Espaciado.xs / 2, vertical: Espaciado.sm),
      decoration: BoxDecoration(
        color: Color.lerp(colores.fondo, colores.fondoBloque, 0.55),
        borderRadius: BorderRadius.circular(radioControlEscritorio),
      ),
      child: Row(
        children: [
          if (icono != null) ...[Icon(icono, size: 20, color: colores.textoSecundario), const SizedBox(width: Espaciado.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
                ),
                if (subtitulo != null)
                  Text(subtitulo!, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
              ],
            ),
          ),
          if (derecha != null) ...[const SizedBox(width: Espaciado.sm), derecha!],
        ],
      ),
    );
  }
}

/// Grupo de pastillas para elegir una opción (vista, período, medio). La
/// elegida: `oscura` = texto sobre el color del texto (la de "qué mirar"),
/// si no el azul suave de selección (la del período) — como en los mocks.
class GrupoPildoras<T> extends StatelessWidget {
  const GrupoPildoras({
    super.key,
    required this.opciones,
    required this.elegida,
    required this.onElegir,
    this.oscura = false,
  });

  final List<(T, String)> opciones;
  final T elegida;
  final bool oscura;
  final void Function(T) onElegir;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colores.fondoBloque,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colores.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (valor, texto) in opciones)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Presionable(
                radio: 999,
                onTap: () => onElegir(valor),
                color: valor == elegida
                    ? (oscura ? colores.textoPrimario : colores.acento.withValues(alpha: 0.18))
                    : Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm + 2),
                  child: Text(
                    texto,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: valor == elegida && oscura ? colores.fondoBloque : colores.textoPrimario,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra partida en tramos de color proporcionales (Efectivo | Mercado Pago).
class BarraDividida extends StatelessWidget {
  const BarraDividida({super.key, required this.tramos, this.alto = 16});

  final List<({Color color, int valor})> tramos;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final conValor = tramos.where((t) => t.valor > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto / 2),
      child: SizedBox(
        height: alto,
        child: conValor.isEmpty
            ? ColoredBox(color: context.colores.fondo)
            : Row(
                children: [
                  for (var i = 0; i < conValor.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(flex: conValor[i].valor, child: ColoredBox(color: conValor[i].color, child: const SizedBox.expand())),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Fila de un ranking: nombre y cifra arriba, barrita proporcional abajo.
class FilaRanking extends StatelessWidget {
  const FilaRanking({super.key, required this.nombre, required this.valor, required this.proporcion});

  final String nombre;
  final String valor;

  /// 0 a 1, respecto del primero del ranking.
  final double proporcion;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Text(valor, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
          ],
        ),
        const SizedBox(height: Espaciado.xs + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: ColoredBox(
              color: colores.fondo,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: proporcion.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: ColoredBox(color: colores.acento),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cifra chica en caja de fondo suave, para las filas de cifras dentro de
/// un panel (Vendido / Ganancia / Stock de un proveedor).
class CajaCifra extends StatelessWidget {
  const CajaCifra({super.key, required this.etiqueta, required this.valor, this.tono});

  final String etiqueta;
  final String valor;
  final Tono? tono;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final t = tono == null ? null : _colores(context, tono!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
      decoration: BoxDecoration(
        color: t?.fondo ?? colores.fondo,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(fontWeight: Pesos.medium, color: t?.texto ?? colores.textoSecundario),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: textTheme.titleLarge?.copyWith(color: t?.texto).tabular),
          ),
        ],
      ),
    );
  }
}

/// Pastilla chica de un medio de pago (punto + nombre), para encabezados.
class FilaMedioCompacta extends StatelessWidget {
  const FilaMedioCompacta({super.key, required this.color, required this.etiqueta});

  final Color color;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.md, vertical: Espaciado.xs + 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PuntoColor(color: color, tamanio: 8),
          const SizedBox(width: Espaciado.sm),
          Text(
            etiqueta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Color.lerp(color, context.colores.textoPrimario, 0.35),
              fontWeight: Pesos.fuerte,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque de fondo suave adentro de una tarjeta o un modal, para agrupar lo
/// que va junto (el precio de un producto: costo, venta, margen).
class BloqueSuave extends StatelessWidget {
  const BloqueSuave({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(color: context.colores.fondo, borderRadius: BorderRadius.circular(radioSuperficieEscritorio - 4)),
      child: child,
    );
  }
}

/// "Bebidas del Lago" → "BL"; "Serra" → "SE".
String inicialesDe(String nombre) {
  final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty && p.toLowerCase() != 'de' && p.toLowerCase() != 'del').toList();
  if (palabras.isEmpty) return '?';
  if (palabras.length == 1) return palabras.first.substring(0, palabras.first.length < 2 ? 1 : 2).toUpperCase();
  return (palabras[0][0] + palabras[1][0]).toUpperCase();
}

/// Cuadradito con las iniciales del proveedor (o un ícono), como en el mock.
class AvatarIniciales extends StatelessWidget {
  const AvatarIniciales({super.key, required this.texto, this.icono, this.elegido = false, this.tamanio = 44});

  final String texto;
  final IconData? icono;
  final bool elegido;
  final double tamanio;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final fondo = elegido ? colores.acento : colores.acento.withValues(alpha: 0.12);
    final tinta = elegido ? colores.acentoTexto : colores.acento;
    return Container(
      width: tamanio,
      height: tamanio,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(tamanio * 0.28)),
      child: icono != null
          ? Icon(icono, color: tinta, size: tamanio * 0.5)
          : Text(
              texto,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tinta,
                fontWeight: Pesos.fuerte,
                fontSize: tamanio * 0.36,
              ),
            ),
    );
  }
}

/// Atajo de un toque para completar un campo ("$ 5.000", "Mitad", "Flete")
/// — mocks `Dialogos*` del "Lenguaje de diseño". Elegido: relleno de acento
/// suave; si no, blanco con borde.
class ChipAtajo extends StatelessWidget {
  const ChipAtajo({super.key, required this.texto, required this.onTap, this.elegido = false});

  final String texto;
  final VoidCallback onTap;
  final bool elegido;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: elegido ? Colors.transparent : colores.borde),
      ),
      child: Presionable(
        radio: 12,
        onTap: onTap,
        color: elegido ? colores.acento.withValues(alpha: 0.18) : colores.fondoBloque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm + 2),
          child: Text(texto, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: Pesos.medium)),
        ),
      ),
    );
  }
}
