import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../impresion/pantalla_impresion.dart';
import '../respaldo/pantalla_respaldo.dart';
import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../servicios/actualizaciones.dart';
import '../../servidor/servidor_companion.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fila_lista.dart';
import '../comun/lista_maestra.dart';
import '../comun/modal.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import '../navegacion/busqueda_contextual.dart';
import 'configuracion_controlador.dart';
import '../tema/iconos.dart';
import '../../domain/marca.dart';
import '../../domain/modulos.dart';

class PantallaConfiguracion extends StatefulWidget {
  const PantallaConfiguracion({
    super.key,
    required this.db,
    required this.usuarioId,
  });

  final AppDatabase db;
  final int usuarioId;

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  late final ConfiguracionControlador _c;

  /// Buscador de arriba (contextual, 2026-09-28): filtra las secciones.
  String _busqueda = '';

  List<SeccionConfiguracion> get _seccionesVisibles => [
    for (final s in SeccionConfiguracion.values)
      if (coincideBusqueda('${_etiquetaSeccion(s)} ${_palabrasClave(s)}', _busqueda)) s,
  ];

  void _buscar(String texto) {
    setState(() => _busqueda = texto);
    // Una sola sección coincide: se abre directo, sin tener que tocarla.
    final visibles = _seccionesVisibles;
    if (visibles.length == 1 && _c.seccionActual != visibles.single) _c.irASeccion(visibles.single);
  }

  @override
  void initState() {
    super.initState();
    _c = ConfiguracionControlador(widget.db);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ConfiguracionControlador>.value(
      value: _c,
      child: Consumer<ConfiguracionControlador>(
        builder: (context, c, _) {
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'configuracion',
            usuarioId: widget.usuarioId,
            titulo: 'Configuración',
            busqueda: BusquedaContextual(pista: 'Buscar un ajuste (fondo, redondeo, usuarios…)', alCambiar: _buscar),
            child: c.cargando
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListaMaestra(
                        mensajeVacio: 'Sin secciones',
                        items: [
                          for (final seccion in _seccionesVisibles)
                            FilaLista(
                              nombre: _etiquetaSeccion(seccion),
                              seleccionada: c.seccionActual == seccion,
                              onTap: () => c.irASeccion(seccion),
                            ),
                        ],
                      ),
                      const SizedBox(width: Espaciado.md),
                      // Respaldo e Impresión (antes apartados propios del
                      // menú, 2026-09-26) traen sus propias superficies y
                      // listas que llenan el alto — van sin el panel con
                      // scroll del resto de las secciones.
                      if (c.seccionActual == SeccionConfiguracion.respaldo)
                        Expanded(
                          child: ContenidoRespaldo(
                            db: widget.db,
                            usuarioId: widget.usuarioId,
                          ),
                        )
                      else if (c.seccionActual ==
                          SeccionConfiguracion.impresion)
                        Expanded(
                          child: ContenidoImpresion(
                            db: widget.db,
                            usuarioId: widget.usuarioId,
                          ),
                        )
                      else
                        Expanded(
                          child: Superficie(
                            // `Material(transparency)`: varias secciones de acá
                            // usan `ListTile` (Usuarios, Medios de pago,
                            // Secciones del menú) — sin esto, el `Bloque`
                            // (un `Container` con color) tapa el ink del
                            // `ListTile` y Flutter tira una excepción al tocar.
                            child: Material(
                              type: MaterialType.transparency,
                              child: SingleChildScrollView(
                                child: _contenido(c),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _contenido(ConfiguracionControlador c) {
    switch (c.seccionActual) {
      case SeccionConfiguracion.comercio:
        return _SeccionComercio(c: c);
      case SeccionConfiguracion.modulos:
        return _SeccionModulos(c: c);
      case SeccionConfiguracion.cigarrillos:
        return _SeccionRecargoCigarrillos(c: c);
      case SeccionConfiguracion.cajaYRedondeo:
        return _SeccionCajaYRedondeo(c: c);
      case SeccionConfiguracion.vuelto:
        return _SeccionVuelto(c: c);
      case SeccionConfiguracion.categorias:
        return _SeccionCategorias(c: c);
      case SeccionConfiguracion.usuarios:
        return _SeccionUsuarios(c: c);
      case SeccionConfiguracion.mediosPago:
        return _SeccionMediosPago(c: c);
      case SeccionConfiguracion.menu:
        return _SeccionMenu(c: c);
      case SeccionConfiguracion.apariencia:
        return _SeccionApariencia(c: c);
      // Se montan aparte, en `build` (ver el comentario ahí).
      case SeccionConfiguracion.respaldo:
      case SeccionConfiguracion.impresion:
        return const SizedBox.shrink();
      case SeccionConfiguracion.companion:
        return _SeccionCompanion(c: c);
      case SeccionConfiguracion.cuentaGoogle:
        return _SeccionCuentaGoogle(c: c);
      case SeccionConfiguracion.actualizaciones:
        return const _SeccionActualizaciones();
    }
  }
}

/// Lo que alguien escribiría buscando esa sección sin saber cómo se llama.
String _palabrasClave(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'nombre negocio comercio ticket encabezado direccion datos',
  SeccionConfiguracion.modulos => 'modulos funciones activar desactivar apagar promos fiado pesables turnos',
  SeccionConfiguracion.cigarrillos => 'atado suelto lata serra recargo qr',
  SeccionConfiguracion.cajaYRedondeo => 'fondo vuelto cajon efectivo redondeo paso',
  SeccionConfiguracion.vuelto => 'caramelo vuelto producto alt c',
  SeccionConfiguracion.categorias => 'rubro markup margen categoria',
  SeccionConfiguracion.usuarios => 'empleado turno persona nombre',
  SeccionConfiguracion.mediosPago => 'efectivo mercado pago qr debito',
  SeccionConfiguracion.menu => 'menu orden ocultar secciones',
  SeccionConfiguracion.apariencia => 'tema oscuro claro modo colores',
  SeccionConfiguracion.respaldo => 'backup copia drive onedrive carpeta',
  SeccionConfiguracion.impresion => 'ticket pdf impresora posnet point terminal token',
  SeccionConfiguracion.companion => 'celular android qr emparejar apk',
  SeccionConfiguracion.cuentaGoogle => 'google login cuenta sesion supabase',
  SeccionConfiguracion.actualizaciones => 'version actualizar actualizacion update buscar novedades',
};

String _etiquetaSeccion(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'Mi comercio',
  SeccionConfiguracion.modulos => 'Módulos',
  SeccionConfiguracion.cigarrillos => 'Recargo de cigarrillos',
  SeccionConfiguracion.cajaYRedondeo => 'Caja y redondeo',
  SeccionConfiguracion.vuelto => 'Botón de vuelto',
  SeccionConfiguracion.categorias => 'Categorías (markup)',
  SeccionConfiguracion.usuarios => 'Usuarios',
  SeccionConfiguracion.mediosPago => 'Medios de pago',
  SeccionConfiguracion.menu => 'Secciones del menú',
  SeccionConfiguracion.apariencia => 'Apariencia',
  SeccionConfiguracion.respaldo => 'Respaldo',
  SeccionConfiguracion.impresion => 'Impresión y posnet',
  SeccionConfiguracion.companion => 'App companion (Android)',
  SeccionConfiguracion.cuentaGoogle => 'Cuenta de Google',
  SeccionConfiguracion.actualizaciones => 'Versión y actualizaciones',
};

class _SeccionModulos extends StatelessWidget {
  const _SeccionModulos({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final modulos = ModulosNegocio.desdeTexto(c.configuracionNegocio?.modulosDesactivados ?? '');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Módulos', style: textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Apagá lo que tu comercio no usa: deja de aparecer en la app. No se borra nada, y al prenderlo vuelve todo como estaba. Vender, cobrar, el stock y el cierre de caja siempre están.',
            style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          for (final m in Modulo.values)
            SwitchListTile(
              key: Key('modulo_${m.clave}'),
              contentPadding: EdgeInsets.zero,
              title: Text(m.etiqueta),
              subtitle: Text(m.descripcion),
              value: modulos.estaActivo(m),
              onChanged: (v) => c.cambiarModulo(m, activo: v),
            ),
        ],
      ),
    );
  }
}

class _SeccionComercio extends StatefulWidget {
  const _SeccionComercio({required this.c});
  final ConfiguracionControlador c;

  @override
  State<_SeccionComercio> createState() => _SeccionComercioState();
}

class _SeccionComercioState extends State<_SeccionComercio> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _encabezadoCtrl;

  @override
  void initState() {
    super.initState();
    final config = widget.c.configuracionNegocio;
    _nombreCtrl = TextEditingController(text: config?.nombreComercio ?? '');
    _encabezadoCtrl = TextEditingController(text: config?.encabezadoTicket ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _encabezadoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() => widget.c.guardarDatosComercio(nombre: _nombreCtrl.text, encabezadoTicket: _encabezadoCtrl.text);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mi comercio', style: textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            'El nombre se ve en la ventana, el menú y el celular. El encabezado es lo que sale arriba de cada ticket, una línea por renglón (nombre, dirección, ciudad…); si lo dejás vacío, el ticket lleva solo el nombre.',
            style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          CampoTexto(key: const Key('campo_nombre_comercio'), controller: _nombreCtrl, etiqueta: 'Nombre del comercio'),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_encabezado_ticket'),
            controller: _encabezadoCtrl,
            etiqueta: 'Encabezado del ticket',
            pista: 'Mi comercio\nCalle 123\nCiudad',
            maxLines: 5,
            minLines: 3,
          ),
          const SizedBox(height: Espaciado.lg),
          Text('Así sale en el ticket', style: textTheme.labelMedium?.copyWith(color: context.colores.textoSecundario)),
          const SizedBox(height: Espaciado.xs),
          AnimatedBuilder(
            animation: Listenable.merge([_nombreCtrl, _encabezadoCtrl]),
            builder: (context, _) {
              final marca = MarcaNegocio(nombreComercio: _nombreCtrl.text, encabezadoTicket: _encabezadoCtrl.text);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Espaciado.md),
                decoration: BoxDecoration(color: context.colores.fondo, borderRadius: BorderRadius.circular(radioControlEscritorio)),
                child: Column(
                  children: [
                    for (final linea in marca.encabezadoTicketEfectivo.split('\n'))
                      Text(linea, textAlign: TextAlign.center, style: textTheme.titleSmall?.copyWith(fontWeight: Pesos.fuerte)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Espaciado.lg),
          Align(alignment: Alignment.centerLeft, child: BotonPrimario(texto: 'Guardar', onPressed: _guardar)),
        ],
      ),
    );
  }
}

class _SeccionRecargoCigarrillos extends StatefulWidget {
  const _SeccionRecargoCigarrillos({required this.c});
  final ConfiguracionControlador c;

  @override
  State<_SeccionRecargoCigarrillos> createState() =>
      _SeccionRecargoCigarrillosState();
}

class _SeccionRecargoCigarrillosState
    extends State<_SeccionRecargoCigarrillos> {
  late final _primerAtadoCtrl = TextEditingController(
    text: formatearARS(
      widget.c.configuracionNegocio!.recargoPrimerAtadoCentavos,
    ),
  );
  late final _atadoAdicionalCtrl = TextEditingController(
    text: formatearARS(
      widget.c.configuracionNegocio!.recargoAtadoAdicionalCentavos,
    ),
  );
  late final _sueltoCtrl = TextEditingController(
    text: formatearARS(widget.c.configuracionNegocio!.recargoSueltoCentavos),
  );

  void _guardar() {
    try {
      widget.c.guardarRecargo(
        primerAtado: parsearARS(_primerAtadoCtrl.text),
        atadoAdicional: parsearARS(_atadoAdicionalCtrl.text),
        suelto: parsearARS(_sueltoCtrl.text),
      );
    } on FormatException {
      // se ignora hasta que los 3 campos sean válidos
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recargo de cigarrillos (Regla 6)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            key: const Key('campo_primer_atado'),
            controller: _primerAtadoCtrl,
            etiqueta: 'Primer atado',
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: Espaciado.md),
          CampoPlata(
            key: const Key('campo_atado_adicional'),
            controller: _atadoAdicionalCtrl,
            etiqueta: 'Atado adicional',
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: Espaciado.md),
          CampoPlata(
            key: const Key('campo_suelto'),
            controller: _sueltoCtrl,
            etiqueta: 'Cigarrillo suelto',
            onSubmitted: (_) => _guardar(),
          ),
        ],
      ),
    );
  }
}

class _SeccionCajaYRedondeo extends StatefulWidget {
  const _SeccionCajaYRedondeo({required this.c});
  final ConfiguracionControlador c;

  @override
  State<_SeccionCajaYRedondeo> createState() => _SeccionCajaYRedondeoState();
}

class _SeccionCajaYRedondeoState extends State<_SeccionCajaYRedondeo> {
  late final _fondoFijoCtrl = TextEditingController(
    text: formatearARS(widget.c.configuracion!.fondoFijoCentavos),
  );
  late final _redondeoCtrl = TextEditingController(
    text: formatearARS(widget.c.configuracionNegocio!.pasoRedondeoCentavos),
  );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Caja y redondeo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            key: const Key('campo_fondo_fijo'),
            controller: _fondoFijoCtrl,
            etiqueta: 'Fondo fijo del cajón (para dar vuelto)',
            onSubmitted: (_) {
              try {
                widget.c.guardarFondoFijo(parsearARS(_fondoFijoCtrl.text));
              } on FormatException {
                /* se ignora hasta que sea válido */
              }
            },
          ),
          const SizedBox(height: Espaciado.md),
          CampoPlata(
            key: const Key('campo_paso_redondeo'),
            controller: _redondeoCtrl,
            etiqueta: 'Paso de redondeo en efectivo (Regla 2)',
            onSubmitted: (_) {
              try {
                widget.c.guardarPasoRedondeo(parsearARS(_redondeoCtrl.text));
              } on FormatException {
                /* se ignora hasta que sea válido */
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SeccionVuelto extends StatelessWidget {
  const _SeccionVuelto({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Botón de vuelto',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Botón fijo en la pantalla de venta (Alt+C) que agrega 1 unidad de este producto.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          _Selector<int?>(
            etiqueta: 'Producto',
            valor: c.configuracionNegocio!.productoVueltoId,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Sin configurar'),
              ),
              for (final p in c.productos)
                DropdownMenuItem(value: p.id, child: Text(p.nombre)),
            ],
            onChanged: c.guardarProductoVuelto,
          ),
        ],
      ),
    );
  }
}

class _SeccionCategorias extends StatelessWidget {
  const _SeccionCategorias({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Markup de referencia por categoría (Regla 14, informativo)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.lg),
          for (final categoria in c.categorias)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
              child: Row(
                children: [
                  Expanded(child: Text(categoria.nombre)),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      key: ValueKey(
                        '${categoria.id}_${categoria.markupDefaultBp}',
                      ),
                      initialValue: (categoria.markupDefaultBp / 100)
                          .toStringAsFixed(0),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      // `fillColor` explícito: este campo vive adentro del
                      // `Bloque` del panel derecho — mismo motivo que
                      // `CampoTexto`.
                      decoration: InputDecoration(
                        suffixText: '%',
                        fillColor: context.colores.fondo,
                      ),
                      onFieldSubmitted: (v) {
                        final pct = int.tryParse(v);
                        if (pct != null) {
                          c.guardarMarkupCategoria(categoria.id, pct * 100);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SeccionUsuarios extends StatefulWidget {
  const _SeccionUsuarios({required this.c});
  final ConfiguracionControlador c;

  @override
  State<_SeccionUsuarios> createState() => _SeccionUsuariosState();
}

class _SeccionUsuariosState extends State<_SeccionUsuarios> {
  final _nuevoCtrl = TextEditingController();

  void _agregar() {
    if (_nuevoCtrl.text.trim().isEmpty) return;
    widget.c.agregarUsuario(_nuevoCtrl.text.trim());
    _nuevoCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usuarios (Regla 18)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CampoTexto(
                  key: const Key('campo_nuevo_usuario'),
                  controller: _nuevoCtrl,
                  etiqueta: 'Nuevo usuario',
                  onSubmitted: (_) => _agregar(),
                ),
              ),
              IconButton(
                icon: const Icon(IconosPlazoleta.add),
                onPressed: _agregar,
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          for (final usuario in widget.c.usuarios)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                usuario.nombre,
                style: TextStyle(
                  color: usuario.activo ? null : context.colores.textoTenue,
                ),
              ),
              trailing: TextButton(
                onPressed: () => widget.c.alternarActivoUsuario(usuario),
                child: Text(usuario.activo ? 'Desactivar' : 'Activar'),
              ),
              onTap: () => _pedirRenombrar(usuario),
            ),
        ],
      ),
    );
  }

  Future<void> _pedirRenombrar(Usuario usuario) async {
    final ctrl = TextEditingController(text: usuario.nombre);
    final nombreNuevo = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: 'Renombrar usuario',
        contenido: CampoTexto(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        botones: [
          BotonSecundario(
            texto: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(),
          ),
          BotonPrimario(
            texto: 'Guardar',
            onPressed: () => Navigator.of(context).pop(ctrl.text),
          ),
        ],
      ),
    );
    if (nombreNuevo != null && nombreNuevo.trim().isNotEmpty) {
      widget.c.renombrarUsuarioExistente(usuario.id, nombreNuevo.trim());
    }
  }
}

class _SeccionMediosPago extends StatelessWidget {
  const _SeccionMediosPago({required this.c});
  final ConfiguracionControlador c;

  Future<void> _pedirRenombrar(BuildContext context, MedioDePago medio) async {
    final ctrl = TextEditingController(text: medio.nombre);
    final nombreNuevo = await mostrarModal<String>(
      context,
      builder: (context) => Modal(
        titulo: 'Renombrar medio de pago',
        contenido: CampoTexto(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        botones: [
          BotonSecundario(
            texto: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(),
          ),
          BotonPrimario(
            texto: 'Guardar',
            onPressed: () => Navigator.of(context).pop(ctrl.text),
          ),
        ],
      ),
    );
    if (nombreNuevo != null && nombreNuevo.trim().isNotEmpty) {
      try {
        await c.renombrarMedio(medio.id, nombreNuevo.trim());
      } on ArgumentError catch (e) {
        // Nombre duplicado (`repositorio_medios_pago.dart`) — mismo criterio
        // que `dialogo_editar_producto.dart` para un `ArgumentError` de
        // negocio, no un bug.
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Medios de pago',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Solo se puede renombrar o desactivar los existentes.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          for (final medio in c.mediosDePago)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                medio.nombre,
                style: TextStyle(
                  color: medio.activo ? null : context.colores.textoTenue,
                ),
              ),
              onTap: () => _pedirRenombrar(context, medio),
              trailing: TextButton(
                onPressed: () => c.alternarActivoMedio(medio),
                child: Text(medio.activo ? 'Desactivar' : 'Activar'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SeccionApariencia extends StatelessWidget {
  const _SeccionApariencia({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Apariencia', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tema automático según el horario del local'),
            subtitle: const Text(
              'Claro de 10 a 22 (local abierto), oscuro fuera de ese horario.',
            ),
            value: c.configuracion!.temaAutomatico,
            onChanged: c.guardarTemaAutomatico,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Modo oscuro'),
            subtitle: Text(
              c.configuracion!.temaAutomatico
                  ? 'Elegir acá apaga el tema automático de arriba.'
                  : 'Recomendado para muchas horas de pantalla seguidas.',
            ),
            // Refleja el modo YA aplicado (el automático manda mientras esté
            // prendido) — tocarlo apaga el automático y deja este valor fijo,
            // no al revés (`configurarTemaOscuroManual`).
            value: c.configuracion!.temaAutomatico
                ? oscuroPorHorarioDelLocal(DateTime.now())
                : c.configuracion!.temaOscuro,
            onChanged: c.guardarTemaOscuro,
          ),
        ],
      ),
    );
  }
}

class _SeccionMenu extends StatelessWidget {
  const _SeccionMenu({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Secciones del menú',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '"Cerrar caja", "Imprimir ticket" y "Configuración" son fijos, no aparecen acá.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          for (var i = 0; i < c.secciones.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.secciones[i].etiqueta,
                style: TextStyle(
                  color: c.secciones[i].visible
                      ? null
                      : context.colores.textoTenue,
                ),
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(IconosPlazoleta.arrowUpward, size: 16),
                    onPressed: i == 0
                        ? null
                        : () => c.moverSeccion(i, arriba: true),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: const Icon(IconosPlazoleta.arrowDownward, size: 16),
                    onPressed: i == c.secciones.length - 1
                        ? null
                        : () => c.moverSeccion(i, arriba: false),
                  ),
                ],
              ),
              trailing: Switch(
                value: c.secciones[i].visible,
                onChanged: (_) => c.alternarVisibleSeccion(c.secciones[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Emparejamiento de la companion app Android (spike 2026-09-07): un QR con
/// `{ip, puerto, token}` para que el celular sepa a qué IP conectarse y con
/// qué token — no es login de usuario (Bruno/su empleado eligen quién son
/// desde el celular, como al abrir caja), es solo la llave que evita que
/// cualquier otro dispositivo de la misma WiFi use la API.
///
/// Segundo QR, agregado 2026-09-07 (Bruno: "que en la app escaneando el QR
/// lo ponga para descargar") — una URL lisa a `/companion/apk`, para la
/// cámara común de un celular que todavía no tiene la app instalada (el QR
/// de arriba es JSON, útil solo para el escáner de la propia companion).
/// `/companion/apk` quedó sin token en `servidor_companion.dart` a
/// propósito: un navegador abriendo un link no puede mandar el header, y
/// el .apk en sí no es un dato sensible.
class _SeccionCompanion extends StatelessWidget {
  const _SeccionCompanion({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final token = c.configuracion!.companionToken;
    final ip = c.companionIp;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'App companion (Android)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Solo funciona con esta app abierta y el celular en la misma WiFi. '
            'Escaneá este código una vez desde la app del celular para emparejarlo.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          if (ip == null)
            Text(
              'No se encontró una red local conectada — conectá esta PC a la '
              'WiFi del local antes de generar el código.',
              style: TextStyle(color: context.colores.error),
            )
          else if (token == null)
            BotonPrimario(
              texto: 'Generar código',
              onPressed: c.generarTokenCompanion,
            )
          else ...[
            Center(
              child: Superficie(
                relleno: context.colores.fondo,
                child: QrImageView(
                  data: jsonEncode({
                    'ip': ip,
                    'puerto': puertoServidorCompanion,
                    'token': token,
                  }),
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: Espaciado.md),
            Text(
              'IP: $ip · Puerto: $puertoServidorCompanion',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Espaciado.lg),
            Text(
              'Generar uno nuevo desconecta cualquier celular ya emparejado con '
              'el código anterior.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.sm),
            BotonSecundario(
              texto: 'Generar uno nuevo',
              onPressed: c.generarTokenCompanion,
            ),
            const SizedBox(height: Espaciado.xl),
            const Divider(),
            const SizedBox(height: Espaciado.lg),
            Text(
              'Instalar en un celular nuevo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Este QR es distinto al de arriba — es una URL, para escanear con la '
              'cámara común del celular (no hace falta tener la app instalada '
              'todavía). Abre el navegador y descarga el .apk directo; después de '
              'instalarlo, escaneá el código de arriba para emparejarlo.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
            const SizedBox(height: Espaciado.lg),
            Center(
              child: Superficie(
                relleno: context.colores.fondo,
                child: QrImageView(
                  data: 'http://$ip:$puertoServidorCompanion/companion/apk',
                  size: 220,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Login del escritorio con la misma cuenta que la companion Android (Bruno,
/// 2026-09-18: "mismo login... que abra una ventana en Chrome... y luego
/// volver a la app"). No bloquea nada del resto de la app — Venta sigue
/// disponible al instante con o sin esta sesión conectada (`CLAUDE.md`,
/// "arranque vs. operación"); es la cuenta que habilita el motor de sync por
/// Supabase (`sincronizacion_supabase.dart`) entre esta PC y la companion.
class _SeccionCuentaGoogle extends StatelessWidget {
  const _SeccionCuentaGoogle({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final email = c.cuentaGoogleEmail;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuenta de Google',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'La misma cuenta con la que te logueás en la companion del '
            'celular — hace falta para sincronizar los datos entre esta PC '
            'y el celular.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          if (email != null) ...[
            Row(
              children: [
                Icon(
                  IconosPlazoleta.checkCircle,
                  color: context.colores.acento,
                  size: 20,
                ),
                const SizedBox(width: Espaciado.sm),
                Expanded(child: Text('Conectado como $email')),
              ],
            ),
            const SizedBox(height: Espaciado.lg),
            BotonSecundario(
              texto: 'Desconectar',
              onPressed: c.desconectarCuentaGoogle,
            ),
          ] else ...[
            BotonPrimario(
              texto: c.conectandoCuentaGoogle
                  ? 'Abriendo el navegador…'
                  : 'Conectar cuenta de Google',
              onPressed: c.conectandoCuentaGoogle
                  ? null
                  : c.conectarCuentaGoogle,
            ),
            if (c.conectandoCuentaGoogle) ...[
              const SizedBox(height: Espaciado.md),
              Text(
                'Se abrió (o está por abrirse) tu navegador — elegí la cuenta '
                'ahí y volvé acá.',
                style: TextStyle(color: context.colores.textoSecundario),
              ),
            ],
          ],
          if (c.errorCuentaGoogle != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(
              c.errorCuentaGoogle!,
              style: TextStyle(color: context.colores.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mismo criterio que `dialogo_editar_producto.dart` (fondo `colores.fondo`,
/// paso 1 del kit "qué es configurable y qué no"): el kit todavía no tiene
/// una pieza de selección propia.
class _Selector<T> extends StatelessWidget {
  const _Selector({
    required this.etiqueta,
    required this.valor,
    required this.items,
    required this.onChanged,
  });

  final String etiqueta;
  final T valor;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: Espaciado.xs),
        Container(
          height: Medidas.alturaControl,
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.md),
          decoration: BoxDecoration(
            color: context.colores.fondo,
            borderRadius: BorderRadius.circular(radioControlEscritorio),
          ),
          child: DropdownButton<T>(
            value: valor,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Versión instalada y búsqueda manual de actualizaciones (2026-09-30).
/// "Buscar actualizaciones" abre la ventana de WinSparkle: lo pidió alguien,
/// así que ahí sí es válido que muestre un resultado o un error de red.
class _SeccionActualizaciones extends StatefulWidget {
  const _SeccionActualizaciones();

  @override
  State<_SeccionActualizaciones> createState() => _SeccionActualizacionesState();
}

class _SeccionActualizacionesState extends State<_SeccionActualizaciones> {
  late final Future<String> _version = textoVersionApp();

  @override
  Widget build(BuildContext context) {
    final servicio = servicioActualizaciones;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versión y actualizaciones',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.sm),
          FutureBuilder<String>(
            future: _version,
            builder: (context, snapshot) => Text(
              'Versión ${snapshot.data ?? '…'}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Las actualizaciones no tocan la base de datos. Antes de instalar '
            'una, se guarda una copia al lado de la base.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.lg),
          BotonSecundario(
            texto: 'Buscar actualizaciones',
            // Sin servicio (tests, o una compilación sin actualizador) no
            // hay nada que abrir.
            onPressed: servicio?.instalarAhora,
          ),
        ],
      ),
    );
  }
}
