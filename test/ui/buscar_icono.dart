// Los íconos de la PC se dibujan con `IconoPlz` (trazo del mock) y no siempre con `Icon`: este buscador encuentra los dos.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/tema/iconos.dart';

Finder buscarIcono(IconData icono) => find.byWidgetPredicate(
  (w) => (w is IconoPlz && w.icono == icono) || (w is Icon && w.icon == icono),
  description: 'ícono $icono',
);
