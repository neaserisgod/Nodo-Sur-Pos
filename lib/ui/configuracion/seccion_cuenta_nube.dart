// Configuración → Cuenta de Nodo Sur: vincular esta PC a la cuenta de Google del sitio, guardar copias de la base en
// la nube y restaurarlas (por ejemplo, después de reinstalar). La caja no depende de nada de esto.
//
// Con el kit del mock v4 (`cfgBody('cuenta')`, 2026-10-06): la tarjeta de la cuenta, la lista del negocio, los botones y
// "Copias en tu cuenta" con su "Restaurar".

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart';
import '../../servicios/copias_nube.dart';
import '../../servicios/cuenta_nube.dart';
import '../../servicios/nube.dart';
import '../../servicios/sync_nube.dart';
import '../comun/estado_mercado_pago.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import '../respaldo/dialogo_confirmar_restaurar.dart';
import 'cuenta_nube_controlador.dart';

class SeccionCuentaNube extends StatefulWidget {
  const SeccionCuentaNube({super.key, required this.db, this.nube});

  final AppDatabase db;

  /// Null = la global de la app real (`nubeApp`); los tests pasan la suya.
  final NubeApp? nube;

  @override
  State<SeccionCuentaNube> createState() => _SeccionCuentaNubeState();
}

class _SeccionCuentaNubeState extends State<SeccionCuentaNube> {
  CuentaNubeControlador? _c;
  String? _errorRestaurar;

  NubeApp? get _nube => widget.nube ?? nubeApp;

  @override
  void initState() {
    super.initState();
    final nube = _nube;
    if (nube != null) {
      _c = CuentaNubeControlador(nube: nube, db: widget.db)..cargar();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String _tamanio(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  String _fecha(DateTime f) => '${f.day}/${f.month}/${f.year} ${horaCorta(f)}';

  Future<void> _restaurar(CopiaEnNube copia) async {
    final c = _c!;
    setState(() => _errorRestaurar = null);
    try {
      final lista = await c.prepararRestauracion(copia);
      if (!mounted) return;
      await mostrarDialogoConfirmarRestaurar(
        context,
        db: widget.db,
        archivo: ArchivoRespaldo(ruta: lista.ruta, nombre: 'copia de tu cuenta', fecha: copia.creada, tamanioBytes: copia.tamanio),
        fechaFormateada: _fecha(copia.creada),
      );
    } on ErrorRestauracion catch (e) {
      if (mounted) setState(() => _errorRestaurar = e.mensaje);
    } on ErrorNube catch (e) {
      if (mounted) setState(() => _errorRestaurar = e.mensaje);
    }
  }

  /// Qué pasa con la sincronización entre dispositivos, con la salida cuando quedó atrás (nunca un callejón sin salida).
  Widget _estadoSync(BuildContext context, ServicioSyncNube sync) {
    final p = context.p;
    final vista = vistaDeSync(sync.ultimo);
    final color = switch (vista.tono) {
      TonoSync.bien => p.g,
      TonoSync.espera => p.mute,
      TonoSync.atencion => p.b,
    };
    return Tarjeta(
      key: const Key('nube_estado_sync'),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sincronización con tus otros dispositivos: ${vista.titulo}', style: estilo(16, 600, color: p.tinta)),
                Text(vista.detalle, style: estilo(14, 400, color: p.mute, alto: 1.4)),
              ],
            ),
          ),
          if (vista.puedeVolverABajar) ...[
            const SizedBox(width: 12),
            Btn('Volver a bajar todo', variante: VarBtn.ton, tam: TamBtn.sm, sobreGris: true, onTap: () => unawaited(sync.volverABajarTodo())),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = _c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Nota(
          texto: 'Con tu cuenta de Google se guardan copias cifradas de tus datos (las últimas 5) y, si reinstalás, entrás con la '
              'misma cuenta y recuperás todo. La caja no depende de nada de esto.',
        ),
        const SizedBox(height: 14),
        if (c == null)
          Text('La cuenta de Nodo Sur no está disponible en esta instalación.', key: const Key('nube_no_disponible'), style: estilo(15, 400, color: p.mute))
        else
          ListenableBuilder(listenable: Listenable.merge([c, c.nube.cambios]), builder: (context, _) => _contenido(context, c)),
      ],
    );
  }

  Widget _contenido(BuildContext context, CuentaNubeControlador c) {
    final p = context.p;
    final nota = estilo(14, 400, color: p.mute, alto: 1.45);
    if (c.cargando && c.cuenta == null) return const Padding(padding: EdgeInsets.all(16), child: Giro(child: Icono(Ic.reload, size: 22)));

    final mensajes = <Widget>[
      if (c.aviso != null) Nota(key: const Key('nube_aviso'), tono: TonoMock.g, texto: c.aviso!),
      if (c.error != null) Nota(key: const Key('nube_error'), tono: TonoMock.b, texto: c.error!),
      if (_errorRestaurar != null) Nota(key: const Key('nube_error_restaurar'), tono: TonoMock.b, texto: _errorRestaurar!),
    ];
    Widget apilar(List<Widget> hijos) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, h) in hijos.indexed) ...[if (i > 0) const SizedBox(height: 14), h],
      ],
    );

    if (!c.vinculada) {
      return apilar([
        Align(
          alignment: Alignment.centerLeft,
          child: Btn(
            c.vinculando ? 'Esperando en el navegador…' : 'Vincular con mi cuenta',
            variante: VarBtn.blue,
            onTap: c.vinculando ? null : c.vincular,
          ),
        ),
        if (c.vinculando) Text('Se abrió tu navegador: entrá con Google, confirmá y volvé acá.', style: nota),
        ...mensajes,
      ]);
    }

    final estado = c.estado;
    final ultimo = c.nube.ultimoResultado;
    final cuenta = c.cuenta!;
    return apilar([
      Tarjeta(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
        child: Row(
          children: [
            Avatar(cuenta.email, diametro: 58, tamanioTexto: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cuenta.email, style: estilo(20, 600, color: p.tinta)),
                  Text('Esta PC: ${cuenta.nombreDispositivo} · Google', style: estilo(15, 400, color: p.mute)),
                ],
              ),
            ),
            Etiqueta('Vinculada', key: const Key('nube_vinculada'), tono: TonoMock.g),
          ],
        ),
      ),
      if (c.equipo case final equipo? when !equipo.vacio) _Equipo(equipo: equipo),
      if (c.nube.sync case final sync?)
        ValueListenableBuilder<int>(
          valueListenable: sync.alCambiarEstado,
          builder: (context, _, _) => sync.ultimo == null ? const SizedBox.shrink() : _estadoSync(context, sync),
        ),
      if (c.canal == 'beta') Text('Esta PC recibe las versiones de prueba antes que los clientes.', key: const Key('nube_beta'), style: nota),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Btn(
            c.subiendo ? 'Guardando…' : 'Guardar una copia ahora',
            key: const Key('nube_boton_subir'),
            variante: VarBtn.blue,
            // Sin permiso también queda apagado.
            onTap: c.subiendo || (estado != null && !estado.puedeSubir) ? null : c.subirAhora,
          ),
          Btn('Desvincular esta PC', variante: VarBtn.out, onTap: c.subiendo ? null : c.desvincular),
        ],
      ),
      if (estado != null && estado.sinPermiso)
        Text(
          'Las copias de seguridad las maneja el dueño del negocio: con tu cuenta no hace falta suscripción ni guardar nada acá.',
          key: const Key('nube_sin_rol_copias'),
          style: nota,
        )
      else if (estado != null && !estado.puedeSubir)
        Text('Tu suscripción no está activa: podés restaurar copias, pero no guardar nuevas.', key: const Key('nube_sin_permiso_subir'), style: nota),
      if (ultimo is SubidaFallida && c.error == null)
        Nota(tono: TonoMock.b, texto: 'La última copia automática no se pudo guardar: ${ultimo.mensaje}'),
      ...mensajes,
      EstadoMercadoPago(leer: () async => c.nube.cliente.estadoMp((await c.nube.almacen.leer())!.token)),
      const Sec('Copias en tu cuenta'),
      if (estado == null)
        Text('No se pudieron leer las copias.', style: nota)
      else if (estado.copias.isEmpty)
        Text(
          estado.puedeRestaurar ? 'Todavía no hay copias guardadas.' : 'No hay copias disponibles para restaurar.',
          key: const Key('nube_sin_copias'),
          style: nota,
        )
      else
        Lista(filas: [
          for (final copia in estado.copias)
            Padding(
              key: Key('nube_copia_${copia.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_fecha(copia.creada)}${copia.nombreDispositivo == null ? '' : ' · ${copia.nombreDispositivo}'}',
                      style: estilo(17, 500, color: p.tinta, num: true),
                    ),
                  ),
                  Text(_tamanio(copia.tamanio), style: estilo(15, 400, color: p.mute, num: true)),
                  const SizedBox(width: 14),
                  Btn(
                    'Restaurar',
                    variante: VarBtn.ton,
                    tam: TamBtn.xs,
                    sobreGris: true,
                    onTap: estado.puedeRestaurar && !c.hayCajaAbierta ? () => _restaurar(copia) : null,
                  ),
                ],
              ),
            ),
        ]),
      if (c.hayCajaAbierta && estado != null && estado.copias.isNotEmpty)
        const Nota(tono: TonoMock.w, texto: 'Hay una caja abierta: cerrala para poder restaurar una copia.'),
    ]);
  }
}

/// El negocio, la sucursal de esta PC y, para el dueño, el equipo: solo para mirar. Se cambia en horsepos.com/negocio.
class _Equipo extends StatelessWidget {
  const _Equipo({required this.equipo});

  final EquipoDeCuenta equipo;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final miembros = equipo.miembros;
    return Column(
      key: const Key('nube_equipo'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (equipo.sucursal != null)
          Lista(
            key: const Key('nube_sucursal'),
            filas: [
              if (equipo.negocio != null) Kv('Negocio', equipo.negocio!),
              Kv('Sucursal', equipo.sucursal!),
              if (equipo.rol != null) Kv('Tu rol', nombreDeRol(equipo.rol)),
              if (miembros != null && miembros.isNotEmpty) Kv('Miembros', '${miembros.length}'),
            ],
          ),
        if (miembros != null && miembros.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Sec('Equipo'),
          const SizedBox(height: 10),
          Lista(filas: [
            for (final m in miembros)
              Padding(
                key: Key('nube_miembro_${m.email}'),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                child: Row(
                  children: [
                    Avatar(m.nombre ?? m.email, diametro: 38, tamanioTexto: 15),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.nombre ?? m.email, style: estilo(17, 600, color: p.tinta)),
                          Text(
                            m.todasLasSucursales ? 'todas las sucursales' : (m.sucursales.isEmpty ? 'sin sucursal' : m.sucursales.join(', ')),
                            style: estilo(14, 400, color: p.mute),
                          ),
                        ],
                      ),
                    ),
                    Etiqueta(nombreDeRol(m.rol)),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text('Para sumar o sacar gente, o cambiar sucursales, entrá a horsepos.com/negocio.', style: estilo(13.5, 400, color: p.mute)),
        ],
      ],
    );
  }
}
