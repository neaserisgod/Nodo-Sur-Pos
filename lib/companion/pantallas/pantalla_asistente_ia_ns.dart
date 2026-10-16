// Asistente con IA de Nodo Sur Servicios (El dueño, 2026-10-16: "responde y actúa", `domain/asistente_ia.dart`). Se le pregunta
// en palabras; contesta con los datos del negocio y, si hace falta, propone acciones que se hacen recién cuando la persona toca
// la acción y confirma. Usa la clave de Configuración › Asistente IA.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositorio_asistente_ia.dart';
import '../../domain/asistente_ia.dart';
import '../../servicios/asistente_ia.dart';
import '../../servicios/gemini.dart';
import '../../servicios/registro_errores.dart' show registrarSiNoEsDeRed;
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import '../pantalla_configuracion_companion.dart';

const sugerenciasAsistenteIa = [
  '¿Qué huecos tengo mañana?',
  '¿Cómo vengo este mes?',
  '¿Quién viene hoy?',
  'Anotá un gasto de 2000 de café',
];

class _Intercambio {
  _Intercambio(this.pregunta);
  final String pregunta;
  RespuestaIa? respuesta;
  String? error;

  /// Las acciones (por posición) que ya se hicieron.
  final Set<int> hechas = {};
}

class PantallaAsistenteIaNs extends StatefulWidget {
  const PantallaAsistenteIaNs({super.key});

  @override
  State<PantallaAsistenteIaNs> createState() => _PantallaAsistenteIaNsState();
}

class _PantallaAsistenteIaNsState extends State<PantallaAsistenteIaNs> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _charla = <_Intercambio>[];
  bool _pensando = false;
  bool _haciendo = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alFinal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _preguntar(String texto) async {
    final pregunta = texto.trim();
    if (pregunta.isEmpty || _pensando) return;
    final antes = [
      for (final i in _charla)
        if (i.respuesta != null) (pregunta: i.pregunta, respuesta: i.respuesta!.texto),
    ];
    final actual = _Intercambio(pregunta);
    setState(() {
      _charla.add(actual);
      _pensando = true;
      _ctrl.clear();
    });
    _alFinal();
    ClienteGemini? cliente;
    try {
      final datos = await datosParaAsistenteIa(baseLocalCompanion());
      cliente = ClienteGemini.guardado();
      actual.respuesta = await preguntarAlAsistente(cliente, pregunta, datos, antes: antes);
    } on ErrorGemini catch (e) {
      actual.error = e.mensaje;
    } catch (e, st) {
      unawaited(registrarSiNoEsDeRed('Asistente IA', e, st));
      actual.error = mensajeDeError(e);
    } finally {
      cliente?.close();
    }
    if (!mounted) return;
    setState(() => _pensando = false);
    _alFinal();
  }

  Future<void> _hacer(_Intercambio intercambio, int indice, AccionIa accion) async {
    final app = AppNs.of(context);
    if (accion is IrAIa) {
      Navigator.of(context).pop();
      app.irAPestania(switch (accion.pantalla) {
        PantallaIa.agenda => PestaniaNs.inicio,
        PantallaIa.cobrar => PestaniaNs.vender,
        PantallaIa.caja => PestaniaNs.caja,
      });
      return;
    }
    final usuario = app.usuarioId;
    if (usuario == null) {
      mostrarAvisoNs(context, 'Falta elegir usuario');
      return;
    }
    final ok = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Lo hago?',
        texto: describirAccionIa(accion),
        botones: [
          BotonNs.primario(ctx, 'Sí, hacerlo', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'No', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _haciendo = true);
    try {
      final aviso = await ejecutarAccionIa(baseLocalCompanion(), accion, usuarioId: usuario);
      intercambio.hechas.add(indice);
      avisarCambiosCompanion();
      unawaited(app.refrescar());
      if (mounted) mostrarAvisoNs(context, aviso);
    } on ArgumentError catch (e) {
      if (mounted) mostrarAvisoNs(context, '${e.message}', largo: true);
    } catch (e, st) {
      unawaited(registrarSiNoEsDeRed('Acción del asistente IA', e, st));
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
    } finally {
      if (mounted) setState(() => _haciendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final conClave = ClaveGemini.configurada;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 16),
            child: Column(
              children: [
                CabeceraSubNs(titulo: 'Asistente', onVolver: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      if (!conClave) ...[
                        const InfoNs('Para usar el asistente cargá la clave de la IA en Más › Configuración › Asistente IA.', tono: TonoNs.warn, icono: IconoNs.alerta),
                        const SizedBox(height: 12),
                        BotonNs.secundario(
                          context,
                          'Ir a Configuración',
                          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PantallaConfiguracionCompanion())).then((_) {
                            if (mounted) setState(() {});
                          }),
                          icono: IconoNs.ajustes,
                        ),
                      ] else if (_charla.isEmpty) ...[
                        Text(
                          'Preguntame por tu agenda, los huecos o lo que cobraste. También puedo dar, mover o cancelar turnos y anotar gastos: '
                          'te muestro qué voy a hacer y lo hago cuando confirmás.',
                          style: estiloNs(15, altura: 1.4, color: ns.mute),
                        ),
                        const SizedBox(height: 14),
                        Wrap(spacing: 8, runSpacing: 8, children: [for (final s in sugerenciasAsistenteIa) ChipNs(texto: s, activo: false, onTap: () => _preguntar(s))]),
                      ],
                      for (final i in _charla) ..._intercambio(context, i),
                      if (_pensando) ...[
                        const SizedBox(height: 12),
                        Text('Pensando…', style: estiloNs(15, color: ns.mute)),
                      ],
                    ],
                  ),
                ),
                if (conClave) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CampoNs(
                          key: const Key('asistente_ia_campo'),
                          etiqueta: '',
                          controller: _ctrl,
                          placeholder: 'Preguntá o pedí algo',
                          habilitado: !_pensando,
                          onSubmit: _preguntar,
                        ),
                      ),
                      const SizedBox(width: 10),
                      BotonCircularNs(
                        key: const Key('asistente_ia_enviar'),
                        icono: IconoNs.chispa,
                        etiqueta: 'Preguntar',
                        tamanio: 52,
                        fondo: ns.prim,
                        colorIcono: TokensNs.blanco,
                        onTap: _pensando ? null : () => _preguntar(_ctrl.text),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _intercambio(BuildContext context, _Intercambio i) {
    final ns = context.ns;
    final r = i.respuesta;
    return [
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
          child: Text(i.pregunta, style: estiloNs(15, altura: 1.4, color: ns.ink)),
        ),
      ),
      const SizedBox(height: 10),
      if (i.error != null) InfoNs(i.error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      if (r != null) ...[
        Text(r.texto, style: estiloNs(16, altura: 1.45, color: ns.ink)),
        for (final (n, a) in r.acciones.indexed) ...[
          const SizedBox(height: 10),
          i.hechas.contains(n)
              ? InfoNs('Hecho: ${describirAccionIa(a)}', tono: TonoNs.good, icono: IconoNs.tilde)
              : TarjetaFilaNs(
                  titulo: describirAccionIa(a),
                  subtitulo: a is IrAIa ? null : 'Tocá para revisarlo y confirmar',
                  icono: switch (a) {
                    DarTurnoIa() || MoverTurnoIa() || CancelarTurnoIa() => IconoNs.calendario,
                    GastoIa() => IconoNs.intercambio,
                    IrAIa() => IconoNs.chevron,
                  },
                  onTap: _haciendo ? null : () => _hacer(i, n, a),
                ),
        ],
        if (r.descartadas > 0) ...[
          const SizedBox(height: 10),
          InfoNs(
            r.descartadas == 1
                ? 'La IA propuso algo que no se puede hacer (un horario pasado, un turno que no existe…). Pedilo de nuevo con más detalle.'
                : 'La IA propuso ${r.descartadas} cosas que no se pueden hacer. Pedilo de nuevo con más detalle.',
            tono: TonoNs.warn,
          ),
        ],
      ],
    ];
  }
}
