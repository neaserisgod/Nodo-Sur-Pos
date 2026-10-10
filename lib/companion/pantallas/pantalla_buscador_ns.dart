// Buscador de funciones, tal cual el mock (docs/03 C5 y docs/06): campo arriba,
// sugerencias, "Ver todas las funciones" y resultados con su ruta. Tocar un
// resultado navega directo a esa función.

import 'package:flutter/material.dart';

import '../app_ns.dart';
import '../funciones_ns.dart';
import '../kit/kit_ns.dart';
import '../../servicios/modulos_activos.dart' show esNegocioDeServicios;

class PantallaBuscadorNs extends StatefulWidget {
  const PantallaBuscadorNs({super.key, required this.origen});

  /// Pestaña desde la que se abrió: al volver (‹) se regresa a ella.
  final PestaniaNs origen;

  @override
  State<PantallaBuscadorNs> createState() => _PantallaBuscadorNsState();
}

class _PantallaBuscadorNsState extends State<PantallaBuscadorNs> {
  final _ctrl = TextEditingController();
  bool _todas = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _poner(String q) => setState(() {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
  });

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    final consulta = _ctrl.text;
    final hayTokens = normalizarNs(consulta).split(RegExp(r'\s+')).any((t) => t.isNotEmpty);
    final servicios = esNegocioDeServicios();
    final resultados = hayTokens
        ? [for (final f in buscarFunciones(consulta, servicios: servicios)) ResultadoFuncion(f)]
        : (_todas ? todasLasFunciones(servicios: servicios) : <ResultadoFuncion>[]);
    final intro = !hayTokens
        ? (_todas ? 'Todo lo que hace la app, ordenado por sección.' : 'Escribí lo que querés hacer o tocá una idea.')
        : resultados.isNotEmpty
        ? '${resultados.length} ${resultados.length == 1 ? 'resultado' : 'resultados'} para "${consulta.trim()}"'
        : 'No encontramos nada para "${consulta.trim()}". Probá con otra palabra o elegí una sugerencia.';
    final sugerir = (!hayTokens && !_todas) || (hayTokens && resultados.isEmpty);
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    BotonCircularNs(icono: IconoNs.volver, onTap: () => Navigator.of(context).maybePop(), etiqueta: 'Volver', tamanioIcono: 18, grosor: 2.4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BuscadorNs(
                        controller: _ctrl,
                        placeholder: 'Qué querés hacer o cambiar',
                        autofoco: false,
                        onChanged: (_) => setState(() {}),
                        conBorrar: consulta.isNotEmpty,
                        onBorrar: () => _poner(''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(intro, style: estiloNs(15, altura: 1.4, color: ns.mute))),
                      const SizedBox(height: 8),
                      if (sugerir)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 6),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final s in servicios ? sugerenciasFuncionesServicios : sugerenciasFunciones) ChipNs(texto: s, activo: false, onTap: () => _poner(s))]),
                        ),
                      if (!hayTokens && !_todas)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: PresionNs(
                            onTap: () => setState(() => _todas = true),
                            etiqueta: 'Ver todas las funciones',
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 60),
                              padding: const EdgeInsets.symmetric(horizontal: 22),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: TokensNs.contorno, width: 1.5)),
                              child: Row(
                                children: [
                                  Expanded(child: Text('Ver todas las funciones', style: estiloNs(16, peso: FontWeight.w600, color: ns.ink))),
                                  IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.mute, grosor: 2.2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      for (final r in resultados) ...[
                        if (r.encabezado != null) Padding(padding: const EdgeInsets.only(top: 10, bottom: 8), child: SeccionNs(r.encabezado!)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TarjetaFilaNs(
                            titulo: r.funcion.titulo,
                            subtitulo: r.funcion.ruta,
                            icono: r.funcion.icono,
                            minAlto: 68,
                            padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
                            tamanioTitulo: 16,
                            onTap: () {
                              Navigator.of(context).pop();
                              app.ejecutarFuncion(r.funcion.accion);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
