// Apertura de una sesión de caja — un día si es la primera del día, un
// turno si ya hubo una hoja cerrada antes hoy (El dueño, sesión del
// 31/08/2026: un turno ES una sesión, no una tabla aparte). El arqueo y la
// separación de cigarrillos son de la fase 4 — esto solo abre la sesión
// para que la pantalla de venta tenga dónde grabar.
//
// Pasado al kit (2026-09-12, el dueño: "el modal de apertura es gigante") —
// nunca había pasado por acá: el `Dialog` crudo + `ConstrainedBox(maxHeight:
// 85% de la pantalla)` + `SingleChildScrollView` que tenía antes se
// estiraba a ese 85% SIEMPRE, aunque el contenido entrara de sobra (un
// `SingleChildScrollView` acotado por altura pero sin nada más que lo
// obligue a un tamaño real reporta ese máximo como su tamaño, no el del
// contenido). `Modal` ya resuelve ancho (760, como cualquier otro
// formulario) y no fuerza ninguna altura salvo que se lo pida — acá no
// hace falta: usuario + tres montos entran de sobra en el piso mínimo
// (1366×768) sin scrollear.

import 'package:flutter/material.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../../data/repositorio_cierre.dart';
import '../../data/repositorio_reposicion.dart';
import '../../data/repositorio_usuarios.dart';
import '../../data/repositorio_ventas.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoAperturaCaja(
  BuildContext context, {
  required AppDatabase db,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DialogoAperturaCaja(db: db),
  );
}

class DialogoAperturaCaja extends StatefulWidget {
  const DialogoAperturaCaja({super.key, required this.db});

  final AppDatabase db;

  @override
  State<DialogoAperturaCaja> createState() => _DialogoAperturaCajaState();
}

class _DialogoAperturaCajaState extends State<DialogoAperturaCaja> {
  List<Usuario> _usuarios = [];
  int? _usuarioId;
  final _fondoInicialCtrl = TextEditingController();
  final _lataInicialCtrl = TextEditingController();
  final _mpInicialCtrl = TextEditingController();
  final _nuevoUsuarioCtrl = TextEditingController();
  bool _agregandoUsuario = false;
  bool _fondoPrecargado = false;
  bool _lataPrecargada = false;
  bool _mpPrecargado = false;
  List<({String nombre, int montoCentavos})> _avisoReposicion = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
    _precargarFondoInicial();
    _precargarLataInicial();
    _precargarMpInicial();
    _cargarAvisoReposicion();
  }

  /// Aviso corto de cuánto separar de cada proveedor — El dueño separa acá,
  /// con la persiana baja, no al cerrar (Regla 5 extendida).
  Future<void> _cargarAvisoReposicion() async {
    final aviso = await avisoASepararAlAbrir(widget.db);
    if (mounted) setState(() => _avisoReposicion = aviso);
  }

  /// "QUEDA EN EL CAJON" de la hoja que se acaba de cerrar hoy es la "Caja
  /// inicial NORMAL" de la que entra — precargado, no fijo: sigue editable
  /// por si se cuenta distinto. Sin cierre de hoy (primera apertura del
  /// día), el campo arranca vacío como siempre.
  Future<void> _precargarFondoInicial() async {
    final sugerido = await fondoInicialSugeridoCentavos(widget.db);
    if (sugerido == null || !mounted) return;
    setState(() {
      _fondoInicialCtrl.text = formatearARS(sugerido).replaceAll('\$', '');
      _fondoPrecargado = true;
    });
  }

  /// Caja cigarrillos como campo editable (2026-09-12, el dueño: "para abrir
  /// caja se necesita: caja normal, caja cigarros, monto Mercado Pago") — el
  /// arrastre automático (Regla 10) sigue existiendo como default de
  /// `abrirSesion`, esto solo permite corregirlo desde el escritorio cuando
  /// hace falta (ej. reboot de la base, sin cierre anterior del que
  /// arrastrar). Null solo cuando nunca hubo un cierre anterior — una lata
  /// que de verdad cerró en 0 sí se sugiere.
  Future<void> _precargarLataInicial() async {
    final sugerido = await lataInicialSugeridoCentavos(widget.db);
    if (sugerido == null || !mounted) return;
    setState(() {
      _lataInicialCtrl.text = formatearARS(sugerido).replaceAll('\$', '');
      _lataPrecargada = true;
    });
  }

  /// Monto Mercado Pago (2026-09-12, el dueño: reboot de la base) — a
  /// diferencia del fondo inicial, se sugiere sin importar el día (la cuenta
  /// de Mercado Pago no se "cierra" a la noche como el cajón): lo último
  /// contado de verdad en el cierre anterior, editable igual que el fondo.
  /// Null solo cuando nunca hubo un cierre anterior (primera vez que se abre
  /// la base) — un MP contado en 0 de verdad sí se sugiere.
  Future<void> _precargarMpInicial() async {
    final sugerido = await mpQueSeArrastraCentavos(widget.db);
    if (sugerido == null || !mounted) return;
    setState(() {
      _mpInicialCtrl.text = formatearARS(sugerido).replaceAll('\$', '');
      _mpPrecargado = true;
    });
  }

  Future<void> _cargarUsuarios() async {
    final usuarios = await listarUsuariosActivos(widget.db);
    setState(() {
      _usuarios = usuarios;
      // Si ya había uno elegido, lo mantiene; si no, el primero de la lista.
      if (_usuarioId == null || !usuarios.any((u) => u.id == _usuarioId)) {
        _usuarioId = usuarios.isEmpty ? null : usuarios.first.id;
      }
      _agregandoUsuario = usuarios.isEmpty;
    });
  }

  Future<void> _agregarUsuario() async {
    final nombre = _nuevoUsuarioCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribí un nombre');
      return;
    }
    final id = await crearUsuario(widget.db, nombre);
    _nuevoUsuarioCtrl.clear();
    await _cargarUsuarios();
    setState(() {
      _usuarioId = id;
      _agregandoUsuario = false;
      _error = null;
    });
  }

  Future<void> _confirmar() async {
    if (_usuarioId == null) {
      setState(() => _error = 'Elegí o agregá quién abre la caja');
      return;
    }
    final int fondoInicial;
    try {
      fondoInicial = parsearARS(
        _fondoInicialCtrl.text.isEmpty ? '0' : _fondoInicialCtrl.text,
      );
    } on FormatException {
      setState(() => _error = 'Revisá los montos');
      return;
    }
    if (fondoInicial < 0) {
      setState(() => _error = 'El fondo inicial no puede ser negativo');
      return;
    }
    final int lataInicial;
    try {
      lataInicial = parsearARS(
        _lataInicialCtrl.text.isEmpty ? '0' : _lataInicialCtrl.text,
      );
    } on FormatException {
      setState(() => _error = 'Revisá los montos');
      return;
    }
    if (lataInicial < 0) {
      setState(() => _error = 'La caja de cigarrillos no puede ser negativa');
      return;
    }
    final int mpInicial;
    try {
      mpInicial = parsearARS(
        _mpInicialCtrl.text.isEmpty ? '0' : _mpInicialCtrl.text,
      );
    } on FormatException {
      setState(() => _error = 'Revisá los montos');
      return;
    }
    if (mpInicial < 0) {
      setState(() => _error = 'El monto de Mercado Pago no puede ser negativo');
      return;
    }

    // Regla 13 (revisar ganancia/reposición) ya no interrumpe acá — El dueño,
    // 2026-09-06: "en lugar de revisar ganancias, un apartado de reportes
    // para poder ver detalladamente todo" — esa revisión pasó a ser la
    // sección "Reportes" de la barra lateral, visitable cuando se quiera
    // (ver `lib/ui/reportes/`), ya no una pantalla forzada al abrir.
    try {
      await abrirSesion(
        widget.db,
        usuarioId: _usuarioId!,
        fondoInicialCentavos: fondoInicial,
        lataInicialCentavos: lataInicial,
        mpInicialCentavos: mpInicial,
      );
    } on SesionYaAbiertaException catch (e) {
      // Bloqueo directo (El dueño, 2026-09-19: "aislar los usuarios para que
      // no se pisen") — probablemente se abrió desde el celular hace un
      // instante; se avisa quién y a qué hora en vez de reabrir con estos
      // montos. Al cerrar el diálogo, `pantalla_venta.dart` vuelve a leer
      // `sesionAbierta` y encuentra la que abrió la otra persona.
      Usuario? usuario;
      for (final u in _usuarios) {
        if (u.id == e.sesion.usuarioAbrioId) {
          usuario = u;
          break;
        }
      }
      final nombre = usuario?.nombre;
      final hora = TimeOfDay.fromDateTime(e.sesion.fechaApertura);
      setState(
        () => _error =
            'Ya la abrió ${nombre ?? 'otro usuario'} a las ${hora.format(context)}',
      );
      return;
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _fondoInicialCtrl.dispose();
    _lataInicialCtrl.dispose();
    _mpInicialCtrl.dispose();
    _nuevoUsuarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // no se puede vender sin abrir la caja primero
      child: Modal(
        titulo: 'Abrir caja',
        contenido: _contenido(context),
        botones: [BotonPrimario(texto: 'Abrir caja', onPressed: _confirmar)],
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quién abre: elegir entre los que ya existen, o cargar uno nuevo
        // (la ayuda de fin de semana, por ejemplo) sin salir de este
        // diálogo — Regla 18 pide un selector, no un callejón sin salida
        // cuando todavía no hay nadie cargado.
        if (_usuarios.isNotEmpty && !_agregandoUsuario) ...[
          DropdownButton<int>(
            value: _usuarioId,
            isExpanded: true,
            items: [
              for (final u in _usuarios)
                DropdownMenuItem(value: u.id, child: Text(u.nombre)),
            ],
            onChanged: (v) => setState(() => _usuarioId = v),
          ),
          TextButton(
            onPressed: () => setState(() => _agregandoUsuario = true),
            child: const Text('Agregar otra persona'),
          ),
        ] else ...[
          if (_usuarios.isEmpty) const Text('Todavía no hay nadie cargado.'),
          CampoTexto(
            key: const Key('campo_nuevo_usuario'),
            controller: _nuevoUsuarioCtrl,
            autofocus: true,
            etiqueta: 'Nombre de quien abre',
            onSubmitted: (_) => _agregarUsuario(),
          ),
          const SizedBox(height: Espaciado.sm),
          Row(
            children: [
              if (_usuarios.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _agregandoUsuario = false),
                  child: const Text('Cancelar'),
                ),
              const Spacer(),
              BotonPrimario(texto: 'Agregar', onPressed: _agregarUsuario),
            ],
          ),
        ],

        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_fondo_inicial'),
          controller: _fondoInicialCtrl,
          etiqueta: 'Fondo inicial (caja normal)',
          onSubmitted: (_) => _confirmar(),
        ),
        if (_fondoPrecargado) ...[
          const SizedBox(height: Espaciado.xs),
          Text(
            'Precargado con lo que quedó en el cajón del turno anterior — se puede corregir.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
        ],

        if (moduloActivo(Modulo.cajaAparte)) ...[
          const SizedBox(height: Espaciado.lg),
          CampoPlata(
            key: const Key('campo_lata_inicial'),
            controller: _lataInicialCtrl,
            etiqueta: 'Caja cigarrillos',
            onSubmitted: (_) => _confirmar(),
          ),
          if (_lataPrecargada) ...[
            const SizedBox(height: Espaciado.xs),
            Text(
              'Precargado con lo que quedó en la lata del cierre anterior — se puede corregir.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
          ],
        ],

        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_mp_inicial'),
          controller: _mpInicialCtrl,
          etiqueta: 'Monto Mercado Pago',
          onSubmitted: (_) => _confirmar(),
        ),
        if (_mpPrecargado) ...[
          const SizedBox(height: Espaciado.xs),
          Text(
            'Precargado con lo último contado en Mercado Pago — se puede corregir.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
        ],

        if (_avisoReposicion.isNotEmpty) ...[
          const SizedBox(height: Espaciado.lg),
          Text('Para separar:', style: TextStyle(fontWeight: Pesos.medium)),
          for (final item in _avisoReposicion)
            Text('${item.nombre}: ${formatearARS(item.montoCentavos)}'),
        ],
        if (_error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(_error!, style: TextStyle(color: context.colores.error)),
        ],
      ],
    );
  }
}
