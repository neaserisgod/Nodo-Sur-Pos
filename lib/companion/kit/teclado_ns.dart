// Saber si el teclado está abierto, y redibujar cuando se abre o se cierra. Se mira la vista y no el MediaQuery: el
// Scaffold que tiene la barra de pestañas ya le descuenta el teclado a su cuerpo, así que adentro no se ve.
import 'package:flutter/widgets.dart';

class ConTecladoNs extends StatefulWidget {
  const ConTecladoNs({super.key, required this.builder});

  final Widget Function(BuildContext context, bool abierto) builder;

  @override
  State<ConTecladoNs> createState() => _ConTecladoNsState();
}

class _ConTecladoNsState extends State<ConTecladoNs> with WidgetsBindingObserver {
  bool _abierto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _abierto = View.of(context).viewInsets.bottom > 0;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final abierto = View.of(context).viewInsets.bottom > 0;
    if (abierto != _abierto) setState(() => _abierto = abierto);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _abierto);
}
