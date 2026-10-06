// Configuración › Asistente IA: cargar la clave gratuita de Google (Gemini) y probar que anda. La clave queda solo en este
// equipo (ver `servicios/gemini.dart`). Con el kit del mock v4 (`cfgBody('ia')`, 2026-10-06).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../servicios/gemini.dart';
import '../kit/kit.dart';

/// Elige con qué modelo de Google se consulta (por defecto el más barato). Se guarda al instante; la clave no se toca. Lo usa también el
/// lector de facturas, para probar modelos sin salir de ahí.
class SelectorModeloIa extends StatefulWidget {
  const SelectorModeloIa({super.key, this.onCambio});

  final VoidCallback? onCambio;

  @override
  State<SelectorModeloIa> createState() => _SelectorModeloIaState();
}

class _SelectorModeloIaState extends State<SelectorModeloIa> {
  @override
  Widget build(BuildContext context) {
    final actual = ClaveGemini.modelo ?? modeloGeminiPorDefecto;
    // Un modelo guardado que ya no está en la lista (se retiró) se sigue mostrando, para poder cambiarlo.
    final modelos = [if (!modelosGemini.contains(actual)) actual, ...modelosGemini];
    return DropdownMenu<String>(
      key: ValueKey('selector_modelo_$actual'),
      width: 460,
      label: const Text('Modelo de la IA'),
      initialSelection: actual,
      dropdownMenuEntries: [for (final m in modelos) DropdownMenuEntry(value: m, label: etiquetaDeModelo(m))],
      onSelected: (m) async {
        if (m == null || m == actual) return;
        await ClaveGemini.elegirModelo(m);
        if (!mounted) return;
        setState(() {});
        widget.onCambio?.call();
      },
    );
  }
}

class SeccionAsistenteIa extends StatefulWidget {
  const SeccionAsistenteIa({super.key, this.client});

  /// Solo para tests: evita llamar a Google de verdad.
  final http.Client? client;

  @override
  State<SeccionAsistenteIa> createState() => _SeccionAsistenteIaState();
}

class _SeccionAsistenteIaState extends State<SeccionAsistenteIa> {
  late final TextEditingController _clave = TextEditingController(text: ClaveGemini.valor ?? '');
  bool _probando = false;

  /// Null = todavía no se probó; vacío = anduvo; con texto = el motivo del fallo.
  String? _resultado;

  @override
  void dispose() {
    _clave.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    setState(() => _probando = true);
    final motivo = await probarYGuardarClave(_clave.text, client: widget.client);
    if (!mounted) return;
    setState(() {
      _probando = false;
      _resultado = motivo ?? '';
    });
  }

  Future<void> _quitar() async {
    await ClaveGemini.guardar(null);
    if (!mounted) return;
    setState(() {
      _clave.clear();
      _resultado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final r = _resultado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Nota(
          texto: 'Google Gemini sugiere promos y lee facturas. Solo sugiere: no cambia nada sin que lo confirmes. La clave se '
              'guarda solo en esta PC.',
        ),
        const SizedBox(height: 14),
        Campo(etiqueta: 'Clave de la API de Google (Gemini)', controller: _clave, pista: 'AIza…', obscuro: true, onSubmitted: (_) => _probar()),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Btn(_probando ? 'Probando…' : 'Guardar y probar', variante: VarBtn.blue, onTap: _probando ? null : _probar),
            Btn('Quitar clave', variante: VarBtn.out, onTap: _probando ? null : _quitar),
          ],
        ),
        if (r != null) ...[
          const SizedBox(height: 12),
          Text(
            r.isEmpty
                ? (ClaveGemini.configurada ? 'Anda: la clave es válida y quedó guardada (modelo ${ClaveGemini.modelo}).' : 'Clave quitada.')
                : '$r (no se guardó)',
            style: estilo(15, 500, color: r.isEmpty ? p.g : p.b),
          ),
        ],
        const SizedBox(height: 14),
        const Nota(
          tono: TonoMock.w,
          texto: 'Se saca en aistudio.google.com/apikey con tu cuenta de Google. Ojo: en el plan gratis Google puede usar lo que '
              'se le manda para mejorar sus productos. Por eso el sistema solo le manda productos, precios y totales — nunca '
              'nombres de clientes ni de fiados.',
        ),
        if (ClaveGemini.configurada) ...[
          const SizedBox(height: 18),
          Align(alignment: Alignment.centerLeft, child: SelectorModeloIa(onCambio: () => setState(() {}))),
        ],
      ],
    );
  }
}
