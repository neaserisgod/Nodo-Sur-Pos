// Las preguntas frecuentes del bot (El dueño, 2026-10-21: "quiero que cubra todas las posibles preguntas acerca de las
// hamburguesas"). Se abre desde Más › Bot de WhatsApp. Lo que se carga acá va a la configuración del bot (`preguntas`,
// `respuestas.pagos` / `respuestas.envios`, `textos.emoji`); las reglas viven en `domain/preguntas_bot.dart`.
//
// Al guardar se vuelve a leer la configuración del sitio y se pone encima: mientras esta pantalla estaba abierta, la app pudo
// mandarle al bot la carta, el horario o el estado de la cocina, y eso no se pisa.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositorio_servicios.dart' show listarProductosDeVenta, listarServicios;
import '../../domain/preguntas_bot.dart';
import '../../servicios/acceso_bot.dart';
import '../base_local.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';

class PantallaPreguntasBotNs extends StatefulWidget {
  const PantallaPreguntasBotNs({super.key, required this.acceso, this.nombresCarta});

  final AccesoBot acceso;

  /// Para avisar si una clave es una palabra de la carta. Null: se leen de la base del celular. Para tests.
  final List<String>? nombresCarta;

  @override
  State<PantallaPreguntasBotNs> createState() => _PantallaPreguntasBotNsState();
}

class _PantallaPreguntasBotNsState extends State<PantallaPreguntasBotNs> {
  bool _cargando = true;
  String? _error;
  bool _sinConfig = false;
  List<PreguntaBot> _preguntas = const [];
  List<String> _carta = const [];
  final _pagos = TextEditingController();
  final _envios = TextEditingController();
  final _emoji = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _pagos.dispose();
    _envios.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final config = (await widget.acceso.config()).config;
      final p = preguntasDeConfig(config);
      final carta = widget.nombresCarta ?? await _nombresDeLaCarta();
      if (!mounted) return;
      setState(() {
        _sinConfig = config == null;
        _preguntas = p.preguntas;
        _pagos.text = p.pagos;
        _envios.text = p.envios;
        _emoji.text = p.emoji;
        _carta = carta;
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Los nombres de la carta, para los avisos. Sin base (la app conectada a una PC) no hay avisos de carta: no es grave.
  static Future<List<String>> _nombresDeLaCarta() async {
    try {
      final db = baseLocalCompanion();
      final platos = await listarServicios(db, conManoDeObra: false);
      final otros = await listarProductosDeVenta(db);
      return [for (final s in platos) s.producto.nombre, for (final p in otros) p.nombre];
    } catch (_) {
      return const [];
    }
  }

  PreguntasDelBot get _actual => PreguntasDelBot(preguntas: _preguntas, pagos: _pagos.text, envios: _envios.text, emoji: _emoji.text);

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final fresca = (await widget.acceso.config()).config;
      if (fresca == null) throw StateError('Primero guardá la configuración del bot (los números) en Más › Bot de WhatsApp.');
      await widget.acceso.guardarConfig(configConPreguntas(fresca, _actual));
      if (mounted) mostrarAvisoNs(context, 'Guardado. El bot lo toma solo, sin reiniciarlo.');
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo guardar: ${mensajeDeError(e)}', largo: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _pegar() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text ?? '';
    final b = leerBloquePreguntas(texto);
    if (!mounted) return;
    if (b.preguntas.isEmpty && b.pagos == null && b.envios == null && b.emoji == null) {
      mostrarAvisoNs(context, 'No encontré preguntas en lo que copiaste. Copiá el bloque entero (con "claves:" y "respuesta:").', largo: true);
      return;
    }
    final seguir = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Pegar ${b.preguntas.length} ${b.preguntas.length == 1 ? 'pregunta' : 'preguntas'}',
        texto: 'Las que ya tenés con el mismo título se reemplazan; las nuevas se agregan.'
            '${b.errores.isEmpty ? '' : '\n\nNo se pudieron leer:\n${b.errores.join('\n')}'}',
        botones: [
          BotonNs.primario(ctx, 'Pegar', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (seguir != true || !mounted) return;
    final r = sumarBloque(_actual, b);
    setState(() {
      _preguntas = r.preguntas;
      _pagos.text = r.pagos;
      _envios.text = r.envios;
      _emoji.text = r.emoji;
    });
    mostrarAvisoNs(context, 'Listo. Revisalas y tocá Guardar.');
  }

  Future<void> _editar([int? i]) async {
    final existente = i == null ? null : _preguntas[i];
    final r = await mostrarHojaNs<_ResultadoEditar>(
      context,
      builder: (ctx) => _HojaPregunta(existente: existente, carta: _carta),
    );
    if (r == null || !mounted) return;
    setState(() {
      final lista = [..._preguntas];
      if (r.borrar) {
        if (i != null) lista.removeAt(i);
      } else if (i == null) {
        lista.add(r.pregunta!);
      } else {
        lista[i] = r.pregunta!;
      }
      _preguntas = lista;
    });
  }

  Widget _seccion(String texto) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs(texto));

  @override
  Widget build(BuildContext context) {
    return PaginaNs(
      titulo: 'Preguntas del bot',
      cuerpo: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_error != null)
                  InfoNs(_error!, tono: TonoNs.bad)
                else if (_sinConfig)
                  const InfoNs('Primero guardá la configuración del bot (los números) en Más › Bot de WhatsApp.', tono: TonoNs.warn)
                else ...[
                  const InfoNs(
                    'El bot contesta solo cuando el cliente escribe una de las frases. Usá frases de pregunta ("qué carne", "tienen cerveza") '
                    'y no palabras sueltas de la carta, que se confunden con un pedido.',
                  ),
                  _seccion('Preguntas (${_preguntas.length})'),
                  for (var i = 0; i < _preguntas.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaFilaNs(
                        key: Key('pregunta_$i'),
                        titulo: _preguntas[i].nombre,
                        subtitulo: _preguntas[i].respuesta.split('\n').first,
                        icono: avisosDeClave(_preguntas[i].claves, nombresCarta: _carta).isEmpty ? IconoNs.portapapeles : IconoNs.alertaCirculo,
                        onTap: () => _editar(i),
                      ),
                    ),
                  if (_preguntas.isEmpty) const InfoNs('Todavía no cargaste preguntas.'),
                  const SizedBox(height: 8),
                  KeyedSubtree(key: const Key('pregunta_agregar'), child: BotonNs.secundario(context, 'Agregar una pregunta', () => _editar(), icono: IconoNs.masMas)),
                  const SizedBox(height: 8),
                  KeyedSubtree(key: const Key('pregunta_pegar'), child: BotonNs.secundario(context, 'Pegar preguntas copiadas', _pegar, icono: IconoNs.portapapeles)),
                  _seccion('Respuestas de siempre'),
                  CampoNs(key: const Key('pregunta_pagos'), etiqueta: '¿Cómo se paga? (vacío: lo contesta una persona)', controller: _pagos, lineas: 4),
                  const SizedBox(height: 10),
                  CampoNs(key: const Key('pregunta_envios'), etiqueta: '¿Hacen envíos? (vacío: el bot dice tus zonas)', controller: _envios, lineas: 4),
                  const SizedBox(height: 10),
                  CampoNs(key: const Key('pregunta_emoji'), etiqueta: 'Emoji del local en el menú (ej: 🍔)', controller: _emoji, placeholder: '🍔'),
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: const Key('pregunta_guardar'),
                    child: BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar', _guardando ? null : _guardar, habilitado: !_guardando),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

class _ResultadoEditar {
  const _ResultadoEditar({this.pregunta, this.borrar = false});
  final PreguntaBot? pregunta;
  final bool borrar;
}

class _HojaPregunta extends StatefulWidget {
  const _HojaPregunta({required this.existente, required this.carta});
  final PreguntaBot? existente;
  final List<String> carta;

  @override
  State<_HojaPregunta> createState() => _HojaPreguntaState();
}

class _HojaPreguntaState extends State<_HojaPregunta> {
  late final _titulo = TextEditingController(text: widget.existente?.titulo ?? '');
  late final _claves = TextEditingController(text: widget.existente?.claves.join(', ') ?? '');
  late final _respuesta = TextEditingController(text: widget.existente?.respuesta ?? '');
  List<String> _problemas = const [];

  @override
  void dispose() {
    _titulo.dispose();
    _claves.dispose();
    _respuesta.dispose();
    super.dispose();
  }

  PreguntaBot get _pregunta => PreguntaBot(
        titulo: _titulo.text.trim(),
        claves: [for (final k in _claves.text.split(',')) if (k.trim().isNotEmpty) k.trim()],
        respuesta: _respuesta.text.trim(),
      );

  void _guardar() {
    final p = _pregunta;
    final malos = problemasDePregunta(p);
    if (malos.isNotEmpty) {
      setState(() => _problemas = malos);
      return;
    }
    Navigator.of(context).pop(_ResultadoEditar(pregunta: p));
  }

  @override
  Widget build(BuildContext context) {
    final avisos = avisosDeClave(_pregunta.claves, nombresCarta: widget.carta);
    return HojaNs(
      titulo: widget.existente == null ? 'Nueva pregunta' : 'Editar pregunta',
      bloques: [
        CampoNs(key: const Key('hoja_pregunta_titulo'), etiqueta: 'Título (para vos)', controller: _titulo, placeholder: '¿De qué es la carne?'),
        const SizedBox(height: 10),
        CampoNs(
          key: const Key('hoja_pregunta_claves'),
          etiqueta: 'Frases que la disparan, separadas por coma',
          controller: _claves,
          placeholder: 'que carne, de que es la carne',
          lineas: 3,
          onChanged: (_) => setState(() {}),
        ),
        for (final a in avisos) Padding(padding: const EdgeInsets.only(top: 6), child: InfoNs(a, tono: TonoNs.warn)),
        const SizedBox(height: 10),
        CampoNs(key: const Key('hoja_pregunta_respuesta'), etiqueta: 'Lo que contesta el bot', controller: _respuesta, lineas: 6),
        for (final m in _problemas) Padding(padding: const EdgeInsets.only(top: 6), child: InfoNs(m, tono: TonoNs.bad)),
      ],
      botones: [
        BotonNs.primario(context, 'Listo', _guardar),
        if (widget.existente != null) BotonNs.peligroSuave(context, 'Borrar', () => Navigator.of(context).pop(const _ResultadoEditar(borrar: true))),
        BotonNs.secundario(context, 'Cancelar', () => Navigator.of(context).pop()),
      ],
    );
  }
}
