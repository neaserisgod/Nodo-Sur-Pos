// Configuración → Cuenta de Nodo Sur: vincular esta PC a la cuenta de Google del sitio, guardar copias de la base en
// la nube y restaurarlas (por ejemplo, después de reinstalar). La caja no depende de nada de esto.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart';
import '../../servicios/copias_nube.dart';
import '../../servicios/cuenta_nube.dart';
import '../../servicios/nube.dart';
import '../comun/botones.dart';
import '../comun/fechas.dart';
import '../respaldo/dialogo_confirmar_restaurar.dart';
import '../tema/iconos.dart';
import '../tema/tokens.dart';
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secundario = TextStyle(color: context.colores.textoSecundario);
    final c = _c;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuenta de Nodo Sur', style: textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Vinculá esta PC a tu cuenta de Google para guardar copias de tu base en la nube. Si borrás el sistema y la base, '
            'lo reinstalás, entrás con la misma cuenta y recuperás todo. Se guardan las últimas 5 copias, cifradas.',
            style: secundario,
          ),
          const SizedBox(height: Espaciado.lg),
          if (c == null)
            Text('La cuenta de Nodo Sur no está disponible en esta instalación.', key: const Key('nube_no_disponible'), style: secundario)
          else
            ListenableBuilder(listenable: Listenable.merge([c, c.nube.cambios]), builder: (context, _) => _contenido(context, c)),
        ],
      ),
    );
  }

  Widget _contenido(BuildContext context, CuentaNubeControlador c) {
    final textTheme = Theme.of(context).textTheme;
    final secundario = TextStyle(color: context.colores.textoSecundario);
    if (c.cargando && c.cuenta == null) return const Padding(padding: EdgeInsets.all(Espaciado.md), child: CircularProgressIndicator());

    final mensajes = <Widget>[
      if (c.aviso != null) Padding(padding: const EdgeInsets.only(top: Espaciado.md), child: Text(c.aviso!, key: const Key('nube_aviso'))),
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(top: Espaciado.md),
          child: Text(c.error!, key: const Key('nube_error'), style: TextStyle(color: context.colores.error)),
        ),
      if (_errorRestaurar != null)
        Padding(
          padding: const EdgeInsets.only(top: Espaciado.md),
          child: Text(_errorRestaurar!, key: const Key('nube_error_restaurar'), style: TextStyle(color: context.colores.error)),
        ),
    ];

    if (!c.vinculada) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: BotonPrimario(
              texto: c.vinculando ? 'Esperando en el navegador…' : 'Vincular con mi cuenta',
              onPressed: c.vinculando ? null : c.vincular,
            ),
          ),
          if (c.vinculando) ...[
            const SizedBox(height: Espaciado.md),
            Text('Se abrió tu navegador: entrá con Google, confirmá y volvé acá.', style: secundario),
          ],
          ...mensajes,
        ],
      );
    }

    final estado = c.estado;
    final ultimo = c.nube.ultimoResultado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(IconosPlazoleta.checkCircle, color: context.colores.acento, size: 20),
            const SizedBox(width: Espaciado.sm),
            Expanded(child: Text('Vinculada a ${c.cuenta!.email} · ${c.cuenta!.nombreDispositivo}', key: const Key('nube_vinculada'))),
          ],
        ),
        if (c.canal == 'beta') ...[
          const SizedBox(height: Espaciado.sm),
          Text('Esta PC recibe las versiones de prueba antes que los clientes.', key: const Key('nube_beta'), style: secundario),
        ],
        const SizedBox(height: Espaciado.lg),
        Wrap(
          spacing: Espaciado.md,
          runSpacing: Espaciado.sm,
          children: [
            BotonPrimario(
              texto: c.subiendo ? 'Guardando…' : 'Guardar una copia ahora',
              onPressed: c.subiendo || (estado != null && !estado.puedeSubir) ? null : c.subirAhora,
            ),
            BotonSecundario(texto: 'Desvincular esta PC', onPressed: c.subiendo ? null : c.desvincular),
          ],
        ),
        if (estado != null && !estado.puedeSubir) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'Tu suscripción no está activa: podés restaurar copias, pero no guardar nuevas.',
            key: const Key('nube_sin_permiso_subir'),
            style: secundario,
          ),
        ],
        if (ultimo is SubidaFallida && c.error == null) ...[
          const SizedBox(height: Espaciado.sm),
          Text('La última copia automática no se pudo guardar: ${ultimo.mensaje}', style: TextStyle(color: context.colores.error)),
        ],
        ...mensajes,
        const SizedBox(height: Espaciado.lg),
        Text('Copias en tu cuenta', style: textTheme.titleSmall),
        const SizedBox(height: Espaciado.sm),
        if (estado == null)
          Text('No se pudieron leer las copias.', style: secundario)
        else if (estado.copias.isEmpty)
          Text(
            estado.puedeRestaurar ? 'Todavía no hay copias guardadas.' : 'No hay copias disponibles para restaurar.',
            key: const Key('nube_sin_copias'),
            style: secundario,
          )
        else
          for (final copia in estado.copias)
            Padding(
              key: Key('nube_copia_${copia.id}'),
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_fecha(copia.creada)} · ${_tamanio(copia.tamanio)}${copia.nombreDispositivo == null ? '' : ' · ${copia.nombreDispositivo}'}',
                    ),
                  ),
                  BotonSecundario(
                    texto: 'Restaurar',
                    onPressed: estado.puedeRestaurar && !c.hayCajaAbierta ? () => _restaurar(copia) : null,
                  ),
                ],
              ),
            ),
        if (c.hayCajaAbierta && estado != null && estado.copias.isNotEmpty) ...[
          const SizedBox(height: Espaciado.sm),
          Text('Hay una caja abierta: cerrala para poder restaurar una copia.', style: secundario),
        ],
      ],
    );
  }
}
