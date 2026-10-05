// Tema propio de la companion — construido con la misma forma que
// `TemaPlazoleta` (`lib/ui/tema/tema.dart`, sin tocar) pero con valores
// completamente nuevos: otra escala tipográfica (más grande, más audaz),
// otro radio de control, botones más altos, sin ninguno de los límites de
// `DISENO.md` (un acento con tres usos exactos, radio único de 14, etc. —
// esas reglas siguen gobernando el escritorio, no esto). `CompanionApp` usa
// este tema en vez de `TemaPlazoleta`; el escritorio no importa este
// archivo, así que no hay forma de que esto se filtre para el otro lado.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import '../kit/tokens_ns.dart';
import 'colores_companion.dart';

/// Radio de "Superficie" — 28, tarjetas muy redondeadas como las de la web
/// de Nodo Sur (rediseño "antigravity").
const double radioSuperficieCompanion = 28;

/// Radio de controles rectangulares (campos, chips de ícono). Los botones son
/// píldoras (`StadiumBorder`), no usan este radio.
const double radioControlCompanion = 16;

abstract final class TemaCompanion {
  static ThemeData get oscuro => _construir(coloresCompanionOscuro, acentosCompanionOscuro, Brightness.dark);
  static ThemeData get claro => _construir(coloresCompanionClaro, acentosCompanionClaro, Brightness.light);

  static ThemeData _construir(ColoresPlazoleta colores, AcentosCompanion acentos, Brightness brillo) {
    final colorScheme = ColorScheme(
      brightness: brillo,
      primary: colores.acento,
      onPrimary: colores.acentoTexto,
      secondary: acentos.dinero,
      onSecondary: acentos.textoSobreColor,
      error: colores.error,
      onError: colores.errorTexto,
      surface: colores.fondo,
      onSurface: colores.textoPrimario,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colores.fondo,
      // Transición propia (El dueño, 2026-09-18: "una app moderna") — el zoom
      // de Android de fábrica es genérico, el mismo de cualquier app sin
      // tema. Entra deslizando desde abajo con fade, sale más rápido que
      // entra (Material Motion: "exit-faster-than-enter" se siente más
      // responsive).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _TransicionCompanion(),
          TargetPlatform.iOS: _TransicionCompanion(),
        },
      ),
      fontFamily: familiaTipografica,
      splashColor: colores.textoPrimario.withValues(alpha: 0.08),
      highlightColor: colores.textoPrimario.withValues(alpha: 0.04),
      hoverColor: colores.textoPrimario.withValues(alpha: 0.04),
    );

    final textTheme = _construirTextTheme(base.textTheme, colores);

    return base.copyWith(
      textTheme: textTheme,
      // También los acentos del escritorio: las piezas del kit compartido
      // (`lib/ui/comun/tarjetas.dart`, "Lenguaje de diseño" 2026-09-26) los
      // leen — mismos valores que `acentos`, ver `colores_companion.dart`.
      extensions: [
        colores,
        acentos,
        brillo == Brightness.dark ? acentosPlazoletaCompanionOscuro : acentosPlazoletaCompanionClaro,
        brillo == Brightness.dark ? TokensNs.oscuroTokens : TokensNs.claro,
      ],
      dividerTheme: DividerThemeData(color: colores.borde, thickness: Bordes.fino, space: Espaciado.lg),
      appBarTheme: AppBarTheme(
        backgroundColor: colores.fondo,
        foregroundColor: colores.textoPrimario,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colores.fondoBloque,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
      ),
      // Aviso flotante del mock (docs/01 §6.14): fondo `toast`, texto blanco
      // 15/600 centrado, radio 26, a 100 px del borde de abajo.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brillo == Brightness.dark ? TokensNs.oscuroTokens.toast : TokensNs.claro.toast,
        contentTextStyle: const TextStyle(fontFamily: familiaTipografica, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35, color: TokensNs.blanco),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        actionTextColor: TokensNs.blanco,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colores.fondoBloque,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
        textStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colores.fondoBloque,
        contentPadding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlCompanion),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlCompanion),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlCompanion),
          borderSide: BorderSide(color: colores.acento, width: 1.5),
        ),
        labelStyle: TextStyle(color: colores.textoSecundario),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          disabledBackgroundColor: colores.borde,
          disabledForegroundColor: colores.textoTenue,
          textStyle: const TextStyle(fontFamily: familiaTipografica, fontSize: 17, fontWeight: FontWeight.w600),
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          elevation: 0,
          textStyle: const TextStyle(fontFamily: familiaTipografica, fontSize: 17, fontWeight: FontWeight.w600),
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colores.textoPrimario,
          side: BorderSide(color: colores.borde, width: 1.5),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colores.acento,
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colores.acento,
        foregroundColor: colores.acentoTexto,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const StadiumBorder(),
        extendedTextStyle: const TextStyle(fontFamily: familiaTipografica, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colores.acento, circularTrackColor: colores.borde),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colores.fondo,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        ),
      ),
      iconTheme: IconThemeData(color: colores.textoSecundario),
      listTileTheme: ListTileThemeData(
        iconColor: colores.textoSecundario,
        textColor: colores.textoPrimario,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acentoTexto : colores.fondo,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acento : colores.textoTenue.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  static TextTheme _construirTextTheme(TextTheme base, ColoresPlazoleta colores) {
    TextStyle estilo(double tamanio, FontWeight peso, Color color, {double altura = 1.25, double apretado = 0}) => TextStyle(
          fontFamily: familiaTipografica,
          fontSize: tamanio,
          fontWeight: peso,
          color: color,
          height: altura,
          letterSpacing: tamanio * apretado,
        );

    // Titulares livianos y muy apretados (peso 400/500, -0,04 em), como la
    // web: la jerarquía la da el tamaño, no el negrita.
    return base.copyWith(
      displayLarge: estilo(52, FontWeight.w400, colores.textoPrimario, altura: 1.02, apretado: -0.05).tabular,
      headlineLarge: estilo(40, FontWeight.w400, colores.textoPrimario, altura: 1.05, apretado: -0.045).tabular,
      headlineMedium: estilo(34, FontWeight.w400, colores.textoPrimario, altura: 1.08, apretado: -0.045).tabular,
      titleLarge: estilo(24, FontWeight.w500, colores.textoPrimario, apretado: -0.03),
      titleMedium: estilo(19, FontWeight.w500, colores.textoPrimario, apretado: -0.02),
      titleSmall: estilo(16, FontWeight.w600, colores.textoPrimario, apretado: -0.01),
      bodyLarge: estilo(17, Pesos.regular, colores.textoPrimario, altura: 1.45),
      bodyMedium: estilo(16, Pesos.regular, colores.textoPrimario, altura: 1.45),
      bodySmall: estilo(14, Pesos.regular, colores.textoSecundario, altura: 1.4),
      labelLarge: estilo(16, FontWeight.w600, colores.textoPrimario),
      labelMedium: estilo(13, FontWeight.w500, colores.textoSecundario),
      labelSmall: estilo(12, FontWeight.w500, colores.textoTenue),
    );
  }
}

/// Altura de cualquier botón/control principal — más alto que el del
/// escritorio (48): "flat mobile" pide controles grandes, cómodos con el
/// pulgar, no compartidos con la densidad de un mostrador con mouse.
const double alturaControlCompanion = 56;

/// Entrada de pantalla del mock (`.scr`, 0,55 s): fade y subida de 14 px con
/// la curva `cubic-bezier(.2,.7,.1,1)`. Al salir solo se desvanece.
class _TransicionCompanion extends PageTransitionsBuilder {
  const _TransicionCompanion();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final t = CurvedAnimation(parent: animation, curve: const Cubic(.2, .7, .1, 1));
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 14 / 844), end: Offset.zero).animate(t),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(parent: secondaryAnimation, curve: const Interval(0, 0.4))),
          child: child,
        ),
      ),
    );
  }
}
