import 'dart:async';

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
import '../tema/presionable.dart';
import '../../domain/marca.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../servicios/nube.dart';
import '../../servicios/pc_local_nube.dart';
import 'seccion_cuenta_nube.dart';

class PantallaConfiguracion extends StatefulWidget {
  const PantallaConfiguracion({
    super.key,
    required this.db,
    required this.usuarioId,
    this.nube,
  });

  final AppDatabase db;
  final int usuarioId;

  /// Null = la cuenta global de la app real; los tests pasan la suya.
  final NubeApp? nube;

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  late final ConfiguracionControlador _c;

  /// Buscador de arriba (contextual, 2026-09-28): filtra las secciones.
  String _busqueda = '';

  /// Lo que se ve de cada grupo: lo que el módulo permite y lo que coincide con la búsqueda de arriba.
  List<SeccionConfiguracion> _seccionesDe(GrupoConfiguracion g) => [
    for (final s in g.secciones)
      if (_seccionDisponible(s) && coincideBusqueda('${g.etiqueta} ${_etiquetaSeccion(s)} ${_palabrasClave(s)}', _busqueda)) s,
  ];

  List<SeccionConfiguracion> get _seccionesVisibles => [for (final g in GrupoConfiguracion.values) ..._seccionesDe(g)];

  List<GrupoConfiguracion> get _gruposVisibles => [for (final g in GrupoConfiguracion.values) if (_seccionesDe(g).isNotEmpty) g];

  /// La sección de recargo de cigarrillos es parte del módulo de caja aparte.
  bool _seccionDisponible(SeccionConfiguracion s) => s != SeccionConfiguracion.cigarrillos || moduloActivo(Modulo.cajaAparte);

  void _buscar(String texto) {
    setState(() => _busqueda = texto);
    final visibles = _seccionesVisibles;
    // Una sola sección coincide: se abre directo. Si lo abierto dejó de coincidir, se pasa a lo primero que sí.
    if (visibles.length == 1 && _c.seccionActual != visibles.single) {
      _c.irASeccion(visibles.single);
    } else if (visibles.isNotEmpty && !visibles.contains(_c.seccionActual)) {
      _c.irASeccion(visibles.first);
    }
  }

  void _irAGrupo(GrupoConfiguracion g) {
    if (g == _c.grupoActual) return;
    final secciones = _seccionesDe(g);
    if (secciones.isNotEmpty) _c.irASeccion(secciones.first);
  }

  @override
  void initState() {
    super.initState();
    _c = ConfiguracionControlador(widget.db);
    _c.cargarTodo();
    // Apagar un módulo desde acá esconde sus secciones al instante.
    modulosActuales.addListener(_alCambiarModulos);
  }

  void _alCambiarModulos() {
    if (!mounted) return;
    setState(() {});
    if (!_seccionesVisibles.contains(_c.seccionActual)) _c.irASeccion(SeccionConfiguracion.modulos);
  }

  @override
  void dispose() {
    modulosActuales.removeListener(_alCambiarModulos);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ConfiguracionControlador>.value(
      value: _c,
      child: Consumer<ConfiguracionControlador>(
        builder: (context, c, _) {
          final grupo = c.grupoActual;
          final secciones = _seccionesDe(grupo);
          final textTheme = Theme.of(context).textTheme;
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
                        mensajeVacio: 'Ningún ajuste coincide',
                        items: [
                          for (final g in _gruposVisibles)
                            FilaLista(
                              key: Key('grupo_${g.name}'),
                              nombre: g.etiqueta,
                              seleccionada: grupo == g,
                              onTap: () => _irAGrupo(g),
                            ),
                        ],
                      ),
                      const SizedBox(width: Espaciado.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(grupo.etiqueta, style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte)),
                            const SizedBox(height: Espaciado.xs),
                            Text(grupo.descripcion, style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario)),
                            if (secciones.length > 1) ...[
                              const SizedBox(height: Espaciado.md),
                              Wrap(
                                spacing: Espaciado.xs,
                                runSpacing: Espaciado.xs,
                                children: [
                                  for (final s in secciones)
                                    _PastillaSeccion(
                                      key: Key('pastilla_${s.name}'),
                                      etiqueta: _etiquetaSeccion(s),
                                      activa: s == c.seccionActual,
                                      onTap: () => c.irASeccion(s),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: Espaciado.md),
                            // Respaldo e Impresión traen sus propias superficies y listas que llenan el alto: van sin el
                            // panel con scroll del resto.
                            Expanded(
                              // Cambiar de sección funde el contenido en vez de saltar.
                              child: AnimatedSwitcher(
                                duration: Animaciones.corta,
                                switchInCurve: Animaciones.curva,
                                layoutBuilder: (actual, anteriores) => Stack(
                                  fit: StackFit.expand,
                                  children: [...anteriores, ?actual],
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey(c.seccionActual),
                                  child: switch (c.seccionActual) {
                                SeccionConfiguracion.respaldo => ContenidoRespaldo(db: widget.db, usuarioId: widget.usuarioId),
                                SeccionConfiguracion.impresion => ContenidoImpresion(db: widget.db, usuarioId: widget.usuarioId),
                                _ => Superficie(
                                  // `Material(transparency)`: varias secciones usan `ListTile`; sin esto el `Bloque` tapa
                                  // el ink y Flutter tira una excepción al tocar.
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: SingleChildScrollView(child: _contenido(c)),
                                  ),
                                ),
                              },
                                ),
                              ),
                            ),
                          ],
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
      case SeccionConfiguracion.cuentaNube:
        return SeccionCuentaNube(db: widget.db, nube: widget.nube);
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
      case SeccionConfiguracion.actualizaciones:
        return const _SeccionActualizaciones();
    }
  }
}

/// Lo que alguien escribiría buscando esa sección sin saber cómo se llama.
String _palabrasClave(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'nombre negocio comercio ticket encabezado direccion datos',
  SeccionConfiguracion.cuentaNube => 'cuenta nodo sur nube copias respaldo google vincular restaurar beta',
  SeccionConfiguracion.modulos => 'modulos funciones activar desactivar apagar promos fiado pesables turnos',
  SeccionConfiguracion.cigarrillos => 'atado suelto lata cigarrillos recargo qr',
  SeccionConfiguracion.cajaYRedondeo => 'fondo vuelto cajon efectivo redondeo paso',
  SeccionConfiguracion.vuelto => 'caramelo vuelto producto alt c',
  SeccionConfiguracion.categorias => 'rubro ganancia margen markup categoria',
  SeccionConfiguracion.usuarios => 'empleado turno persona nombre',
  SeccionConfiguracion.mediosPago => 'efectivo mercado pago qr debito',
  SeccionConfiguracion.menu => 'menu orden ocultar secciones',
  SeccionConfiguracion.apariencia => 'tema oscuro claro modo colores',
  SeccionConfiguracion.respaldo => 'backup copia drive onedrive carpeta',
  SeccionConfiguracion.impresion => 'ticket pdf impresora posnet point terminal token',
  SeccionConfiguracion.companion => 'celular android qr emparejar apk',
  SeccionConfiguracion.actualizaciones => 'version actualizar actualizacion update buscar novedades',
};

String _etiquetaSeccion(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'Comercio',
  SeccionConfiguracion.cuentaNube => 'Cuenta de Nodo Sur',
  SeccionConfiguracion.modulos => 'Módulos',
  SeccionConfiguracion.cigarrillos => 'Cigarrillos',
  SeccionConfiguracion.cajaYRedondeo => 'Caja y redondeo',
  SeccionConfiguracion.vuelto => 'Vuelto',
  SeccionConfiguracion.categorias => 'Ganancia por categoría',
  SeccionConfiguracion.usuarios => 'Usuarios',
  SeccionConfiguracion.mediosPago => 'Medios de pago',
  SeccionConfiguracion.menu => 'Menú',
  SeccionConfiguracion.apariencia => 'Tema',
  SeccionConfiguracion.respaldo => 'Respaldo',
  SeccionConfiguracion.impresion => 'Impresión y posnet',
  SeccionConfiguracion.companion => 'Celular',
  SeccionConfiguracion.actualizaciones => 'Versión',
};

class _PastillaSeccion extends StatelessWidget {
  const _PastillaSeccion({super.key, required this.etiqueta, required this.activa, required this.onTap});

  final String etiqueta;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Presionable(
      radio: 999,
      onTap: onTap,
      color: activa ? colores.textoPrimario : colores.fondoBloque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.sm),
        child: Text(
          etiqueta,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: activa ? Pesos.medium : FontWeight.w500,
            color: activa ? colores.fondo : colores.textoPrimario,
          ),
        ),
      ),
    );
  }
}

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
          Text(
            'Apagá lo que no usás. No se borra nada: al prenderlo vuelve como estaba.',
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
          Text(
            'El encabezado sale arriba de cada ticket, una línea por renglón. Vacío, lleva solo el nombre.',
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
      final primerAtado = parsearARS(_primerAtadoCtrl.text);
      final atadoAdicional = parsearARS(_atadoAdicionalCtrl.text);
      final suelto = parsearARS(_sueltoCtrl.text);
      // Un recargo negativo restaría plata al cliente: no se guarda.
      if (primerAtado < 0 || atadoAdicional < 0 || suelto < 0) return;
      widget.c.guardarRecargo(
        primerAtado: primerAtado,
        atadoAdicional: atadoAdicional,
        suelto: suelto,
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
          CampoPlata(
            key: const Key('campo_fondo_fijo'),
            controller: _fondoFijoCtrl,
            etiqueta: 'Fondo fijo del cajón (para dar vuelto)',
            onSubmitted: (_) {
              try {
                final fondo = parsearARS(_fondoFijoCtrl.text);
                if (fondo >= 0) widget.c.guardarFondoFijo(fondo);
              } on FormatException {
                /* se ignora hasta que sea válido */
              }
            },
          ),
          const SizedBox(height: Espaciado.md),
          CampoPlata(
            key: const Key('campo_paso_redondeo'),
            controller: _redondeoCtrl,
            etiqueta: 'Redondeo en efectivo',
            onSubmitted: (_) {
              try {
                // Paso 0 o negativo rompería el redondeo de cada cobro en efectivo.
                final paso = parsearARS(_redondeoCtrl.text);
                if (paso > 0) widget.c.guardarPasoRedondeo(paso);
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
            'El botón de vuelto de la venta (Alt+C) agrega 1 de este producto.',
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
            'Ganancia de referencia sobre el precio. Es solo una guía al cargar productos.',
            style: TextStyle(color: context.colores.textoSecundario),
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
                        if (pct != null && pct >= 0 && pct < 100) {
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
                tooltip: 'Agregar',
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
            'Tocá uno para renombrarlo.',
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
            'Qué secciones se ven arriba y en qué orden.',
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
                    tooltip: 'Subir',
                    icon: const Icon(IconosPlazoleta.arrowUpward, size: 16),
                    onPressed: i == 0
                        ? null
                        : () => c.moverSeccion(i, arriba: true),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    tooltip: 'Bajar',
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

/// Conectar un celular con esta PC (El dueño, 2026-10-03: "que empareje por un código numérico de una sola vez"). Si
/// el celular está con la misma cuenta y sucursal de Nodo Sur se conecta solo (la PC avisa su dirección al sitio,
/// `pc_local_nube.dart`); si no, el celular busca la PC en el wifi y pide este código de 6 números, que sirve una vez y
/// dura 5 minutos (`codigoEmparejamiento`, `/emparejar` en `servidor_companion.dart`). Ya no hay QR con la llave.
/// Sigue el QR para bajar la app: es una dirección para la cámara común de un celular que todavía no la tiene.
class _SeccionCompanion extends StatefulWidget {
  const _SeccionCompanion({required this.c});
  final ConfiguracionControlador c;

  @override
  State<_SeccionCompanion> createState() => _SeccionCompanionState();
}

class _SeccionCompanionState extends State<_SeccionCompanion> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    // El código vence solo: la cuenta regresiva se repinta cada segundo mientras haya uno.
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && codigoEmparejamiento.codigo != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _generarCodigo() async {
    if (widget.c.configuracion!.companionToken == null) await widget.c.generarTokenCompanion();
    setState(codigoEmparejamiento.generar);
  }

  Future<void> _desconectarCelulares() async {
    codigoEmparejamiento.anular();
    await widget.c.generarTokenCompanion();
    final nube = nubeApp;
    if (nube != null) unawaited(avisarPcLocal(widget.c.db, almacen: nube.almacen, cliente: nube.cliente));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ip = widget.c.companionIp;
    final textTheme = Theme.of(context).textTheme;
    final secundario = TextStyle(color: context.colores.textoSecundario);
    final codigo = codigoEmparejamiento.codigo;
    final restante = codigoEmparejamiento.restante;
    final mmss = '${restante.inMinutes}:${(restante.inSeconds % 60).toString().padLeft(2, '0')}';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Medidas.anchoMaximoContenido),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'En el celular tocá "Conectar con la PC". Si está con tu misma cuenta de Nodo Sur se conecta solo; si no, '
            'te pide este código. El celular tiene que estar en el mismo wifi.',
            style: secundario,
          ),
          const SizedBox(height: Espaciado.lg),
          if (ip == null)
            Text(
              'Esta PC no está conectada a una red local: conectala al wifi del local para emparejar un celular.',
              style: TextStyle(color: context.colores.error),
            )
          else ...[
            Superficie(
              relleno: context.colores.fondo,
              child: SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: Animaciones.corta,
                  child: codigo == null
                      ? Column(
                          key: const ValueKey('sin_codigo'),
                          children: [
                            Text('Código para un celular nuevo', style: textTheme.titleMedium),
                            const SizedBox(height: Espaciado.md),
                            BotonPrimario(texto: 'Generar código', onPressed: _generarCodigo),
                          ],
                        )
                      : Column(
                          key: ValueKey(codigo),
                          children: [
                            Text(
                              '${codigo.substring(0, 3)} ${codigo.substring(3)}',
                              key: const Key('codigo_emparejamiento'),
                              style: textTheme.displayMedium?.copyWith(fontWeight: Pesos.fuerte, letterSpacing: 6),
                            ),
                            const SizedBox(height: Espaciado.xs),
                            Text('Vence en $mmss · sirve una sola vez', style: secundario),
                            const SizedBox(height: Espaciado.md),
                            BotonSecundario(texto: 'Generar otro', onPressed: _generarCodigo),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: Espaciado.sm),
            Text('Esta PC en el wifi: $ip', style: textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario)),
            const SizedBox(height: Espaciado.lg),
            Text('¿Un celular que ya no usás?', style: textTheme.titleSmall),
            Text('Desconectarlos obliga a todos los celulares emparejados a conectarse de nuevo.', style: secundario),
            const SizedBox(height: Espaciado.sm),
            BotonSecundario(texto: 'Desconectar los celulares', onPressed: _desconectarCelulares),
            const SizedBox(height: Espaciado.xl),
            Text('Instalar la app en un celular', style: textTheme.titleSmall),
            Text('Escaneá esto con la cámara del celular para bajar la app.', style: secundario),
            const SizedBox(height: Espaciado.md),
            Superficie(
              relleno: context.colores.fondo,
              child: QrImageView(data: 'http://$ip:$puertoServidorCompanion/companion/apk', size: 180),
            ),
          ],
        ],
      ),
    );
  }
}

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
          FutureBuilder<String>(
            future: _version,
            builder: (context, snapshot) => Text(
              'Versión ${snapshot.data ?? '…'}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Actualizar no toca tus datos: antes se guarda una copia.',
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
