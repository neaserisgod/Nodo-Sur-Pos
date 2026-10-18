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
import '../servicios/registro_errores.dart';
import '../domain/cuentas_del_celular.dart';
import 'base_local.dart';
import 'bienvenida/vista_entrar_con_google.dart';
import 'borrar_celular.dart';
import 'reinicio_companion.dart';
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
import 'pantalla_menu_companion.dart';
import 'perfil_por_cuenta.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'sync_nube_companion.dart';
import '../edicion.dart';

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
    if (!kIsWeb) await anotarCuentaActiva(perfil: perfil);
    await resolverPerfilDeCuenta(perfil: perfil, servicio: await (servicio ?? servicioParaPerfil)());
  } catch (_) {
    // silencioso a propósito
  }
}

/// El nombre que el dueño le puso al comercio, también para su negocio en el sitio: uno nuevo nace "Negocio de (nombre de
/// Google)", y ese nombre quedaba para siempre en la lista de negocios del celular, en horsepos.com/negocio y en el cobro
/// (2026-10-14). Sin cuenta, sin red o sin ser el dueño (el sitio contesta 403), no pasa nada: el nombre ya quedó en la base.
Future<void> avisarNombreDelNegocio(String nombre, {SyncNubeCompanion? sync}) async {
  try {
    final s = sync ?? await syncNubeDelCelular();
    final cuenta = await s.cuenta();
    if (cuenta == null || nombre.trim().isEmpty) return;
    await s.cliente.renombrarNegocio(cuenta.token, nombre.trim());
    // Que la lista de negocios del celular ya lo muestre con el nombre nuevo.
    await reconciliarPerfilDeCuenta(sync: s);
  } on ErrorNube catch (e) {
    if (e.estado == 403) return; // un empleado o un encargado: el nombre lo decide el dueño
    unawaited(registrarSiNoEsDeRed('Avisar el nombre del negocio', e));
  } catch (e, st) {
    unawaited(registrarSiNoEsDeRed('Avisar el nombre del negocio', e, st));
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

  /// Qué hacer con el perfil ya resuelto; por defecto abre el menú, o "Configurá tu negocio" si es el dueño de un negocio
  /// nuevo. Sin pantalla de "Listo" en el medio (El dueño, 2026-10-18: "tarda demasiado"): un toque menos.
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

  /// Qué está haciendo mientras trabaja: entrar puede tardar (bajar los datos del negocio), y el botón lo dice.
  String? _etapa;

  /// La vuelta de la sync que se hizo al entrar terminó bien: para saber si el negocio es nuevo no hace falta otra.
  bool _sincronizado = false;

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
  CuentaDelCelular? get _paraVolver => _agregando ? _cuentas!.guardadas.first : null;

  /// Descarta lo de este lugar (todavía no hay cuenta, o es una repetida) y trae la guardada [id].
  Future<void> _irACuentaGuardada(String id) async {
    setState(() => _trabajando = true);
    if (widget.irACuentaGuardada != null) return widget.irACuentaGuardada!(id);
    // Esto DESCARTA lo de este lugar: se vuelve a leer el índice justo antes y solo se sigue si de verdad es un lugar recién
    // agregado (sin cuenta anotada). Una cuenta que ya entró y trabajó nunca pasa por acá.
    final indice = await leerIndiceCuentas();
    if (indice.activa != null || !indice.guardadas.any((g) => g.id == id)) {
      if (mounted) {
        setState(() {
          _cuentas = indice;
          _trabajando = false;
          _error = 'No se puede volver a ese negocio desde acá. Entrá con tu cuenta y cambiá desde Cuenta y sincronización.';
        });
      }
      return;
    }
    await borrarTodoDelCelular(null, id);
    await volverAEmpezar();
  }

  /// Agregando otro negocio al celular: no hay cuenta activa y hay alguna guardada.
  bool get _agregando => _cuentas?.activa == null && (_cuentas?.guardadas.isNotEmpty ?? false);

  /// Entró en un negocio y sucursal que ya están guardados en este celular con el mismo mail: tenerlos dos veces sería tener
  /// dos copias de lo mismo. Se ofrece ir al guardado (con todo lo suyo) o elegir otro. Devuelve si se encargó (no hay que
  /// seguir). El mismo mail en otro negocio no es repetido: es justamente para eso (2026-10-13).
  Future<bool> _yaEstaGuardada(PerfilDeCuenta perfil) async {
    // Solo agregando: una cuenta que ya vivía acá (por ejemplo, entrando de nuevo porque venció la sesión) nunca se descarta.
    if (!_agregando) return false;
    final id = cuentaRepetida(_cuentas!, email: perfil.email, negocio: perfil.negocio, sucursal: perfil.sucursal);
    if (id == null || !mounted) return false;
    final guardada = _cuentas!.guardadas.firstWhere((c) => c.id == id);
    final ir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '${guardada.titulo} ya está en este celular',
        texto: 'Ya está guardado acá con ${perfil.email}, con todo lo suyo. Para no tenerlo dos veces, se usa ese.',
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
    // En la compu no hay cuenta de Google del teléfono: directo al navegador, como la PC.
    if (kIsWeb || esEscritorioAparte) return _entrarConNavegador();
    setState(() {
      _trabajando = true;
      _etapa = 'Esperando a Google…';
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

  void _enEtapa(String etapa) {
    if (mounted) setState(() => _etapa = etapa);
  }

  Future<void> _resolver(CuentaVinculada cuenta) async {
    if (mounted) setState(() => _trabajando = true);
    try {
      _enEtapa('Buscando tu negocio…');
      final perfil = await _sync!.cliente.yo(cuenta.token);
      if (await _yaEstaGuardada(perfil)) return;
      // Cómo se llama este negocio, para la lista de cuentas del celular (`cuentas_del_celular.dart`), y que quede anotado
      // como el activo (así "Volver a…" ya no aparece para él). Si falla, no frena la entrada.
      await guardarNegocioDeEstaCuenta(perfil);
      if (!kIsWeb && widget.leerCuentas == null) {
        try {
          await anotarCuentaActiva(perfil: perfil);
        } catch (e, st) {
          unawaited(registrarError('Anotar el negocio activo', e, st));
        }
      }
      // Un equipo nuevo en "Solo celular" (otro celular, o el navegador) baja primero lo que ya está en la nube: el perfil se busca
      // por nombre, y con la base todavía vacía se creaba otra persona con el mismo nombre (revisión 2026-10-12, "Caro" tres veces
      // en la Agenda). Sin red sigue igual que antes.
      if (await leerModoUso() == ModoUso.soloCelular) {
        _enEtapa('Bajando los datos del negocio…');
        _sincronizado = await sincronizarUnaVez(_sync!.servicio);
      }
      _enEtapa('Preparando la app…');
      final servicio = await (widget.servicio ?? servicioParaPerfil)();
      await resolverPerfilDeCuenta(perfil: perfil, servicio: servicio);
      if (!mounted) return;
      if (widget.alEntrar != null) {
        widget.alEntrar!(context);
        return;
      }
      final nuevo = await (widget.esNegocioNuevo ?? _esNegocioNuevo)(perfil);
      if (!mounted) return;
      if (nuevo) {
        await abrirAsistenteNegocio(context);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const PantallaMenuCompanion()));
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
    // Si la sync de recién terminó bien, ya está todo lo de la nube en la base: otra vuelta solo hacía esperar.
    final esNuevo = _sincronizado ? await baseSinNegocio(db) : await esNegocioNuevoTrasSincronizar(sync: _sync!.servicio, db: db);
    if (!esNuevo) return false;
    await prepararNegocioNuevo(db);
    await guardarPasosPendientes(pasosDelNegocio().toSet());
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
        etapa: _etapa,
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
