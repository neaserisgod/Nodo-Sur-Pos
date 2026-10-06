// Configuración, hecha desde cero como el mock v4 (`SCR.config`, 2026-10-06):
//
// - Cabecera: "Configuración" y, a la derecha, el buscador grande ("Buscar un ajuste…"), que filtra la lista.
// - Izquierda (320): los cinco grupos (`.cgrp`, en mayúsculas chicas) con sus secciones (`.csec`, pastilla; la abierta
//   en negro).
// - Derecha: el nombre de la sección (h2), para qué sirve (lead) y su contenido, hasta 1000 de ancho.
//
// Lo que el mock trae y la app no tiene detrás no está, para no poner controles que no guardan nada: el interruptor
// "Redondear el efectivo" (el efectivo siempre redondea, REGLAS-NEGOCIO), el día del retiro semanal (eliminado, §13),
// la "Reserva diaria de fijos" (ver `docs/ESTADO-FIDELIDAD-MOCK.md`: hoy sale de los fijos del mes), los roles de
// usuario, el logo prendido/apagado, partículas/cursor/desplazamiento suave y el canal Beta/Estable.

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/marca.dart';
import '../../domain/modulos.dart';
import '../../servicios/actualizaciones.dart';
import '../../servicios/modulos_activos.dart';
import '../../servicios/nube.dart';
import '../../servicios/pc_local_nube.dart';
import '../../servidor/servidor_companion.dart';
import '../comun/armazon_gestion.dart';
import '../comun/aviso_superior.dart';
import '../impresion/pantalla_impresion.dart';
import '../kit/kit.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../respaldo/pantalla_respaldo.dart';
import 'configuracion_controlador.dart';
import 'seccion_asistente_ia.dart';
import 'seccion_cuenta_nube.dart';

class PantallaConfiguracion extends StatefulWidget {
  const PantallaConfiguracion({super.key, required this.db, required this.usuarioId, this.nube});

  final AppDatabase db;
  final int usuarioId;

  /// Null = la cuenta global de la app real; los tests pasan la suya.
  final NubeApp? nube;

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  late final ConfiguracionControlador _c;

  /// Lo escrito en el buscador de arriba: filtra las secciones de la izquierda.
  String _busqueda = '';

  /// Lo que se ve de cada grupo: lo que el módulo permite y lo que coincide con la búsqueda.
  List<SeccionConfiguracion> _seccionesDe(GrupoConfiguracion g) => [
    for (final s in g.secciones)
      if (_seccionDisponible(s) && coincideBusqueda('${g.etiqueta} ${etiquetaSeccion(s)} ${_palabrasClave(s)}', _busqueda)) s,
  ];

  List<SeccionConfiguracion> get _seccionesVisibles => [for (final g in GrupoConfiguracion.values) ..._seccionesDe(g)];

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
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'configuracion',
            usuarioId: widget.usuarioId,
            titulo: 'Configuración',
            acciones: [
              SizedBox(
                width: 420,
                child: BuscadorPagina(campoKey: const Key('busqueda_configuracion'), pista: 'Buscar un ajuste…', alto: 56, onCambio: _buscar),
              ),
            ],
            child: c.cargando
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: _Navegacion(c: c, seccionesDe: _seccionesDe),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        // Cambiar de sección funde el contenido en vez de saltar.
                        child: AnimatedSwitcher(
                          duration: hayMovimiento(context) ? ms(220) : Duration.zero,
                          switchInCurve: curvaEase,
                          layoutBuilder: (actual, anteriores) => Stack(fit: StackFit.expand, children: [...anteriores, ?actual]),
                          child: KeyedSubtree(
                            key: ValueKey(c.seccionActual),
                            child: _Derecha(c: c, contenido: _contenido(c)),
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

  Widget _contenido(ConfiguracionControlador c) => switch (c.seccionActual) {
    SeccionConfiguracion.comercio => _SeccionComercio(c: c),
    SeccionConfiguracion.usuarios => _SeccionUsuarios(c: c),
    SeccionConfiguracion.cajaYRedondeo => _SeccionCajaYRedondeo(c: c),
    SeccionConfiguracion.cigarrillos => _SeccionRecargoCigarrillos(c: c),
    SeccionConfiguracion.vuelto => _SeccionVuelto(c: c),
    SeccionConfiguracion.mediosPago => _SeccionMediosPago(c: c),
    SeccionConfiguracion.categorias => _SeccionCategorias(c: c),
    SeccionConfiguracion.cuentaNube => SeccionCuentaNube(db: widget.db, nube: widget.nube),
    SeccionConfiguracion.impresion => ContenidoImpresion(db: widget.db, usuarioId: widget.usuarioId),
    SeccionConfiguracion.companion => _SeccionCompanion(c: c),
    SeccionConfiguracion.asistenteIa => const SeccionAsistenteIa(),
    SeccionConfiguracion.respaldo => ContenidoRespaldo(db: widget.db, usuarioId: widget.usuarioId),
    SeccionConfiguracion.actualizaciones => const _SeccionVersion(),
    SeccionConfiguracion.apariencia => _SeccionTema(c: c),
    SeccionConfiguracion.menu => _SeccionMenu(c: c),
    SeccionConfiguracion.modulos => _SeccionModulos(c: c),
  };
}

/// Lo que alguien escribiría buscando esa sección sin saber cómo se llama.
String _palabrasClave(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'nombre negocio comercio rubro ticket encabezado logo direccion datos',
  SeccionConfiguracion.cuentaNube => 'cuenta nodo sur nube copias respaldo google vincular restaurar negocio sucursal miembros sync',
  SeccionConfiguracion.modulos => 'modulos funciones activar desactivar apagar promos fiado pesables turnos arqueo point encargues',
  SeccionConfiguracion.cigarrillos => 'atado suelto lata cigarrillos recargo qr',
  SeccionConfiguracion.cajaYRedondeo => 'fondo vuelto cajon efectivo redondeo paso',
  SeccionConfiguracion.vuelto => 'caramelo vuelto producto boton alt c',
  SeccionConfiguracion.categorias => 'rubro ganancia margen markup categoria referencia',
  SeccionConfiguracion.usuarios => 'empleado turno persona nombre',
  SeccionConfiguracion.mediosPago => 'efectivo mercado pago qr tarjeta debito credito',
  SeccionConfiguracion.menu => 'menu orden ocultar secciones',
  SeccionConfiguracion.apariencia => 'tema oscuro claro modo colores animaciones movimiento',
  SeccionConfiguracion.respaldo => 'backup copia drive onedrive carpeta restaurar importar',
  SeccionConfiguracion.impresion => 'ticket pdf impresora posnet point terminal token reimprimir',
  SeccionConfiguracion.companion => 'celular android qr emparejar codigo apk',
  SeccionConfiguracion.asistenteIa => 'ia inteligencia artificial gemini google clave api promos facturas',
  SeccionConfiguracion.actualizaciones => 'version actualizar actualizacion update buscar novedades',
};

/// El nombre de cada sección, como en el mock.
String etiquetaSeccion(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'Comercio',
  SeccionConfiguracion.usuarios => 'Usuarios',
  SeccionConfiguracion.cajaYRedondeo => 'Caja y redondeo',
  SeccionConfiguracion.cigarrillos => 'Cigarrillos',
  SeccionConfiguracion.vuelto => 'Vuelto',
  SeccionConfiguracion.mediosPago => 'Medios de pago',
  SeccionConfiguracion.categorias => 'Ganancia por categoría',
  SeccionConfiguracion.cuentaNube => 'Cuenta de Nodo Sur',
  SeccionConfiguracion.impresion => 'Impresión y posnet',
  SeccionConfiguracion.companion => 'Celular',
  SeccionConfiguracion.asistenteIa => 'Asistente IA',
  SeccionConfiguracion.respaldo => 'Respaldo',
  SeccionConfiguracion.actualizaciones => 'Versión',
  SeccionConfiguracion.apariencia => 'Tema y movimiento',
  SeccionConfiguracion.menu => 'Menú',
  SeccionConfiguracion.modulos => 'Módulos',
};

/// Para qué sirve cada sección: la línea que va bajo el título (`SDESC` del mock).
String _descripcionSeccion(SeccionConfiguracion s) => switch (s) {
  SeccionConfiguracion.comercio => 'Cómo se llama el local y qué dice el ticket.',
  SeccionConfiguracion.usuarios => 'Quién atiende. Cada turno arranca con la caja contada.',
  SeccionConfiguracion.cajaYRedondeo => 'Cuánto se redondea el efectivo y qué plata se aparta.',
  SeccionConfiguracion.cigarrillos => 'Recargo por pago virtual en ventas con cigarrillos.',
  SeccionConfiguracion.vuelto => 'El producto que se agrega cuando faltan \$ 100 de vuelto.',
  SeccionConfiguracion.mediosPago => 'Cómo se cobra y a qué caja va cada cosa.',
  SeccionConfiguracion.categorias => 'Ganancia de referencia por categoría.',
  SeccionConfiguracion.cuentaNube => 'Tu cuenta, el negocio y la sincronización.',
  SeccionConfiguracion.impresion => 'Ticket, impresora y terminal Point.',
  SeccionConfiguracion.companion => 'Vinculá la app Android con esta caja.',
  SeccionConfiguracion.asistenteIa => 'Ayuda para promos y facturas.',
  SeccionConfiguracion.respaldo => 'Copias automáticas y cómo volver atrás.',
  SeccionConfiguracion.actualizaciones => 'Qué versión tenés y cómo actualizarla.',
  SeccionConfiguracion.apariencia => 'Cómo se ve y cómo se mueve.',
  SeccionConfiguracion.menu => 'Qué secciones se ven y en qué orden.',
  SeccionConfiguracion.modulos => 'Qué partes del sistema están prendidas.',
};

// ───────────────────────────── armazón ─────────────────────────────

/// `.cfgnav`: los grupos con sus secciones. Tocar el nombre de un grupo abre su primera sección.
class _Navegacion extends StatelessWidget {
  const _Navegacion({required this.c, required this.seccionesDe});
  final ConfiguracionControlador c;
  final List<SeccionConfiguracion> Function(GrupoConfiguracion) seccionesDe;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final grupos = [
      for (final g in GrupoConfiguracion.values)
        if (seccionesDe(g).isNotEmpty) g,
    ];
    if (grupos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Sin coincidencias', style: estilo(16, 400, color: p.mute)),
      );
    }
    // 16 secciones fijas: no es una lista larga, va entera (así "Buscar" y los atajos llegan a todas aunque no se vean).
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in grupos) ...[
            Tocable(
              key: Key('grupo_${g.name}'),
              radio: 12,
              etiqueta: g.etiqueta,
              onTap: () {
                final secciones = seccionesDe(g);
                if (!secciones.contains(c.seccionActual)) c.irASeccion(secciones.first);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(g.etiqueta.toUpperCase(), style: estilo(12, 700, color: p.soft, em: .03)),
              ),
            ),
            for (final s in seccionesDe(g))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _Csec(key: Key('pastilla_${s.name}'), texto: etiquetaSeccion(s), elegida: s == c.seccionActual, onTap: () => c.irASeccion(s)),
              ),
          ],
        ],
      ),
    );
  }
}

/// `.csec`: pastilla de 40 con el nombre y la flechita; la abierta va en negro.
class _Csec extends StatelessWidget {
  const _Csec({super.key, required this.texto, required this.elegida, required this.onTap});
  final String texto;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AlPasar(
      builder: (encima) {
        final color = elegida ? p.papel : (encima ? p.tinta : p.mute);
        return Tocable(
          onTap: onTap,
          radio: 20,
          seleccionado: elegida,
          child: AnimatedContainer(
            duration: ms(200),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: elegida ? p.tinta : (encima ? p.s : p.s.withValues(alpha: 0)), borderRadius: BorderRadius.circular(999)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo(16, elegida ? 600 : 500, color: color),
                  ),
                ),
                Icono(Ic.chev, size: 16, color: color, grosor: 2.4),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// La columna derecha: título, para qué sirve y el contenido (hasta 1000 de ancho), todo con scroll.
class _Derecha extends StatelessWidget {
  const _Derecha({required this.c, required this.contenido});
  final ConfiguracionControlador c;
  final Widget contenido;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiquetaSeccion(c.seccionActual), style: Tipos.h2(p.tinta)),
          const SizedBox(height: 6),
          Text(_descripcionSeccion(c.seccionActual), style: estilo(17, 400, color: p.mute, alto: 1.5)),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: DefaultTextStyle(
              style: estilo(16, 400, color: p.tinta),
              child: contenido,
            ),
          ),
        ],
      ),
    );
  }
}

/// Las piezas de una sección, una debajo de la otra con 14 de aire (`gap:14px` del mock).
class _Apilado extends StatelessWidget {
  const _Apilado(this.hijos);
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, h) in hijos.indexed) ...[if (i > 0) const SizedBox(height: 14), h],
    ],
  );
}

/// Una fila de una `Lista` con algo a la izquierda, título y detalle, y botones a la derecha (usuarios, medios...).
class _FilaLista extends StatelessWidget {
  const _FilaLista({super.key, this.izquierda, required this.titulo, this.detalle, this.derecha = const [], this.apagada = false, this.tamanioTitulo = 18});
  final Widget? izquierda;
  final String titulo;
  final String? detalle;
  final List<Widget> derecha;
  final bool apagada;
  final double tamanioTitulo;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Opacity(
      opacity: apagada ? .5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        child: Row(
          children: [
            if (izquierda != null) ...[izquierda!, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo(tamanioTitulo, 600, color: p.tinta),
                  ),
                  if (detalle != null)
                    Text(
                      detalle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo(14, 400, color: p.mute),
                    ),
                ],
              ),
            ),
            for (final w in derecha) ...[const SizedBox(width: 8), w],
          ],
        ),
      ),
    );
  }
}

/// Un campo de plata que se guarda al dar Enter o al salir de él (el mock no tiene botón "Guardar" en estas secciones).
/// [guardar] recibe los centavos; si el texto no es un monto, no se guarda nada.
class _CampoPlata extends StatefulWidget {
  const _CampoPlata({super.key, required this.etiqueta, required this.centavos, required this.guardar});
  final String etiqueta;
  final int centavos;
  final Future<void> Function(int centavos) guardar;

  @override
  State<_CampoPlata> createState() => _CampoPlataState();
}

class _CampoPlataState extends State<_CampoPlata> {
  late final _ctrl = TextEditingController(text: formatearARS(widget.centavos, conSigno: false));
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus) _guardar();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _guardar() {
    try {
      final centavos = parsearARS(_ctrl.text);
      if (centavos != widget.centavos) unawaited(widget.guardar(centavos));
    } on FormatException {
      // Sin monto válido no se guarda: queda lo que había.
    }
  }

  @override
  Widget build(BuildContext context) =>
      Campo(etiqueta: widget.etiqueta, controller: _ctrl, focusNode: _foco, pista: r'$ 0', teclado: TextInputType.number, onSubmitted: (_) => _guardar());
}

/// Pide un nombre (renombrar o agregar) en un modal del mock. Null si se cancela o queda vacío.
Future<String?> _pedirNombre(BuildContext context, {required String titulo, String inicial = '', String boton = 'Guardar'}) async {
  final nombre = await mostrarModalMock<String>(
    context,
    builder: (context) => _DialogoNombre(titulo: titulo, inicial: inicial, boton: boton),
  );
  final limpio = nombre?.trim();
  return limpio == null || limpio.isEmpty ? null : limpio;
}

/// Dueño de su campo: el controlador vive lo que vive el modal, también durante la animación de salida.
class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre({required this.titulo, required this.inicial, required this.boton});
  final String titulo;
  final String inicial;
  final String boton;

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  late final _ctrl = TextEditingController(text: widget.inicial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.inicial.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModalMock(
    titulo: widget.titulo,
    ancho: AnchoModal.angosto,
    cuerpo: [
      Campo(key: const Key('campo_nombre_modal'), etiqueta: 'Nombre', controller: _ctrl, autofocus: true, onSubmitted: (v) => Navigator.of(context).pop(v)),
    ],
    pie: [Btn(widget.boton, variante: VarBtn.dark, ancho: true, onTap: () => Navigator.of(context).pop(_ctrl.text))],
  );
}

// ───────────────────────────── Negocio ─────────────────────────────

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

  Future<void> _elegirLogo() async {
    final archivo = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Imagen', extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp']),
      ],
    );
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    final listo = await widget.c.guardarLogoTicket(bytes);
    if (!listo && mounted) mostrarAviso(context, 'No se pudo abrir esa imagen');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final logo = widget.c.configuracion?.logoTicket;
    return _Apilado([
      Campo(key: const Key('campo_nombre_comercio'), etiqueta: 'Nombre del comercio', controller: _nombreCtrl),
      Campo(
        key: const Key('campo_encabezado_ticket'),
        etiqueta: 'Encabezado del ticket (una línea por renglón; vacío, va solo el nombre)',
        controller: _encabezadoCtrl,
        pista: 'Mi comercio\nCalle 123\nCiudad',
        maxLineas: 5,
      ),
      // `F.drop` del mock: el lugar del logo, con borde y la acción a la derecha.
      Tarjeta(
        linea: true,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        child: Row(
          children: [
            if (logo != null) ...[
              Container(
                key: const Key('vista_logo_ticket'),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Image.memory(logo, height: 48, filterQuality: FilterQuality.medium),
              ),
              const SizedBox(width: 18),
            ] else ...[
              Ibox(Ic.image, fondo: p.s),
              const SizedBox(width: 18),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Logo del ticket (opcional)', style: estilo(17, 600, color: p.tinta)),
                  Text(
                    'PNG o JPG · sale arriba del encabezado en el ticket en PDF, en blanco y negro. La terminal imprime solo texto.',
                    style: estilo(14, 400, color: p.mute, alto: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Btn(logo == null ? 'Elegir imagen' : 'Cambiar', key: const Key('boton_elegir_logo'), variante: VarBtn.ton, tam: TamBtn.sm, onTap: _elegirLogo),
            if (logo != null) ...[
              const SizedBox(width: 8),
              Btn('Quitar', key: const Key('boton_quitar_logo'), variante: VarBtn.out, tam: TamBtn.sm, onTap: widget.c.quitarLogoTicket),
            ],
          ],
        ),
      ),
      const Sec('Así sale en el ticket'),
      ListenableBuilder(
        listenable: Listenable.merge([_nombreCtrl, _encabezadoCtrl]),
        builder: (context, _) {
          final marca = MarcaNegocio(nombreComercio: _nombreCtrl.text, encabezadoTicket: _encabezadoCtrl.text);
          return Tarjeta(
            child: Column(
              children: [
                if (logo != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Image.memory(logo, height: 40)),
                for (final linea in marca.encabezadoTicketEfectivo.split('\n'))
                  Text(
                    linea,
                    textAlign: TextAlign.center,
                    style: estilo(16, 700, color: p.tinta),
                  ),
              ],
            ),
          );
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Btn('Guardar', variante: VarBtn.dark, onTap: _guardar),
      ),
    ]);
  }
}

class _SeccionUsuarios extends StatelessWidget {
  const _SeccionUsuarios({required this.c});
  final ConfiguracionControlador c;

  Future<void> _renombrar(BuildContext context, Usuario u) async {
    final nombre = await _pedirNombre(context, titulo: 'Renombrar', inicial: u.nombre);
    if (nombre != null) await c.renombrarUsuarioExistente(u.id, nombre);
  }

  Future<void> _agregar(BuildContext context) async {
    final nombre = await _pedirNombre(context, titulo: 'Agregar usuario', boton: 'Agregar');
    if (nombre != null) await c.agregarUsuario(nombre);
  }

  @override
  Widget build(BuildContext context) {
    return _Apilado([
      Lista(
        filas: [
          for (final u in c.usuarios)
            _FilaLista(
              key: Key('usuario_${u.id}'),
              izquierda: Avatar(u.nombre),
              titulo: u.activo ? u.nombre : '${u.nombre} · desactivado',
              detalle: u.activo ? null : 'No aparece para abrir caja',
              apagada: !u.activo,
              derecha: [
                Btn('Renombrar', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: () => _renombrar(context, u)),
                Btn(u.activo ? 'Desactivar' : 'Activar', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: () => c.alternarActivoUsuario(u)),
              ],
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Btn('Agregar usuario', key: const Key('boton_agregar_usuario'), variante: VarBtn.ton, icono: Ic.plus, onTap: () => _agregar(context)),
      ),
    ]);
  }
}

// ───────────────────────────── Caja y cobros ─────────────────────────────

class _SeccionCajaYRedondeo extends StatelessWidget {
  const _SeccionCajaYRedondeo({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final paso = c.configuracionNegocio!.pasoRedondeoCentavos;
    // Los tres pasos del mock; si se había guardado otro, también se ofrece (para no perderlo).
    final pasos = {5000, 10000, 20000, paso}.toList()..sort();
    return _Apilado([
      Lista(
        filas: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Paso de redondeo', style: estilo(18, 600, color: p.tinta)),
                      Text(
                        'El efectivo se redondea hacia arriba a este paso. Los cobros virtuales (QR, Point) nunca se redondean; '
                        'el redondeo se muestra aparte en el cierre.',
                        style: estilo(14, 400, color: p.mute, alto: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Seg<int>(
                  key: const Key('seg_paso_redondeo'),
                  opciones: [for (final v in pasos) (v, formatearARS(v, separado: true))],
                  valor: paso,
                  onCambio: c.guardarPasoRedondeo,
                ),
              ],
            ),
          ),
        ],
      ),
      _CampoPlata(
        key: const Key('campo_fondo_fijo'),
        etiqueta: 'Fondo fijo de caja (para dar vuelto)',
        centavos: c.configuracion!.fondoFijoCentavos,
        guardar: c.guardarFondoFijo,
      ),
    ]);
  }
}

class _SeccionRecargoCigarrillos extends StatelessWidget {
  const _SeccionRecargoCigarrillos({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final n = c.configuracionNegocio!;
    Future<void> guardar({int? primero, int? adicional, int? suelto}) async {
      // Un recargo negativo restaría plata al cliente: no se guarda.
      if ((primero ?? 0) < 0 || (adicional ?? 0) < 0 || (suelto ?? 0) < 0) return;
      await c.guardarRecargo(
        primerAtado: primero ?? n.recargoPrimerAtadoCentavos,
        atadoAdicional: adicional ?? n.recargoAtadoAdicionalCentavos,
        suelto: suelto ?? n.recargoSueltoCentavos,
      );
    }

    return _Apilado([
      const Nota(
        texto:
            'El recargo se aplica solo cuando la venta tiene cigarrillos y el medio incluye virtual (QR, Point o mixto). '
            'En mixtos se aplica completo. Se queda en la caja normal, nunca pasa a la lata.',
      ),
      Row(
        children: [
          Expanded(
            child: _CampoPlata(
              key: const Key('campo_primer_atado'),
              etiqueta: 'Primer atado',
              centavos: n.recargoPrimerAtadoCentavos,
              guardar: (v) => guardar(primero: v),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _CampoPlata(
              key: const Key('campo_atado_adicional'),
              etiqueta: 'Cada atado adicional',
              centavos: n.recargoAtadoAdicionalCentavos,
              guardar: (v) => guardar(adicional: v),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _CampoPlata(
              key: const Key('campo_suelto'),
              etiqueta: 'Cigarro suelto',
              centavos: n.recargoSueltoCentavos,
              guardar: (v) => guardar(suelto: v),
            ),
          ),
        ],
      ),
    ]);
  }
}

class _SeccionVuelto extends StatelessWidget {
  const _SeccionVuelto({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final id = c.configuracionNegocio!.productoVueltoId;
    final producto = c.productos.where((p) => p.id == id).firstOrNull;
    return _Apilado([
      const Nota(
        texto:
            'Cuando faltan exactamente \$ 100 de vuelto, el botón de vuelto de la venta agrega 1 de este producto en lugar '
            'del cambio. Es una venta (descuenta stock y computa ganancia), no un redondeo.',
      ),
      Lista(
        filas: [
          Kv(
            'Producto del botón de vuelto',
            '',
            valorWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Etiqueta(producto?.nombre ?? 'Sin configurar', tono: producto == null ? TonoMock.w : TonoMock.dark),
                const SizedBox(width: 10),
                Btn(
                  'Cambiar',
                  key: const Key('boton_cambiar_vuelto'),
                  variante: VarBtn.ton,
                  tam: TamBtn.xs,
                  sobreGris: true,
                  onTap: () async {
                    final elegido = await _elegirProducto(context, c.productos, actual: id);
                    if (elegido != null) await c.guardarProductoVuelto(elegido.$1);
                  },
                ),
              ],
            ),
          ),
          const Kv('Atajo', 'Alt+C'),
        ],
      ),
    ]);
  }
}

/// Elegir el producto del vuelto entre los del catálogo, con un buscador. `(null)` = sin producto; null = canceló.
Future<(int?,)?> _elegirProducto(BuildContext context, List<Producto> productos, {int? actual}) {
  return mostrarModalMock<(int?,)>(
    context,
    builder: (context) => _DialogoElegirProducto(productos: productos, actual: actual),
  );
}

class _DialogoElegirProducto extends StatefulWidget {
  const _DialogoElegirProducto({required this.productos, this.actual});
  final List<Producto> productos;
  final int? actual;

  @override
  State<_DialogoElegirProducto> createState() => _DialogoElegirProductoState();
}

class _DialogoElegirProductoState extends State<_DialogoElegirProducto> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lista = [
      for (final p in widget.productos)
        if (coincideBusqueda(p.nombre, _q)) p,
    ];
    return ModalMock(
      titulo: 'Producto del vuelto',
      ancho: AnchoModal.angosto,
      cuerpo: [
        BuscadorPagina(pista: 'Buscar un producto…', onCambio: (t) => setState(() => _q = t)),
        SizedBox(
          height: 360,
          child: ListView(
            children: [
              Rowb(
                titulo: 'Sin producto',
                detalle: 'El botón de vuelto no agrega nada',
                elegida: widget.actual == null,
                onTap: () => Navigator.of(context).pop((null,)),
              ),
              for (final p in lista.take(60))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Rowb(titulo: p.nombre, elegida: p.id == widget.actual, onTap: () => Navigator.of(context).pop((p.id,))),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeccionMediosPago extends StatelessWidget {
  const _SeccionMediosPago({required this.c});
  final ConfiguracionControlador c;

  Future<void> _renombrar(BuildContext context, MedioDePago medio) async {
    final nombre = await _pedirNombre(context, titulo: 'Renombrar', inicial: medio.nombre);
    if (nombre == null) return;
    try {
      await c.renombrarMedio(medio.id, nombre);
    } on ArgumentError catch (e) {
      // Nombre duplicado (`repositorio_medios_pago.dart`): un error de negocio, no un bug.
      if (context.mounted) mostrarAviso(context, e.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Apilado([
      Lista(
        filas: [
          for (final m in c.mediosDePago)
            _FilaLista(
              key: Key('medio_${m.id}'),
              izquierda: Ibox(m.esEfectivo ? Ic.cash : Ic.mp, fondo: context.p.papel),
              titulo: m.nombre,
              detalle: m.activo ? (m.esEfectivo ? 'Cajón' : 'Saldo de Mercado Pago') : 'Desactivado',
              apagada: !m.activo,
              derecha: [
                Btn('Renombrar', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: () => _renombrar(context, m)),
                Btn(m.activo ? 'Desactivar' : 'Activar', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: () => c.alternarActivoMedio(m)),
              ],
            ),
        ],
      ),
      const Nota(texto: 'QR, débito y crédito liquidan al mismo saldo, por eso son un solo medio en la caja. El canal se guarda como dato del pago.'),
    ]);
  }
}

// ───────────────────────────── Productos ─────────────────────────────

class _SeccionCategorias extends StatelessWidget {
  const _SeccionCategorias({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    return _Apilado([
      Lista(
        filas: [
          for (final (i, cat) in c.categorias.indexed)
            Builder(
              builder: (context) {
                final (fondo, tinta) = parDeRubro(cat.nombre, indice: i);
                final pct = (cat.markupDefaultBp / 100).round();
                return _FilaLista(
                  key: Key('categoria_${cat.id}'),
                  izquierda: Avatar(cat.nombre, fondo: fondo, color: tinta, diametro: 38, tamanioTexto: 15),
                  titulo: cat.nombre,
                  tamanioTitulo: 18,
                  derecha: [
                    Stp(
                      valor: '$pct %',
                      etiquetaMenos: 'Bajar la ganancia de ${cat.nombre}',
                      etiquetaMas: 'Subir la ganancia de ${cat.nombre}',
                      onMenos: pct <= 0 ? null : () => c.guardarMarkupCategoria(cat.id, (pct - 1) * 100),
                      onMas: pct >= 99 ? null : () => c.guardarMarkupCategoria(cat.id, (pct + 1) * 100),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      const Nota(texto: 'Ganancia de referencia sobre el precio: es una guía al cargar productos nuevos, no cambia ningún precio.'),
    ]);
  }
}

// ───────────────────────────── Equipos y cuenta ─────────────────────────────

/// Conectar un celular con esta PC (El dueño, 2026-10-03: "que empareje por un código numérico de una sola vez"). Si
/// el celular está con la misma cuenta y sucursal de Nodo Sur se conecta solo (la PC avisa su dirección al sitio,
/// `pc_local_nube.dart`); si no, el celular busca la PC en el wifi y pide este código de 6 números, que sirve una vez y
/// dura 5 minutos (`codigoEmparejamiento`, `/emparejar` en `servidor_companion.dart`). Sigue el QR para bajar la app.
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
    final p = context.p;
    final ip = widget.c.companionIp;
    final codigo = codigoEmparejamiento.codigo;
    final restante = codigoEmparejamiento.restante;
    final mmss = '${restante.inMinutes}:${(restante.inSeconds % 60).toString().padLeft(2, '0')}';
    if (ip == null) {
      return const Nota(
        tono: TonoMock.w,
        icono: Ic.wifioff,
        texto: 'Esta PC no está conectada a una red local: conectala al wifi del local para emparejar un celular.',
      );
    }
    final hero = BloqueHero(
      padding: const EdgeInsets.all(34),
      child: AnimatedSwitcher(
        duration: hayMovimiento(context) ? ms(220) : Duration.zero,
        child: Column(
          key: ValueKey(codigo),
          children: [
            Text('Código para emparejar', style: estilo(15, 600, color: p.heroSub)),
            const SizedBox(height: 12),
            if (codigo == null)
              Text('— — —', style: Tipos.fig(p.sobreHero.withValues(alpha: .4), tamanio: 78))
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${codigo.substring(0, 3)} ${codigo.substring(3)}',
                  key: const Key('codigo_emparejamiento'),
                  style: Tipos.fig(p.sobreHero, tamanio: 78).copyWith(letterSpacing: .06 * 78),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              codigo == null ? 'Generalo y escribilo en la app del celular.' : 'Ingresalo en la app del celular. Vence en $mmss y sirve una sola vez.',
              textAlign: TextAlign.center,
              style: estilo(14, 400, color: p.heroSub),
            ),
            const SizedBox(height: 18),
            Btn(codigo == null ? 'Generar código' : 'Generar otro', variante: VarBtn.blue, tam: TamBtn.sm, onTap: _generarCodigo),
          ],
        ),
      ),
    );
    final derecha = _Apilado([
      const Nota(
        texto:
            'En el celular tocá "Conectar con la PC". Si está con tu misma cuenta de Nodo Sur se conecta solo; si no, '
            'te pide este código. El celular tiene que estar en el mismo wifi.',
      ),
      Tarjeta(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(data: 'http://$ip:$puertoServidorCompanion/companion/apk', size: 112, padding: EdgeInsets.zero),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Instalar la app en un celular', style: estilo(17, 600, color: p.tinta)),
                  const SizedBox(height: 4),
                  Text('Escaneá esto con la cámara del celular para bajar la app. Esta PC en el wifi: $ip', style: estilo(14, 400, color: p.mute, alto: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Btn('Desconectar los celulares', variante: VarBtn.red, onTap: _desconectarCelulares),
      ),
      Text(
        '¿Un celular que ya no usás? Desconectarlos obliga a todos los celulares emparejados a conectarse de nuevo.',
        style: estilo(13.5, 400, color: p.mute),
      ),
    ]);
    return LayoutBuilder(
      builder: (context, lim) => lim.maxWidth >= 860
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 420, child: hero),
                const SizedBox(width: 20),
                Expanded(child: derecha),
              ],
            )
          : _Apilado([hero, derecha]),
    );
  }
}

/// Versión instalada y búsqueda manual de actualizaciones (2026-09-30). "Buscar actualizaciones" abre la ventana de
/// WinSparkle: lo pidió alguien, así que ahí sí es válido que muestre un resultado o un error de red.
class _SeccionVersion extends StatefulWidget {
  const _SeccionVersion();

  @override
  State<_SeccionVersion> createState() => _SeccionVersionState();
}

class _SeccionVersionState extends State<_SeccionVersion> {
  late final Future<String> _version = textoVersionApp();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final servicio = servicioActualizaciones;
    return _Apilado([
      BloqueHero(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión instalada', style: estilo(15, 600, color: p.heroSub)),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _version,
              builder: (context, s) => Text(s.data ?? '…', key: const Key('version_instalada'), style: Tipos.fig(p.sobreHero, tamanio: 52)),
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        // Sin servicio (tests, o una compilación sin actualizador) no hay nada que abrir.
        child: Btn('Buscar actualizaciones', variante: VarBtn.blue, onTap: servicio?.instalarAhora),
      ),
      const Nota(texto: 'Actualizar no toca tus datos: antes se guarda una copia.'),
    ]);
  }
}

// ───────────────────────────── Apariencia ─────────────────────────────

enum _Tema { claro, oscuro, automatico }

class _SeccionTema extends StatelessWidget {
  const _SeccionTema({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final cfg = c.configuracion!;
    final actual = cfg.temaAutomatico ? _Tema.automatico : (cfg.temaOscuro ? _Tema.oscuro : _Tema.claro);
    return _Apilado([
      const Sec('Tema'),
      Seg<_Tema>(
        key: const Key('seg_tema'),
        llenar: true,
        opciones: const [(_Tema.claro, 'Claro'), (_Tema.oscuro, 'Oscuro'), (_Tema.automatico, 'Automático (sigue a Windows)')],
        valor: actual,
        // Elegir claro u oscuro deja de seguir a Windows (`configurarTemaOscuroManual`).
        onCambio: (t) => switch (t) {
          _Tema.automatico => c.guardarTemaAutomatico(true),
          _Tema.claro => c.guardarTemaOscuro(false),
          _Tema.oscuro => c.guardarTemaOscuro(true),
        },
      ),
      const Nota(texto: 'Con "reducir animaciones" de Windows todo se apaga solo. Las animaciones nunca demoran lo que se tipea ni el cobro.'),
    ]);
  }
}

class _SeccionMenu extends StatelessWidget {
  const _SeccionMenu({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = c.secciones;
    return _Apilado([
      Lista(
        filas: [
          for (var i = 0; i < s.length; i++)
            Padding(
              key: Key('menu_${s[i].clave}'),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${i + 1}', style: estilo(16, 400, color: p.mute, num: true)),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: s[i].visible ? 1 : .45,
                      child: Text(s[i].etiqueta, style: estilo(18, 500, color: p.tinta)),
                    ),
                  ),
                  Btn(
                    '↑',
                    variante: VarBtn.ton,
                    tam: TamBtn.xs,
                    sobreGris: true,
                    etiqueta: 'Subir ${s[i].etiqueta}',
                    onTap: i == 0 ? null : () => c.moverSeccion(i, arriba: true),
                  ),
                  const SizedBox(width: 8),
                  Btn(
                    '↓',
                    variante: VarBtn.ton,
                    tam: TamBtn.xs,
                    sobreGris: true,
                    etiqueta: 'Bajar ${s[i].etiqueta}',
                    onTap: i == s.length - 1 ? null : () => c.moverSeccion(i, arriba: false),
                  ),
                  const SizedBox(width: 8),
                  Btn(s[i].visible ? 'Ocultar' : 'Mostrar', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: () => c.alternarVisibleSeccion(s[i])),
                ],
              ),
            ),
        ],
      ),
      const Nota(texto: 'Venta es la pantalla principal y no se puede ocultar. Configuración va siempre como engranaje.'),
    ]);
  }
}

class _SeccionModulos extends StatelessWidget {
  const _SeccionModulos({required this.c});
  final ConfiguracionControlador c;

  @override
  Widget build(BuildContext context) {
    final modulos = ModulosNegocio.desdeTexto(c.configuracionNegocio?.modulosDesactivados ?? '');
    return _Apilado([
      const Nota(texto: 'Apagá lo que no usás. No se borra nada: al prenderlo vuelve como estaba.'),
      Lista(
        filas: [
          for (final m in Modulo.values)
            Interruptor(
              key: Key('modulo_${m.clave}'),
              titulo: m.etiqueta,
              detalle: m.descripcion,
              valor: modulos.estaActivo(m),
              onCambio: (v) => c.cambiarModulo(m, activo: v),
            ),
        ],
      ),
    ]);
  }
}
