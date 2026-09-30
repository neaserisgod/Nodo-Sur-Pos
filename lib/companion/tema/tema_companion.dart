// Tema propio de la companion — construido con la misma forma que
// `TemaPlazoleta` (`lib/ui/tema/tema.dart`, sin tocar) pero con valores
// completamente nuevos: otra escala tipográfica (más grande, más audaz),
// otro radio de control, botones más altos, sin ninguno de los límites de
// `DISENO.md` (un acento con tres usos exactos, radio único de 14, etc. —
// esas reglas siguen gobernando el escritorio, no esto). `CompanionApp` usa
// este tema en vez de `TemaPlazoleta`; el escritorio no importa este
// archivo, así que no hay forma de que esto se filtre para el otro lado.

import 'package:flutter/material.dart';

import '../../ui/tema/acentos.dart' show acentosEscritorioClaro, acentosEscritorioOscuro;
import '../../ui/tema/tokens.dart';
import 'colores_companion.dart';

/// Radio de "Superficie" — 20, el de las tarjetas de los mocks de
/// "Lenguaje de diseño" (2026-09-26). Mismo valor que
/// `radioSuperficieEscritorio`.
const double radioSuperficieCompanion = 20;

/// Radio de controles rectangulares (campos, chips de ícono) — mismo valor
/// que `radioControlEscritorio`.
const double radioControlCompanion = 14;

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
      splashColor: colores.acento.withValues(alpha: 0.16),
      highlightColor: colores.acento.withValues(alpha: 0.08),
      hoverColor: colores.textoPrimario.withValues(alpha: 0.04),
    );

    final textTheme = _construirTextTheme(base.textTheme, colores);

    return base.copyWith(
      textTheme: textTheme,
      // También los acentos del escritorio: las piezas del kit compartido
      // (`lib/ui/comun/tarjetas.dart`, "Lenguaje de diseño" 2026-09-26) los
      // leen — mismos valores que `acentos`, ver `colores_companion.dart`.
      extensions: [colores, acentos, brillo == Brightness.dark ? acentosEscritorioOscuro : acentosEscritorioClaro],
      dividerTheme: DividerThemeData(color: colores.borde, thickness: Bordes.fino, space: EspacioCompanion.lg),
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
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colores.textoPrimario,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colores.fondo),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colores.fondoBloque,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
        textStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colores.fondo,
        contentPadding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.lg, vertical: EspacioCompanion.md),
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
          borderSide: BorderSide(color: colores.acento, width: 2),
        ),
        labelStyle: TextStyle(color: colores.textoSecundario),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          disabledBackgroundColor: colores.borde,
          disabledForegroundColor: colores.textoTenue,
          textStyle: TextStyle(fontFamily: familiaTipografica, fontSize: 17, fontWeight: Pesos.medium),
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
          padding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          elevation: 0,
          textStyle: TextStyle(fontFamily: familiaTipografica, fontSize: 17, fontWeight: Pesos.medium),
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
          padding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.lg),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colores.textoPrimario,
          side: BorderSide(color: colores.borde, width: 1.5),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(alturaControlCompanion),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlCompanion)),
          padding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.lg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colores.acento,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconTheme: IconThemeData(color: colores.textoSecundario),
      listTileTheme: ListTileThemeData(
        iconColor: colores.textoSecundario,
        textColor: colores.textoPrimario,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acento : colores.textoTenue,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acento.withValues(alpha: 0.4) : colores.borde,
        ),
      ),
    );
  }

  static TextTheme _construirTextTheme(TextTheme base, ColoresPlazoleta colores) {
    TextStyle estilo(double tamanio, FontWeight peso, Color color, {double altura = 1.25}) => TextStyle(
          fontFamily: familiaTipografica,
          fontSize: tamanio,
          fontWeight: peso,
          color: color,
          height: altura,
        );

    // Escala propia, bien diferenciada de la del escritorio: más salto entre
    // roles, y Bold (único peso "fuerte" que trae la fuente empaquetada) en
    // más lugares — look "flat mobile" audaz en vez del bento discreto.
    return base.copyWith(
      displayLarge: estilo(44, Pesos.medium, colores.textoPrimario, altura: 1.1).tabular,
      headlineMedium: estilo(32, Pesos.medium, colores.textoPrimario, altura: 1.1).tabular,
      titleLarge: estilo(22, Pesos.medium, colores.textoPrimario),
      titleMedium: estilo(18, Pesos.medium, colores.textoPrimario),
      titleSmall: estilo(16, Pesos.medium, colores.textoPrimario),
      bodyLarge: estilo(17, Pesos.regular, colores.textoPrimario),
      bodyMedium: estilo(16, Pesos.regular, colores.textoPrimario),
      bodySmall: estilo(14, Pesos.regular, colores.textoSecundario),
      labelLarge: estilo(16, Pesos.medium, colores.textoPrimario),
      labelMedium: estilo(13, Pesos.regular, colores.textoSecundario),
      labelSmall: estilo(12, Pesos.regular, colores.textoTenue),
    );
  }
}

/// Escala de espaciado propia — mismos valores base (múltiplos de 4) que el
/// escritorio porque siguen siendo el criterio correcto para este estilo
/// (la propia guía "flat mobile touch-first" recomienda 4/8/16/24/32/48),
/// no porque se reuse el token del escritorio: `EspaciadoCompanion` es un
/// tipo propio, así que un cambio futuro de uno nunca mueve al otro.
abstract final class EspacioCompanion {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Altura de cualquier botón/control principal — más alto que el del
/// escritorio (48): "flat mobile" pide controles grandes, cómodos con el
/// pulgar, no compartidos con la densidad de un mostrador con mouse.
const double alturaControlCompanion = 56;

/// Desliza desde abajo con fade al entrar, sale con fade solo (más corto)
/// al volver — reemplaza el zoom de Material por defecto.
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
    final entrando = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: const Interval(0, 0.7)),
      child: SlideTransition(
        position: entrando,
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(
            CurvedAnimation(parent: secondaryAnimation, curve: const Interval(0, 0.4)),
          ),
          child: child,
        ),
      ),
    );
  }
}
