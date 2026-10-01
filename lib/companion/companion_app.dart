// Raíz de la companion app Android — sin base de datos propia, sin
// servidor: arranca leyendo si ya hay un usuario elegido
// (`emparejamiento.dart`) y entra directo al menú. Emparejar con una PC por
// LAN ya no es parte de este arranque (ver comentario en `_decidir`).

import 'package:flutter/material.dart';

import '../data/identidad_sync.dart';
import 'emparejamiento.dart';
import 'flujo_modo_uso.dart';
import 'modo_uso.dart';
import 'identidad_dispositivo.dart';
import 'pantalla_elegir_usuario.dart';
import 'pantalla_menu_companion.dart';
import 'tema/tema_companion.dart';
import '../servicios/marca_actual.dart';

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_) => '${marcaActual.value.nombre} — Companion',
      debugShowCheckedModeBanner: false,
      theme: TemaCompanion.claro,
      darkTheme: TemaCompanion.oscuro,
      home: const _PantallaInicial(),
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
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => modo == null
            ? pantallaDeElegirModoInicial()
            : usuario == null
            ? const PantallaElegirUsuario()
            : const PantallaMenuCompanion(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
