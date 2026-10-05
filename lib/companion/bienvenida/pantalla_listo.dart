// El cierre del primer recorrido (mock 02k/02l): la cuenta ya entró y el perfil quedó guardado. "Listo, Ana." con la tarjeta
// oscura de la cuenta de Google antes de abrir el menú (o "Configurar mi negocio", si es el dueño de un negocio nuevo).

import 'package:flutter/material.dart';

import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../pantalla_menu_companion.dart';
import '../sync_nube_companion.dart';

class PantallaListo extends StatefulWidget {
  const PantallaListo({super.key, this.nombre, this.email, this.alSeguir, this.textoBoton = 'Ir al inicio'});

  /// "Configurar mi negocio" cuando lo que sigue es el asistente del dueño nuevo.
  final String textoBoton;

  /// Solo para tests: el nombre y el mail a mostrar. En la app salen del perfil que se acaba de guardar y de la cuenta.
  final String? nombre;
  final String? email;

  /// Qué hacer con "Ir al inicio"; por defecto abre el menú.
  final void Function(BuildContext context)? alSeguir;

  @override
  State<PantallaListo> createState() => _PantallaListoState();
}

class _PantallaListoState extends State<PantallaListo> {
  String? _nombre;
  String? _email;

  @override
  void initState() {
    super.initState();
    _nombre = widget.nombre;
    _email = widget.email;
    if (_nombre == null) {
      leerUsuario().then((u) {
        if (mounted && u != null) setState(() => _nombre = u.nombre);
      });
    }
    if (_email == null && widget.nombre == null) _leerMail();
  }

  Future<void> _leerMail() async {
    try {
      final cuenta = await (await syncNubeDelCelular()).cuenta();
      if (mounted && cuenta != null) setState(() => _email = cuenta.email);
    } catch (_) {
      // Sin cuenta a mano no se muestra el mail.
    }
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
    final nombre = _nombre?.trim() ?? '';
    return PaginaArranqueNs(
      titulo: nombre.isEmpty ? 'Listo.' : 'Listo, $nombre.',
      claveTitulo: const Key('listo-titulo'),
      bajada: 'Este celular ya está listo para vender.',
      cuerpo: [HeroHojaNs(rotulo: 'Cuenta de Google', cifra: nombre, apoyo: _email ?? '')],
      botones: [KeyedSubtree(key: const Key('listo-seguir'), child: BotonNs.primario(context, widget.textoBoton, _seguir))],
    );
  }
}
