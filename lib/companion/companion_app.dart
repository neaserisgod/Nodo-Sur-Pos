// Raíz de la companion app Android — sin base de datos propia, sin
// servidor: arranca leyendo si ya hay un usuario elegido
// (`emparejamiento.dart`) y entra directo al menú. Emparejar con una PC por
// LAN ya no es parte de este arranque (ver comentario en `_decidir`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import '../data/identidad_sync.dart';
import 'emparejamiento.dart';
import 'app_ns.dart';
import 'bienvenida/marca_nodo_sur.dart';
import 'kit/kit_ns.dart';
import 'flujo_modo_uso.dart';
import 'modo_uso.dart';
import 'identidad_dispositivo.dart';
import 'pantalla_entrar_con_cuenta.dart';
import 'pantalla_menu_companion.dart';
import 'tema/tema_companion.dart';
import '../servicios/marca_actual.dart';

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: modoTemaNs,
      builder: (context, modo, _) => MaterialApp(
        onGenerateTitle: (_) => '${marcaActual.value.nombre} — Companion',
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'AR'),
        supportedLocales: const [Locale('es', 'AR'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: modo,
        // Íconos de la barra de estado claros u oscuros según el tema, y el cartel
        // "Sin conexión con la PC" arriba de todas las pantallas (docs/01 §6.15):
        // mientras se ve, todo baja 34 px.
        builder: (context, navegador) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: ValueListenableBuilder<bool>(
            valueListenable: sinConexionGlobalNs,
            builder: (context, sinConexion, _) {
              if (!sinConexion) return PuenteAppNs(child: navegador!);
              final arriba = MediaQuery.paddingOf(context).top;
              return Column(
                children: [
                  Container(
                    color: context.ns.wbg,
                    height: CartelSinConexionNs.alto + arriba,
                    padding: EdgeInsets.only(top: arriba),
                    child: const CartelSinConexionNs(),
                  ),
                  Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: PuenteAppNs(child: navegador!))),
                ],
              );
            },
          ),
        ),
        home: const _PantallaInicial(),
      ),
    );
  }
}

class _PantallaInicial extends StatefulWidget {
  const _PantallaInicial();

  @override
  State<_PantallaInicial> createState() => _PantallaInicialState();
}

class _PantallaInicialState extends State<_PantallaInicial> {
  @override
  void initState() {
    super.initState();
    cargarModoTemaNs();
    _decidir();
  }

  Future<void> _decidir() async {
    // Se fija una sola vez por arranque, antes de cualquier pantalla — hoy
    // no hay ninguna escritura local todavía (fase 1 del rediseño de
    // sincronización, sin `PuertoLocal` en producción), pero cuando la haya
    // (fase 3) tiene que estar listo desde el primer frame.
    establecerIdDispositivo(await idDispositivoEstable());
    // Emparejar con una PC por LAN ya NO es un paso obligatorio de arranque
    // (El dueño, 2026-09-18: "no debería tener que escanear ya, es
    // innecesario" — justo el objetivo de esta fase era que la companion
    // funcione como un POS aparte, sin depender de la PC). No hay login: se
    // entra directo a elegir usuario / al menú, y
    // `PantallaMenuCompanion` ya tolera sin problema no tener `conexion`
    // (`_iniciarConexion` se queda con `_cliente`/`_servicio` en null).
    // Emparejar sigue disponible a pedido desde Gestión → "Desconectar de
    // esta PC" (mismo botón sirve para conectar si todavía no hay nada que
    // desconectar).
    final usuario = await leerUsuario();
    final conexion = await leerConexion();
    final guardado = await leerModoUso();
    final modo = resolverModoUso(guardado: guardado, tieneConexion: conexion != null, tieneUsuario: usuario != null);
    // Instalaciones anteriores a la pantalla de elegir modo: se les asigna el que ya venían usando.
    if (modo != null && guardado == null) await guardarModoUso(modo);
    // Con perfil ya guardado el arranque no espera a la red; si hay cuenta vinculada, el perfil se corrige solo por detrás.
    if (usuario != null) unawaited(reconciliarPerfilDeCuenta());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => modo == null
            ? pantallaDeBienvenidaInicial()
            : usuario == null
            ? const PantallaEntrarConCuenta()
            : const PantallaMenuCompanion(),
      ),
    );
  }

  // Leer lo guardado tarda un instante: se ve el logo, que es con lo que arranca la bienvenida.
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: MarcaNodoSur(tamanio: 64)));
}
