// "Cuenta y sincronización" en la companion: con quién está sincronizando este celular ahora (la PC por wifi,
// internet, o nadie) y la cuenta de Nodo Sur que hace falta para sincronizar por internet.
//
// Es lo único que hay que tocar para trabajar sin la PC: vincular la cuenta una vez. Después el celular pasa solo
// a internet si la PC no contesta (`conmutador_sync.dart`) y vuelve a la PC cuando contesta.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../servicios/cuenta_nube.dart';
import '../servicios/registro_errores.dart';
import '../servicios/sync_nube.dart';
import '../ui/comun/estado_mercado_pago.dart';
import '../domain/cuentas_del_celular.dart';
import 'borrar_celular.dart';
import 'reinicio_companion.dart';
import 'cuentas_del_celular.dart';
import '../servicios/recargar_pagina.dart';
import 'conmutador_sync.dart';
import 'elegir_sucursal.dart';
import 'google_en_celular.dart';
import 'kit/kit_ns.dart';
import 'sync_nube_companion.dart';
import '../plataforma.dart';
import 'entrar_en_compu.dart';

class PantallaCuentaCompanion extends StatefulWidget {
  const PantallaCuentaCompanion({super.key, required this.sync, this.alContinuar, this.borrarTodo, this.leerCuentas, this.pasarACuenta, this.volverAEmpezar});

  /// La sync del celular (en la app real, `syncNubeDelCelular()`).
  final SyncNubeCompanion sync;

  /// Al elegir "solo celular" por primera vez la pantalla se ofrece como un paso más (vincular ahora o después):
  /// con esto aparece el botón para seguir.
  final void Function(BuildContext context)? alContinuar;

  /// Borra todo lo del celular (`borrar_celular.dart`). Para tests.
  final Future<void> Function()? borrarTodo;

  /// Las cuentas de este celular (`cuentas_del_celular.dart`). Para tests.
  final Future<IndiceCuentas> Function()? leerCuentas;

  /// Pasa a otra cuenta guardada (o deja el lugar para una nueva, con null). Para tests.
  final Future<void> Function(String? destino)? pasarACuenta;

  /// Arma la app de cero después de cambiar (`volverAEmpezar`). Para tests.
  final Future<void> Function()? volverAEmpezar;

  @override
  State<PantallaCuentaCompanion> createState() => _PantallaCuentaCompanionState();
}

class _PantallaCuentaCompanionState extends State<PantallaCuentaCompanion> {
  CuentaVinculada? _cuenta;
  bool _cargando = true;
  bool _ocupado = false;
  String? _mensaje;

  /// Vincular con Google desde la app no anduvo (o se cerró el selector): se ofrece el navegador.
  bool _ofrecerNavegador = false;

  /// Las otras cuentas de este celular. Null mientras se leen (o en la web, que no tiene varias).
  IndiceCuentas? _cuentas;

  /// En qué negocio está esta cuenta (lo dijo el sitio al entrar).
  NegocioDeLaCuenta? _negocio;

  SyncNubeCompanion get _sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _leerCuenta();
  }

  Future<void> _leerCuenta() async {
    final cuenta = await _sync.cuenta();
    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _cargando = false;
    });
    // Las otras cuentas se leen aparte: la pantalla no las espera para mostrarse.
    final cuentas = await _leerCuentasDelCelular();
    final negocio = cuenta == null || widget.leerCuentas != null ? null : await leerNegocioDeEstaCuenta();
    if (mounted) {
      setState(() {
        _cuentas = cuentas;
        _negocio = negocio;
      });
    }
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

  /// Pasar a otra cuenta de este celular ([destino]) o agregar una nueva (null). La de ahora queda guardada tal cual, con sus
  /// ventas, su sync y su PC; nada pasa de una a la otra.
  Future<void> _pasarACuenta(String? destino, String titulo) async {
    final nueva = destino == null;
    final seguir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: nueva ? '¿Agregar otro negocio?' : '¿Pasar a $titulo?',
        texto:
            'El negocio de ahora queda guardado en este celular con todo lo suyo, sin mezclarse con el otro. '
            '${nueva ? 'Después entrás en el otro, con esta misma cuenta de Google o con otra' : 'Pasás a $titulo sin cerrar la app'}. '
            'Si el bot de WhatsApp está prendido, se apaga.',
        botones: [
          BotonNs.primario(ctx, nueva ? 'Agregar otro negocio' : 'Pasar a $titulo', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (seguir != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await (widget.pasarACuenta ?? pasarACuenta)(destino);
    } on CuentaNoEstaEnElCelular catch (e) {
      // Se comprobó antes de frenar nada: la app sigue como estaba, sin ese negocio en la lista. En una hoja: quien tocó el
      // botón está abajo de todo y un mensaje arriba no lo vería.
      if (!mounted) return;
      setState(() => _ocupado = false);
      final cuentas = await _leerCuentasDelCelular();
      if (mounted) setState(() => _cuentas = cuentas);
      if (!mounted) return;
      await mostrarHojaNs<void>(
        context,
        builder: (ctx) => HojaNs(
          titulo: e.toString(),
          texto: 'Se sacó de la lista. Para volver a tenerlo, agregalo de nuevo entrando con tu cuenta.',
          botones: [BotonNs.primario(ctx, 'Entendido', () => Navigator.of(ctx).pop())],
        ),
      );
      return;
    } catch (e, st) {
      // Ya se había frenado la sync y cerrado la base: seguir así no sirve. Lo que quedó a medias lo termina el próximo
      // arranque (o lo muestra, si tampoco puede).
      unawaited(registrarError('Cambiar de negocio', e, st));
      if (!mounted) return;
      await mostrarHojaNs<void>(
        context,
        descartable: false,
        builder: (ctx) => HojaNs(
          titulo: 'No se pudo terminar el cambio',
          texto: 'No se perdió nada. Se vuelve a intentar terminar el cambio.',
          botones: [BotonNs.primario(ctx, 'Seguir', () => Navigator.of(ctx).pop())],
        ),
      );
    }
    await (widget.volverAEmpezar ?? volverAEmpezar)();
  }

  /// En el celular, con la cuenta de Google del teléfono (sin navegador); en la web, por el sitio. Mismo criterio que
  /// `pantalla_entrar_con_cuenta.dart`.
  Future<void> _vincular({bool conNavegador = false}) async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      if (kIsWeb || conNavegador) {
        await _sync.vincular(nombre: nombreDelCelular());
      } else {
        final cuenta = await _sync.entrarConGoogle(
          nombre: nombreDelCelular(),
          elegir: (opciones) async => mounted ? elegirNegocio(context, opciones) : null,
        );
        if (cuenta == null && mounted) setState(() => _ofrecerNavegador = true);
      }
      await _leerCuenta();
    } on GoogleNoDisponible {
      if (mounted) {
        setState(() {
          _mensaje = 'No se pudo entrar con Google desde la app. Probá con el navegador.';
          _ofrecerNavegador = true;
        });
      }
    } on ErrorNube catch (e) {
      if (mounted) setState(() => _mensaje = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _mensaje = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _desvincular() async {
    final confirmar = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Cerrar sesión?',
        texto: 'Sin la cuenta no se sincroniza por internet. Lo que ya está guardado en el celular no se borra.',
        botones: [
          BotonNs.peligroSolido(ctx, 'Cerrar sesión', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (confirmar != true) return;
    await _sync.desvincular();
    await _leerCuenta();
  }

  Future<void> _entrarEnUnaCompu() async {
    final aviso = await entrarEnUnaCompu(context, sync: _sync);
    if (aviso != null && mounted) mostrarAvisoNs(context, aviso, largo: true);
  }

  Future<void> _sincronizarAhora() async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    final r = await _sync.servicio.sincronizar();
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _mensaje = textoDeResultado(r);
    });
  }

  /// Cerrar sesión y dejar el celular como recién instalado (El dueño, 2026-10-10: sin tener que ir a las
  /// configuraciones de Android). Con cuenta, antes se sube lo que falte: así no se pierde nada de lo cargado acá.
  Future<void> _cerrarSesion() async {
    final cuenta = _cuenta;
    final seguir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Cerrar sesión y borrar este celular?',
        texto: (cuenta != null
                ? 'Primero se manda a tu cuenta lo que falte subir. Después se borra todo lo de esta cuenta en el celular. '
                      'Entrando de nuevo con tu cuenta, vuelve a bajar.'
                : 'No entraste con una cuenta: todo lo que cargaste acá se pierde. La app arranca de cero.') +
            (_cuentas?.guardadas.isNotEmpty ?? false
                ? ' Las otras cuentas de este celular no se tocan: al abrir, seguís en ${_cuentas!.guardadas.first.titulo}.'
                : ''),
        botones: [
          BotonNs.peligroSolido(ctx, 'Cerrar sesión y borrar', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (seguir != true || !mounted) return;
    setState(() {
      _ocupado = true;
      _mensaje = cuenta != null ? 'Subiendo lo último…' : null;
    });
    if (cuenta != null) {
      final r = await _sync.servicio.sincronizar();
      if (!mounted) return;
      if (r is! SyncNubeOk) {
        final igual = await mostrarHojaNs<bool>(
          context,
          builder: (ctx) => HojaNs(
            titulo: 'No se pudo subir lo último',
            texto: '${textoDeResultado(r)} Si borrás igual, lo que no subió se pierde.',
            botones: [
              BotonNs.peligroSolido(ctx, 'Borrar igual', () => Navigator.of(ctx).pop(true)),
              BotonNs.secundario(ctx, 'No borrar', () => Navigator.of(ctx).pop(false)),
            ],
          ),
        );
        if (igual != true) {
          if (mounted) {
            setState(() {
              _ocupado = false;
              _mensaje = textoDeResultado(r);
            });
          }
          return;
        }
      }
    }
    if (widget.borrarTodo != null) {
      await widget.borrarTodo!();
      return;
    }
    await borrarTodoDelCelular();
    // En el navegador se recarga la página, que arranca de cero.
    if (kIsWeb) return recargarPagina();
    await (widget.volverAEmpezar ?? volverAEmpezar)();
  }

  Future<void> _volverABajarTodo() async {
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    final r = await _sync.servicio.volverABajarTodo();
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _mensaje = textoDeResultado(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    if (_cargando) {
      return PaginaNs(titulo: 'Cuenta y sincronización', sinVolver: widget.alContinuar != null, cuerpo: const Center(child: CircularProgressIndicator()));
    }
    final cuenta = _cuenta;
    return PaginaNs(
      titulo: 'Cuenta y sincronización',
      sinVolver: widget.alContinuar != null,
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          ValueListenableBuilder<ModoSync>(
            valueListenable: _sync.conmutador.modo,
            builder: (context, modo, _) => _TarjetaModo(modo: modo, hayCuenta: cuenta != null),
          ),
          if (cuenta != null)
            ValueListenableBuilder<int>(
              valueListenable: _sync.servicio.alCambiarEstado,
              builder: (context, _, _) {
                // "Todavía no hubo una vuelta" no es una novedad para mostrar: se ve recién con un resultado.
                if (_sync.servicio.ultimo == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _EstadoSync(vista: vistaDeSync(_sync.servicio.ultimo), ocupado: _ocupado, alVolverABajar: _volverABajarTodo),
                );
              },
            ),
          if (_mensaje != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoNs(_mensaje!)),
          const SizedBox(height: 8),
          FilaClaveValorNs(
            clave: 'Tu cuenta',
            valor: cuenta?.email ?? 'Sin entrar',
            tamanioValor: 19,
            colorValor: cuenta == null ? ns.b : null,
          ),
          if (cuenta != null && _negocio?.nombreNegocio != null)
            FilaClaveValorNs(
              clave: 'Negocio',
              valor: CuentaDelCelular(id: '', email: null, nombreNegocio: _negocio!.nombreNegocio, nombreSucursal: _negocio!.nombreSucursal).titulo,
            ),
          if (cuenta != null) FilaClaveValorNs(clave: 'Este celular', valor: cuenta.nombreDispositivo),
          // Nodo Sur Servicios de Windows se entra escaneando su QR con un celular ya vinculado (`entrar_en_compu.dart`).
          if (cuenta != null && esAndroid) ...[
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const Key('cuenta_entrar_en_compu'),
              child: BotonNs.secundario(context, 'Entrar en una compu', _ocupado ? null : _entrarEnUnaCompu, icono: IconoNs.computadora),
            ),
          ],
          if (cuenta == null) ...[
            const SizedBox(height: 12),
            const InfoNs(
              'Con la PC prendida, el celular sincroniza con ella. Si la PC se apaga o queda fuera del wifi, pasa solo a internet; cuando la PC vuelve, vuelve a ella.',
            ),
          ] else ...[
            const SizedBox(height: 20),
            const SeccionNs('Mercado Pago'),
            _SeccionMp(leer: () => _sync.cliente.estadoMp(cuenta.token)),
            const SizedBox(height: 12),
            const InfoNs(
              'Con la PC prendida, el celular sincroniza con ella. Si la PC se apaga o queda fuera del wifi, pasa solo a internet; cuando la PC vuelve, vuelve a ella.',
            ),
          ],
          if (_cuentas != null && widget.alContinuar == null) ...[
            const SizedBox(height: 20),
            _SeccionCuentas(cuentas: _cuentas!, ocupado: _ocupado, alPasar: _pasarACuenta),
          ],
        ],
      ),
      botones: [
        if (cuenta == null) ...[
          BotonNs.primario(context, _ocupado ? 'Entrando…' : 'Entrar con Google', _ocupado ? null : _vincular, habilitado: !_ocupado),
          if (_ofrecerNavegador)
            BotonNs.secundario(context, 'Entrar con el navegador', _ocupado ? null : () => _vincular(conNavegador: true)),
        ]
        else ...[
          BotonNs.primario(context, 'Sincronizar ahora', _ocupado ? null : _sincronizarAhora, habilitado: !_ocupado),
          BotonNs.peligroSuave(context, 'Cerrar sesión', _ocupado ? null : _desvincular),
        ],
        if (widget.alContinuar != null)
          BotonNs.secundario(context, cuenta == null ? 'Entrar más tarde' : 'Continuar', _ocupado ? null : () => widget.alContinuar!(context))
        else
          BotonNs.peligroSuave(context, 'Cerrar sesión y borrar este celular', _ocupado ? null : _cerrarSesion),
      ],
    );
  }
}

/// Las otras cuentas de este celular (El dueño, 2026-10-13: "múltiples cuentas sin cerrar la otra sesión pero tampoco
/// mezclando cosas"): pasar a una, o agregar otra.
class _SeccionCuentas extends StatelessWidget {
  const _SeccionCuentas({required this.cuentas, required this.ocupado, required this.alPasar});

  final IndiceCuentas cuentas;
  final bool ocupado;
  final void Function(String? destino, String titulo) alPasar;

  /// El nombre del negocio; si dos se llaman igual (el mismo negocio con dos personas), con el mail para distinguirlos.
  String _texto(CuentaDelCelular c) {
    final repetido = cuentas.guardadas.where((o) => o.titulo == c.titulo).length > 1;
    return repetido && c.detalle != null ? '${c.titulo} (${c.detalle})' : c.titulo;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('cuentas_del_celular'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SeccionNs('Otros negocios en este celular'),
        for (final c in cuentas.guardadas) ...[
          KeyedSubtree(
            key: Key('pasar_a_${c.id}'),
            child: BotonNs.secundario(context, 'Pasar a ${_texto(c)}', ocupado ? null : () => alPasar(c.id, c.titulo)),
          ),
          const SizedBox(height: 8),
        ],
        KeyedSubtree(
          key: const Key('agregar_cuenta'),
          child: BotonNs.secundario(context, 'Agregar otro negocio', ocupado ? null : () => alPasar(null, '')),
        ),
        const SizedBox(height: 12),
        const InfoNs(
          'Cada negocio guarda sus propias ventas, productos y caja en este celular, aunque entres con la misma cuenta de Google. '
          'Cambiar no cierra la sesión ni mezcla nada.',
        ),
      ],
    );
  }
}

/// El texto que se muestra tras una vuelta manual.
String textoDeResultado(ResultadoSyncNube r) => switch (r) {
  SyncNubeOk(:final bajadas, :final subidas) =>
    bajadas == 0 && subidas == 0 ? 'Todo al día.' : 'Listo: recibió $bajadas y mandó $subidas cambios.',
  SyncNubeSinCuenta() => 'Primero entrá con tu cuenta.',
  SyncNubeExpirada() => vistaDeSync(r).detalle,
  SyncNubeFallida(:final mensaje, :final sinRed) => sinRed ? 'Sin conexión a internet.' : mensaje,
};

/// Lo que está pasando con la sync, en una frase, y la salida cuando algo la traba (Regla: nunca un callejón sin salida).
class _EstadoSync extends StatelessWidget {
  const _EstadoSync({required this.vista, required this.ocupado, required this.alVolverABajar});

  final VistaSync vista;
  final bool ocupado;
  final VoidCallback alVolverABajar;

  @override
  Widget build(BuildContext context) {
    final tono = switch (vista.tono) {
      TonoSync.bien => TonoNs.good,
      TonoSync.espera => vista.titulo == 'Sin conexión' ? TonoNs.warn : TonoNs.neutro,
      TonoSync.atencion => TonoNs.bad,
    };
    return Column(
      key: const Key('estado_sync'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoNs(vista.detalle, tono: tono),
        if (vista.puedeVolverABajar) ...[
          const SizedBox(height: 12),
          KeyedSubtree(
            key: const Key('volver_a_bajar_todo'),
            child: BotonNs.secundario(context, 'Volver a bajar todo', ocupado ? null : alVolverABajar),
          ),
        ],
      ],
    );
  }
}

/// Mercado Pago: lo que dice el servidor (conectado, sin conectar, hay que reconectarlo) y el atajo al sitio.
class _SeccionMp extends StatefulWidget {
  const _SeccionMp({required this.leer});
  final Future<EstadoMp> Function() leer;

  @override
  State<_SeccionMp> createState() => _SeccionMpState();
}

class _SeccionMpState extends State<_SeccionMp> {
  late Future<EstadoMp?> _estado = _cargar();

  Future<EstadoMp?> _cargar() async {
    try {
      return await widget.leer();
    } on ErrorNube {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EstadoMp?>(
      future: _estado,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: FilaEsperaNs('Mirando Mercado Pago…'));
        }
        final vista = vistaDeEstadoMp(snap.data);
        return Column(
          key: const Key('estado_mercado_pago'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilaClaveValorNs(clave: 'Mercado Pago', valor: vista.titulo),
            InfoNs(vista.detalle),
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const Key('mp_abrir_negocio'),
              child: BotonNs.secundario(
                context,
                vista.listo ? 'Administrar en el sitio' : 'Conectar en el sitio',
                () async => launchUrl(urlNegocioNube, mode: LaunchMode.externalApplication),
              ),
            ),
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const Key('mp_reintentar'),
              child: BotonNs.secundario(context, 'Actualizar', () => setState(() => _estado = _cargar())),
            ),
          ],
        );
      },
    );
  }
}

class _TarjetaModo extends StatelessWidget {
  const _TarjetaModo({required this.modo, required this.hayCuenta});

  final ModoSync modo;
  final bool hayCuenta;

  @override
  Widget build(BuildContext context) {
    final (titulo, detalle) = switch (modo) {
      ModoSync.pc => ('Con la PC', 'Sincronizando por wifi.'),
      ModoSync.nube => ('Por internet', 'La PC no contesta: sincronizando con la nube.'),
      ModoSync.local => ('Solo en este celular', hayCuenta ? 'Esperando para sincronizar.' : 'Entrá con tu cuenta para sincronizar por internet.'),
    };
    // El bloque negro: lo más importante de la pantalla (con quién se sincroniza ahora).
    return HeroNs(
      ancho: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ahora', style: estiloNs(14, peso: FontWeight.w600, color: const Color(0xC7FFFFFF))),
          const SizedBox(height: 4),
          Text(titulo, style: tituloNs(46, track: -0.058, altura: 1.02, color: TokensNs.blanco)),
          const SizedBox(height: 6),
          Text(detalle, style: estiloNs(15, altura: 1.4, color: const Color(0xCCFFFFFF))),
        ],
      ),
    );
  }
}

/// La pantalla con la sync real del celular: la arma la primera vez que se abre.
class PantallaCuentaDelCelular extends StatelessWidget {
  const PantallaCuentaDelCelular({super.key, this.alContinuar});

  final void Function(BuildContext context)? alContinuar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SyncNubeCompanion>(
      future: syncNubeDelCelular(),
      builder: (context, snap) => snap.hasData
          ? PantallaCuentaCompanion(sync: snap.data!, alContinuar: alContinuar)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
