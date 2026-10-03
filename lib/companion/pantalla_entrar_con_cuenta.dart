// Entrar al celular con la cuenta de cada persona (El dueño, 2026-10-02: "que los empleados directamente logueen con su
// perfil en lugar de seleccionar"). Reemplaza a la lista "¿Quién sos?": nadie elige un perfil en el celular, el perfil es el de
// la cuenta (`perfil_por_cuenta.dart`). Cambiar de perfil queda solo en el POS de escritorio.
//
// Pide internet una sola vez, al entrar; después el celular sigue andando sin conexión con el perfil ya guardado.

import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart';
import '../ui/tema/tokens.dart';
import 'base_local.dart';
import 'bienvenida/aparecer.dart';
import 'bienvenida/pantalla_listo.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'perfil_por_cuenta.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'sync_nube_companion.dart';
import 'tema/piezas_companion.dart';

/// El servicio contra el que se busca o crea el perfil: la PC si está emparejada y contesta, si no la base local (que se
/// sincroniza). Mismo criterio que el resto de la companion.
Future<ServicioCompanion> servicioParaPerfil() async {
  final conexion = await leerConexion();
  return conexion == null ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion())) : resolverServicioCompanion(conexion);
}

/// Para celulares que ya tenían la cuenta vinculada y un perfil elegido de la lista (de antes de este cambio): en segundo plano
/// y sin bloquear nada, vuelve a tomar el perfil de la cuenta. Sin internet, o ante cualquier falla, no toca nada: el celular
/// sigue con el perfil que tenía y la próxima vez que abra con conexión se corrige solo.
Future<void> reconciliarPerfilDeCuenta({SyncNubeCompanion? sync, Future<ServicioCompanion> Function()? servicio}) async {
  try {
    final s = sync ?? await syncNubeDelCelular();
    final cuenta = await s.cuenta();
    if (cuenta == null) return;
    final perfil = await s.cliente.yo(cuenta.token).timeout(const Duration(seconds: 6));
    await resolverPerfilDeCuenta(perfil: perfil, servicio: await (servicio ?? servicioParaPerfil)());
  } catch (_) {
    // silencioso a propósito
  }
}

class PantallaEntrarConCuenta extends StatefulWidget {
  const PantallaEntrarConCuenta({super.key, this.sync, this.servicio, this.alEntrar});

  /// Solo para tests: la sync del celular y el servicio. En la app real salen de `syncNubeDelCelular()` y de la conexión.
  final SyncNubeCompanion? sync;
  final Future<ServicioCompanion> Function()? servicio;

  /// Qué hacer con el perfil ya resuelto; por defecto muestra "Listo", que después abre el menú.
  final void Function(BuildContext context)? alEntrar;

  @override
  State<PantallaEntrarConCuenta> createState() => _PantallaEntrarConCuentaState();
}

class _PantallaEntrarConCuentaState extends State<PantallaEntrarConCuenta> {
  SyncNubeCompanion? _sync;
  bool _trabajando = true;
  String? _error;

  /// El token ya no vale (sacaron a la persona del negocio o revocaron el celular): hay que entrar de nuevo.
  bool _hayQueEntrarDeNuevo = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _sync = widget.sync ?? await syncNubeDelCelular();
      final cuenta = await _sync!.cuenta();
      if (cuenta != null) {
        await _resolver(cuenta);
        return;
      }
    } catch (e) {
      _error = mensajeDeError(e);
    }
    if (mounted) setState(() => _trabajando = false);
  }

  Future<void> _entrar() async {
    setState(() {
      _trabajando = true;
      _error = null;
      _hayQueEntrarDeNuevo = false;
    });
    try {
      final cuenta = await _sync!.vincular(nombre: nombreDelCelular());
      await _resolver(cuenta);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ErrorNube ? e.mensaje : mensajeDeError(e);
          _trabajando = false;
        });
      }
    }
  }

  Future<void> _resolver(CuentaVinculada cuenta) async {
    if (mounted) setState(() => _trabajando = true);
    try {
      final perfil = await _sync!.cliente.yo(cuenta.token);
      final servicio = await (widget.servicio ?? servicioParaPerfil)();
      await resolverPerfilDeCuenta(perfil: perfil, servicio: servicio);
      if (!mounted) return;
      if (widget.alEntrar != null) {
        widget.alEntrar!(context);
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PantallaListo()));
      }
    } on PerfilDesactivado catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _trabajando = false;
      });
    } on ErrorNube catch (e) {
      if (mounted) setState(() {
        _error = e.mensaje;
        _hayQueEntrarDeNuevo = e.pideVincularDeNuevo;
        _trabajando = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = mensajeDeError(e);
        _trabajando = false;
      });
    }
  }

  Future<void> _reintentar() async {
    final cuenta = await _sync!.cuenta();
    if (cuenta == null) {
      setState(() => _error = null);
      return;
    }
    await _resolver(cuenta);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Aparecer(
              orden: 0,
              child: EncabezadoCompanion(
                titulo: 'Entrá con tu cuenta',
                bajada: 'Tu perfil sale de tu cuenta de Nodo Sur: lo que hagas desde este celular queda a tu nombre.',
                padding: EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xxl + Espaciado.lg, Espaciado.xl, Espaciado.xl),
              ),
            ),
            Expanded(
              child: _trabajando
                  ? const Center(child: CircularProgressIndicator())
                  : Aparecer(
                      orden: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Text(_error!, key: const Key('entrar_error'), style: textTheme.bodyMedium?.copyWith(color: context.colores.error)),
                              const SizedBox(height: Espaciado.lg),
                            ],
                            // Con una cuenta ya vinculada y un error que no es de la sesión, se reintenta sin volver al navegador.
                            if (_error != null && !_hayQueEntrarDeNuevo && _sync != null)
                              OutlinedButton(key: const Key('entrar_reintentar'), onPressed: _reintentar, child: const Text('Reintentar')),
                            if (_error != null && !_hayQueEntrarDeNuevo) const SizedBox(height: Espaciado.sm),
                            FilledButton(key: const Key('entrar_con_cuenta'), onPressed: _entrar, child: const Text('Entrar con mi cuenta')),
                            const SizedBox(height: Espaciado.md),
                            Text(
                              'Se abre el navegador para que ingreses con tu cuenta de Google, una sola vez. Después el celular sigue funcionando sin internet.',
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
