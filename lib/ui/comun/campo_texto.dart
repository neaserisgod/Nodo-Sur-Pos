// Un solo estilo de campo de texto para toda la app. Etiqueta FIJA arriba —
// nunca la flotante de Material (corrección post-aprobación del kit, el dueño):
// share el mismo mecanismo con el borde que la etiqueta flotante corre según
// el `textAlign` del campo (ver historia vieja de este archivo), y una
// etiqueta que se mueve según lo que se tipeó es, de por sí, más ruido del
// necesario para un campo de formulario.
//
// El campo en sí necesita fondo propio para parecer un campo (no un texto de
// lectura): `colores.fondo`, un paso contra el `Bloque` que lo contiene —
// mismo criterio que ya usan los botones de medio de pago sin seleccionar en
// la pantalla de venta (`columna_cobro.dart`). Altura fija
// `Medidas.alturaControl`, igual que cualquier otro control de la app. El
// borde de foco (`colores.acento`) ya sale del tema global
// (`TemaPlazoleta.inputDecorationTheme`) — acá solo se pisa el color de
// fondo, todo lo demás se hereda.
//
// `CampoPlata` es la variante para centavos: alineada a la derecha, cifras
// tabulares, igual que cualquier otro monto de la app. Con la etiqueta fija
// (no flotante) esto ya no arrastra ningún corrimiento — el `textAlign` solo
// afecta al texto editado. Sigue sin hacer el parseo — `parsearARS` (Regla 1)
// es responsabilidad de quien llama, igual que ya lo era en los diálogos
// existentes.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';

class CampoTexto extends StatelessWidget {
  const CampoTexto({
    super.key,
    required this.controller,
    this.etiqueta,
    this.autofocus = false,
    this.obscureText = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.pista,
    this.sobreElFondo = false,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? etiqueta;

  /// Qué hace la tecla de acción del teclado del celular. En un formulario de
  /// varios campos, "next" en todos menos el último pasa al campo siguiente en
  /// vez de cerrar el teclado. Null = el de siempre.
  final TextInputAction? textInputAction;

  /// Más de una línea (ej. el encabezado del ticket: una línea por renglón). Por defecto, una sola.
  final int maxLines;
  final int? minLines;

  /// Texto gris adentro del campo vacío ("Buscar N° de venta o producto").
  final String? pista;

  /// El campo está directo sobre el canvas de la pantalla, no adentro de
  /// una tarjeta: se rellena con el blanco de tarjeta — con el relleno de
  /// siempre (el color del canvas) no se vería dónde empieza.
  final bool sobreElFondo;
  final bool autofocus;

  /// Para tokens/credenciales (ej. el access token de Mercado Pago en
  /// Impresión) — nunca se muestran en pantalla mientras se escriben.
  final bool obscureText;

  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Opcionales — ninguna pantalla del escritorio los usa hoy (por eso
  /// default null no les cambia nada), pero un buscador (companion,
  /// 2026-09-10) necesita el ícono de lupa y un spinner de "cargando" sin
  /// volver a un `TextField` crudo.
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  /// Null = el default de `TextField` (teclado de texto). Para plata usar
  /// `CampoPlata`, no esto — este es para enteros sueltos sin formato de
  /// moneda (ej. stock inicial, companion, 2026-09-17).
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return _CampoConEtiqueta(
      etiqueta: etiqueta,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType ?? (maxLines == 1 ? null : TextInputType.multiline),
        textInputAction: textInputAction,
        maxLines: obscureText ? 1 : maxLines,
        minLines: obscureText ? null : minLines,
        decoration: InputDecoration(
          fillColor: sobreElFondo ? context.colores.fondoBloque : context.colores.fondo,
          hintText: pista,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class CampoPlata extends StatelessWidget {
  const CampoPlata({
    super.key,
    required this.controller,
    this.etiqueta,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.sobreElFondo = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? etiqueta;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Ver `CampoTexto.textInputAction`.
  final TextInputAction? textInputAction;

  /// Mismo criterio que `CampoTexto.sobreElFondo`: sobre el color del
  /// canvas (o un `BloqueSuave`) se rellena con el blanco de tarjeta.
  final bool sobreElFondo;

  @override
  Widget build(BuildContext context) {
    return _CampoConEtiqueta(
      etiqueta: etiqueta,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        // `.number` a secas no ofrece el separador decimal en el teclado de
        // Android (no se nota en el escritorio, con teclado físico, pero
        // vuelve la carga de precios "a los pedales" desde el celular:
        // El dueño, 2026-09-07, alta de productos por companion) — con
        // `decimal: true` el teclado numérico incluye la coma/punto.
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        textInputAction: textInputAction,
        style: Theme.of(context).textTheme.bodyMedium?.tabular,
        decoration: InputDecoration(fillColor: sobreElFondo ? context.colores.fondoBloque : context.colores.fondo),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class _CampoConEtiqueta extends StatelessWidget {
  const _CampoConEtiqueta({required this.etiqueta, required this.child});

  final String? etiqueta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (etiqueta != null) ...[
          Text(etiqueta!, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Espaciado.xs),
        ],
        SizedBox(height: Medidas.alturaControl, child: child),
      ],
    );
  }
}
