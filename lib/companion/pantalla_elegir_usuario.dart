// "¿Quién sos?" — mismo criterio que abrir caja en la pantalla de venta: no
// hay login real, se elige de una lista de usuarios, para que los ajustes de
// stock/gastos que se carguen desde el celular queden atribuidos a la
// persona correcta.
//
// La lista sale de la PC en vivo si hay una emparejada y responde, y si no
// (nunca se emparejó, o no contesta) de la base local sincronizada por
// Supabase (`usuarios` entró a la sincronización en la migración v31→v32,
// El dueño 2026-09-18: "no debería tener que escanear ya, es innecesario") —
// mismo patrón de `resolverServicioCompanion` que ya usa el resto de la
// companion, nunca se queda esperando una PC que no existe.

import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'pantalla_menu_companion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'tema/chip_icono.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';

class PantallaElegirUsuario extends StatefulWidget {
  const PantallaElegirUsuario({super.key});

  @override
  State<PantallaElegirUsuario> createState() => _PantallaElegirUsuarioState();
}

class _PantallaElegirUsuarioState extends State<PantallaElegirUsuario> {
  List<UsuarioCompanion>? _usuarios;
  String? _error;

  /// El dueño, 2026-09-19: "la pantalla de seleccionar perfil no se refresca
  /// una vez trae los datos" — en una companion recién instalada, `usuarios`
  /// puede tardar el mismo puñado de segundos que cualquier otra tabla en
  /// llegar por sync; sin esto, la lista se quedaba vacía para siempre en
  /// vez de completarse sola apenas el pull trae la fila.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    _cargar();
    _subCambiosSync = avisosCambiosCompanion.listen((_) => _cargar());
  }

  @override
  void dispose() {
    _subCambiosSync?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final conexion = await leerConexion();
      final servicio = conexion == null
          ? PuertoLocal(baseLocalCompanion())
          : await resolverServicioCompanion(conexion);
      final usuarios = await servicio.usuarios();
      if (mounted) setState(() => _usuarios = usuarios);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo cargar la lista de usuarios: ${mensajeDeError(e)}',
        );
      }
    }
  }

  Future<void> _elegir(UsuarioCompanion u) async {
    await guardarUsuario(u);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PantallaMenuCompanion()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('¿Quién sos?')),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Espaciado.lg),
                  child: Text(_error!),
                ),
              )
            : _usuarios == null
            ? const EsqueletoLista()
            : ListView.builder(
                padding: const EdgeInsets.all(Espaciado.lg),
                itemCount: _usuarios!.length,
                itemBuilder: (context, i) {
                  final u = _usuarios![i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: Superficie(
                      padding: EdgeInsets.zero,
                      child: Presionable(
                        onTap: () => _elegir(u),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Espaciado.lg,
                            vertical: Espaciado.md,
                          ),
                          child: Row(
                            children: [
                              ChipIcono(icono: IconosPlazoleta.personOutline, color: context.colores.acento),
                              const SizedBox(width: Espaciado.md),
                              Expanded(
                                child: Text(
                                  u.nombre,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Icon(
                                IconosPlazoleta.chevronRight,
                                color: context.colores.textoTenue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
