// Entrar al celular con la cuenta de cada persona (El dueño, 2026-10-02: "que los empleados directamente logueen con su
// perfil en lugar de seleccionar"). Reemplaza a la lista "¿Quién sos?": nadie elige un perfil en el celular, el perfil es el de
// la cuenta (`perfil_por_cuenta.dart`). Cambiar de perfil queda solo en el POS de escritorio.
//
// Pide internet una sola vez, al entrar; después el celular sigue andando sin conexión con el perfil ya guardado.
//
// En el celular se entra con el selector de cuentas de Google del teléfono, sin navegador (El dueño, 2026-10-13). Si eso no
// anda (un teléfono sin servicios de Google, la app sin registrar en Google Cloud, o la persona cierra el selector), aparece
// "Entrar con el navegador", el camino de antes. En la versión web se entra siempre por el sitio, en la misma pestaña.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart';
import '../domain/cuentas_del_celular.dart';
import 'base_local.dart';
import 'bienvenida/pantalla_listo.dart';
import 'bienvenida/vista_entrar_con_google.dart';
import 'borrar_celular.dart';
import 'configurar/asistente_negocio.dart';
import 'configurar/flujo_negocio.dart';
import 'configurar/negocio_nuevo.dart';
import 'cuentas_del_celular.dart';
import 'elegir_sucursal.dart';
import 'google_en_celular.dart';
import 'kit/kit_ns.dart';
import 'modo_uso.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'perfil_por_cuenta.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'sync_nube_companion.dart';

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
    await guardarNegocioDeEstaCuenta(perfil);
    await resolverPerfilDeCuenta(perfil: perfil, servicio: await (servicio ?? servicioParaPerfil)());
  } catch (_) {
    // silencioso a propósito
  }
}

class PantallaEntrarConCuenta extends StatefulWidget {
  const PantallaEntrarConCuenta({
    super.key,
    this.sync,
    this.servicio,
    this.alEntrar,
    this.esNegocioNuevo,
    this.leerCuentas,
    this.irACuentaGuardada,
  });

  /// Solo para tests: la sync del celular y el servicio. En la app real salen de `syncNubeDelCelular()` y de la conexión.
  final SyncNubeCompanion? sync;
  final Future<ServicioCompanion> Function()? servicio;

  /// Qué hacer con el perfil ya resuelto; por defecto muestra "Listo", que después abre el menú (o "Configurá tu
  /// negocio", si es el dueño de un negocio nuevo).
  final void Function(BuildContext context)? alEntrar;

  /// Solo para tests: si quien entró es el dueño de un negocio nuevo. En la app real, [_esNegocioNuevo].
  final Future<bool> Function(PerfilDeCuenta perfil)? esNegocioNuevo;

  /// Solo para tests: las cuentas del celular (`cuentas_del_celular.dart`) y qué hacer para ir a una guardada (en la app real,
  /// se descarta lo de este lugar, se trae esa y se cierra la app).
  final Future<IndiceCuentas> Function()? leerCuentas;
  final Future<void> Function(String id)? irACuentaGuardada;

  @override
  State<PantallaEntrarConCuenta> createState() => _PantallaEntrarConCuentaState();
}

class _PantallaEntrarConCuentaState extends State<PantallaEntrarConCuenta> {
  SyncNubeCompanion? _sync;
  bool _trabajando = true;
  String? _error;

  /// El token ya no vale (sacaron a la persona del negocio o revocaron el celular): hay que entrar de nuevo.
  bool _hayQueEntrarDeNuevo = false;

  /// Entrar con Google desde la app no anduvo (o se cerró el selector): se ofrece el navegador.
  bool _ofrecerNavegador = false;

  /// Las cuentas guardadas en el celular (null en la web, que no tiene varias).
  IndiceCuentas? _cuentas;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      // Las otras cuentas se leen aparte, sin frenar el arranque.
      unawaited(_leerCuentasDelCelular().then((c) {
        if (mounted) setState(() => _cuentas = c);
      }));
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

  Future<IndiceCuentas?> _leerCuentasDelCelular() async {
    if (widget.leerCuentas != null) return widget.leerCuentas!();
    if (kIsWeb) return null;
    try {
      return await leerIndiceCuentas();
    } catch (_) {
      return null;
    }
  }

  /// Se tocó "Agregar otra cuenta" (no hay activa) y hay otra guardada: la salida para volver a ella.
  CuentaDelCelular? get _paraVolver => _cuentas?.activa == null ? _cuentas?.guardadas.firstOrNull : null;

  /// Descarta lo de este lugar (todavía no hay cuenta, o es una repetida) y trae la guardada [id].
  Future<void> _irACuentaGuardada(String id) async {
    setState(() => _trabajando = true);
    if (widget.irACuentaGuardada != null) return widget.irACuentaGuardada!(id);
    await borrarTodoDelCelular(null, id);
    await cerrarLaApp();
  }

  /// Agregando otro negocio al celular: no hay cuenta activa y hay alguna guardada.
  bool get _agregando => _cuentas?.activa == null && (_cuentas?.guardadas.isNotEmpty ?? false);

  /// Entró en un negocio y sucursal que ya están guardados en este celular con el mismo mail: tenerlos dos veces sería tener
  /// dos copias de lo mismo. Se ofrece ir al guardado (con todo lo suyo) o elegir otro. Devuelve si se encargó (no hay que
  /// seguir). El mismo mail en otro negocio no es repetido: es justamente para eso (2026-10-13).
  Future<bool> _yaEstaGuardada(PerfilDeCuenta perfil) async {
    final id = _cuentas == null ? null : cuentaRepetida(_cuentas!, email: perfil.email, negocio: perfil.negocio, sucursal: perfil.sucursal);
    if (id == null || !mounted) return false;
    final guardada = _cuentas!.guardadas.firstWhere((c) => c.id == id);
    final ir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '${guardada.titulo} ya está en este celular',
        texto: 'Ya está guardado acá con ${perfil.email}, con todo lo suyo. Para no tenerlo dos veces, se usa ese. '
            'La app se cierra: abrila de nuevo para seguir ahí.',
        botones: [
          BotonNs.primario(ctx, 'Ir a ${guardada.titulo}', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Entrar en otro negocio', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (ir == true) {
      await _irACuentaGuardada(id);
    } else {
      await _sync!.desvincular();
      if (mounted) setState(() => _trabajando = false);
    }
    return true;
  }

  Future<void> _entrar() async {
    if (kIsWeb) return _entrarConNavegador();
    setState(() {
      _trabajando = true;
      _error = null;
      _hayQueEntrarDeNuevo = false;
    });
    try {
      final cuenta = await _sync!.entrarConGoogle(
        nombre: nombreDelCelular(),
        elegir: (opciones) async => mounted ? elegirNegocio(context, opciones) : null,
        elegirSiempre: _agregando,
      );
      if (cuenta == null) {
        // Cerró el selector sin elegir. Con la app mal registrada en Google, el selector también "se cancela" solo: por eso
        // queda a mano el navegador.
        if (mounted) {
          setState(() {
            _trabajando = false;
            _ofrecerNavegador = true;
          });
        }
        return;
      }
      await _resolver(cuenta);
    } on GoogleNoDisponible {
      if (mounted) {
        setState(() {
          _error = 'No se pudo entrar con Google desde la app. Probá con el navegador.';
          _trabajando = false;
          _ofrecerNavegador = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ErrorNube ? e.mensaje : mensajeDeError(e);
          _trabajando = false;
        });
      }
    }
  }

  /// El camino de antes: se abre la página /vincular/ del sitio y vuelve con el código.
  Future<void> _entrarConNavegador() async {
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
      if (await _yaEstaGuardada(perfil)) return;
      // Cómo se llama este negocio, para la lista de cuentas del celular (`cuentas_del_celular.dart`).
      await guardarNegocioDeEstaCuenta(perfil);
      // Un equipo nuevo en "Solo celular" (otro celular, o el navegador) baja primero lo que ya está en la nube: el perfil se busca
      // por nombre, y con la base todavía vacía se creaba otra persona con el mismo nombre (revisión 2026-10-12, "Caro" tres veces
      // en la Agenda). Sin red sigue igual que antes.
      if (await leerModoUso() == ModoUso.soloCelular) await sincronizarUnaVez(_sync!.servicio);
      final servicio = await (widget.servicio ?? servicioParaPerfil)();
      await resolverPerfilDeCuenta(perfil: perfil, servicio: servicio);
      if (!mounted) return;
      if (widget.alEntrar != null) {
        widget.alEntrar!(context);
        return;
      }
      final nuevo = await (widget.esNegocioNuevo ?? _esNegocioNuevo)(perfil);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => nuevo
              ? PantallaListo(textoBoton: 'Configurar mi negocio', alSeguir: (context) => abrirAsistenteNegocio(context))
              : const PantallaListo(),
        ),
      );
    } on PerfilDesactivado catch (e) {
      if (mounted) {
        setState(() {
        _error = e.toString();
        _trabajando = false;
      });
      }
    } on ErrorNube catch (e) {
      if (mounted) {
        setState(() {
        _error = e.mensaje;
        _hayQueEntrarDeNuevo = e.pideVincularDeNuevo;
        _trabajando = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _error = mensajeDeError(e);
        _trabajando = false;
      });
      }
    }
  }

  /// El dueño de un negocio que todavía no tiene nada, usando solo el celular: le toca "Configurá tu negocio". Con la
  /// PC, la configuración vive allá; un empleado o encargado entra a un negocio que ya armó el dueño.
  Future<bool> _esNegocioNuevo(PerfilDeCuenta perfil) async {
    if (perfil.rol != rolDuenio) return false;
    if (await leerModoUso() != ModoUso.soloCelular) return false;
    final db = baseLocalCompanion();
    if (!await esNegocioNuevoTrasSincronizar(sync: _sync!.servicio, db: db)) return false;
    await prepararNegocioNuevo(db);
    await guardarPasosPendientes(PasoNegocio.values.toSet());
    return true;
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
  Widget build(BuildContext context) => VistaEntrarConGoogle(
        alEntrar: _entrar,
        trabajando: _trabajando,
        error: _error,
        // Con una cuenta ya vinculada y un error que no es de la sesión, se reintenta sin volver al navegador.
        alReintentar: _error != null && !_hayQueEntrarDeNuevo && _sync != null ? _reintentar : null,
        alEntrarConNavegador: _ofrecerNavegador && _sync != null ? _entrarConNavegador : null,
        volverACuenta: switch (_paraVolver) {
          final c? => (titulo: c.titulo, alTocar: () => _irACuentaGuardada(c.id)),
          null => null,
        },
      );
}
