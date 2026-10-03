// El cierre del primer recorrido: la cuenta ya entró y el perfil quedó guardado. Un momento corto con el nombre de la
// persona antes de abrir el menú, con el mismo punto verde que termina la bienvenida (acá crece hasta ser el tilde).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import '../emparejamiento.dart';
import '../pantalla_menu_companion.dart';
import '../tema/tema_companion.dart';
import 'aparecer.dart';
import 'marca_nodo_sur.dart';

class PantallaListo extends StatefulWidget {
  const PantallaListo({super.key, this.nombre, this.alSeguir});

  /// Solo para tests: el nombre a mostrar. En la app sale del perfil que se acaba de guardar.
  final String? nombre;

  /// Qué hacer con "Ir al inicio"; por defecto abre el menú.
  final void Function(BuildContext context)? alSeguir;

  @override
  State<PantallaListo> createState() => _PantallaListoState();
}

class _PantallaListoState extends State<PantallaListo> with SingleTickerProviderStateMixin {
  late final AnimationController _reloj = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  String? _nombre;

  @override
  void initState() {
    super.initState();
    _nombre = widget.nombre;
    if (_nombre == null) {
      leerUsuario().then((u) {
        if (mounted && u != null) setState(() => _nombre = u.nombre);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reloj.isAnimating || _reloj.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reloj.value = 1;
    } else {
      _reloj.forward();
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  void _seguir() {
    if (widget.alSeguir != null) {
      widget.alSeguir!(context);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PantallaMenuCompanion()));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nombre = _nombre?.trim() ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.xl),
          child: Column(
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _reloj,
                builder: (context, _) {
                  // El punto verde crece hasta ser el círculo del tilde, y el tilde se dibuja después.
                  final crece = const Cubic(0.2, 0, 0, 1).transform(const Interval(0, 0.6).transform(_reloj.value));
                  final tilde = Curves.easeOut.transform(const Interval(0.45, 1).transform(_reloj.value));
                  final lado = 14 + (88 - 14) * crece;
                  return SizedBox(
                    width: 88,
                    height: 88,
                    child: Center(
                      child: Container(
                        width: lado,
                        height: lado,
                        decoration: BoxDecoration(
                          color: Color.lerp(verdeMarca, const Color(0xFF1E8E3E), crece),
                          shape: BoxShape.circle,
                        ),
                        child: Opacity(
                          opacity: tilde,
                          child: Transform.scale(scale: 0.6 + 0.4 * tilde, child: const Icon(Icons.check_rounded, color: Colors.white, size: 46)),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: Espaciado.xl),
              Aparecer(
                orden: 3,
                child: Text(
                  nombre.isEmpty ? 'Listo.' : 'Listo, $nombre.',
                  key: const Key('listo-titulo'),
                  textAlign: TextAlign.center,
                  style: textTheme.displayLarge,
                ),
              ),
              const SizedBox(height: Espaciado.md),
              Aparecer(
                orden: 4,
                child: Text(
                  'Este celular ya está listo para vender.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario),
                ),
              ),
              const Spacer(),
              Aparecer(
                orden: 5,
                child: SizedBox(
                  width: double.infinity,
                  height: alturaControlCompanion,
                  child: FilledButton(key: const Key('listo-seguir'), onPressed: _seguir, child: const Text('Ir al inicio')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
