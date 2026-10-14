// Cambiar de negocio sin cerrar la app (El dueño, 2026-10-14: "necesito que funcione íntegramente sin cerrarse").
//
// Antes la app se cerraba (`exit`) para que no quedara en memoria nada del negocio anterior. Ahora eso se hace a mano, en
// este orden, y la app sigue abierta:
//  1. Se desarma todo el árbol de pantallas y se muestra "Cambiando de negocio…": cada pantalla cancela lo suyo al cerrarse
//     (escuchas, temporizadores) y ya nadie toca nada.
//  2. Se frena todo lo que escribe (`frenarLoQueEscribe`): la sync (esperando la vuelta en curso), los avisos de Mercado
//     Pago, la escucha de la PC y el bot. La base queda cerrada y BLOQUEADA: algo que llegue tarde y la pida falla, en vez de
//     abrir una base vacía en el lugar de la activa.
//  3. Se olvida lo que quedó en memoria de la cuenta (`olvidarLoDeLaCuenta`).
//  4. Se trae el negocio elegido igual que al arrancar (`terminarCambioAlArrancar`, que vuelve a barrer el lugar hacia la
//     cuenta vieja antes de traer) y se lee su clave de la IA.
//  5. Se desbloquea la base y se arma la app de nuevo con otra `Key`: arranca como recién abierta.
//
// Una pieza nueva que guarde algo de la cuenta en memoria (una variable global, un `static`) tiene que olvidarse en
// [olvidarLoDeLaCuenta]. Ver `TRAMPAS.md`, "Cambiar de negocio sin cerrar la app".

import 'package:flutter/widgets.dart';

import '../domain/marca.dart';
import '../servicios/gemini.dart' show ClaveGemini;
import '../domain/modulos.dart' show ModulosNegocio;
import '../edicion.dart' show esEdicionServicios;
import '../servicios/marca_actual.dart';
import '../servicios/modulos_activos.dart' show modulosActuales;
import '../servicios/registro_errores.dart';
import '../servicios/turnos_bot_nube.dart' show turnosBotSinCargar;
import 'actualizacion.dart' show celularDePruebas;
import 'app_ns.dart' show sinConexionGlobalNs;
import 'base_local.dart';
import 'borrar_celular.dart' show frenarLoQueEscribe;
import 'bot_celular.dart' show olvidarBotDelCelular;
import 'configurar/negocio_nuevo.dart' show pasosPendientesNegocio;
import 'cuentas_del_celular.dart' show terminarCambioAlArrancar;
import 'kit/aviso_ns.dart' show quitarAvisoNs;

/// Lo que dibuja la raíz de la app (`RaizCompanion`): cada [generacion] es una app armada de cero.
@immutable
class EstadoRaizCompanion {
  const EstadoRaizCompanion({this.generacion = 0, this.cambiando = false, this.cambioTrabado});

  final int generacion;

  /// Se está cambiando de negocio: no hay ninguna pantalla de la app armada.
  final bool cambiando;

  /// El cambio no se pudo terminar (`PantallaCambioTrabado`).
  final Object? cambioTrabado;
}

final ValueNotifier<EstadoRaizCompanion> raizCompanion = ValueNotifier(const EstadoRaizCompanion());

/// Arma la app de cero con lo que haya en el lugar de la cuenta activa, sin cerrarla. Lo llaman los botones de cambiar de
/// negocio, "Volver a…" y "Cerrar sesión y borrar", después de guardar o descartar la cuenta de ahora. [terminar] y
/// [esperarCuadro] son para tests.
Future<void> volverAEmpezar({Future<Object?> Function()? terminar, Future<void> Function()? esperarCuadro}) async {
  final antes = raizCompanion.value;
  if (antes.cambiando) return;
  raizCompanion.value = EstadoRaizCompanion(generacion: antes.generacion, cambiando: true);
  quitarAvisoNs();
  // Un cuadro para que el árbol viejo se desarme del todo antes de frenar y mover nada.
  await (esperarCuadro ?? () => WidgetsBinding.instance.endOfFrame)();
  Object? trabado;
  try {
    // Ya lo hizo quien guardó la cuenta; de nuevo por lo que una pantalla pudo haber prendido al cerrarse.
    await frenarLoQueEscribe();
    olvidarLoDeLaCuenta();
    trabado = await (terminar ?? terminarCambioAlArrancar)();
    await ClaveGemini.cargar();
  } catch (e, st) {
    await registrarError('Volver a empezar la app', e, st);
    trabado = e;
  }
  // Con el cambio trabado la base sigue bloqueada: la pantalla del cambio trabado no la usa, y reintentar pasa de nuevo por acá.
  if (trabado == null) desbloquearBaseLocal();
  raizCompanion.value = EstadoRaizCompanion(generacion: antes.generacion + 1, cambioTrabado: trabado);
}

/// Suelta todo lo que la app guarda en memoria de la cuenta activa. Lo de cada pantalla se va con ella; esto es lo que vive
/// fuera de las pantallas.
void olvidarLoDeLaCuenta() {
  ClaveGemini.olvidarCuenta();
  olvidarBotDelCelular();
  marcaActual.value = const MarcaNegocio();
  sinConexionGlobalNs.value = false;
  pasosPendientesNegocio.value = const {};
  turnosBotSinCargar.value = const [];
  celularDePruebas.value = false;
  // Los módulos del negocio anterior: hasta que el nuevo lea su base, como al arrancar.
  modulosActuales.value = esEdicionServicios ? ModulosNegocio.todosActivos.paraEdicionServicios() : ModulosNegocio.todosActivos;
}
