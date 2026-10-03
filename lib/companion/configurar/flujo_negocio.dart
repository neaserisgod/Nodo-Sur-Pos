// Abre "Configurá tu negocio" con lo real detrás: la base local del celular, la cámara, el alta de productos de
// siempre (`ServicioCompanion.crearProducto`, con su rastro de stock) y horsepos.com/negocio en el navegador.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositorio_productos.dart' as repo_productos;
import '../../servicios/marca_actual.dart';
import '../base_local.dart';
import '../emparejamiento.dart';
import '../escanear_codigo.dart';
import '../pantalla_entrar_con_cuenta.dart';
import '../pantalla_menu_companion.dart';
import 'asistente_negocio.dart';
import 'negocio_nuevo.dart';

/// La página del negocio en la web: ahí el dueño conecta Mercado Pago y la terminal, e invita a su equipo.
final urlPaginaNegocio = Uri.parse('https://horsepos.com/negocio/');

/// [desdeInicio]: se retoma desde la tarjeta de Inicio, así que al terminar se vuelve a Inicio en vez de armar el menú.
Future<void> abrirAsistenteNegocio(BuildContext context, {PasoNegocio paso = PasoNegocio.negocio, bool desdeInicio = false}) async {
  final db = baseLocalCompanion();
  final categorias = [for (final c in await repo_productos.listarCategorias(db)) c.nombre];
  if (!context.mounted) return;
  final marca = marcaActual.value;
  final ruta = MaterialPageRoute<void>(
    builder: (_) => AsistenteNegocio(
      pasoInicial: paso,
      nombreInicial: marca.configurada ? marca.nombreComercio : '',
      categoriasExistentes: categorias,
      alCompletarPaso: (p) => marcarPasoHecho(p),
      alGuardarNegocio: (nombre, rubro) => guardarNegocio(db, nombre: nombre, rubro: rubro),
      alEscanear: escanearCodigo,
      alGuardarProducto: (p) => _guardarProducto(p),
      alAbrirWeb: (_) => launchUrl(urlPaginaNegocio, mode: LaunchMode.externalApplication),
      alTerminar: (context, _) {
        final navigator = Navigator.of(context);
        if (desdeInicio) {
          navigator.pop();
        } else {
          navigator.pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const PantallaMenuCompanion()), (r) => false);
        }
      },
    ),
  );
  final navigator = Navigator.of(context);
  if (desdeInicio) {
    await navigator.push(ruta);
  } else {
    await navigator.pushAndRemoveUntil(ruta, (r) => false);
  }
}

/// El producto de práctica entra por el mismo alta que cualquier otro. Si el código ya estaba cargado (alguien probó
/// antes con el mismo producto) no se duplica: se da por hecho.
Future<void> _guardarProducto(ProductoDePrueba p) async {
  final db = baseLocalCompanion();
  final servicio = await servicioParaPerfil();
  if (await servicio.porCodigoBarras(p.codigo) != null) return;
  final usuario = await leerUsuario();
  int? categoriaId;
  if (p.categoria != null) {
    for (final c in await repo_productos.listarCategorias(db)) {
      if (c.nombre == p.categoria) categoriaId = c.id;
    }
  }
  await servicio.crearProducto(
    nombre: p.nombre,
    codigoBarras: p.codigo,
    categoriaId: categoriaId,
    esPesable: false,
    precioCentavos: p.precioCentavos,
    stock: p.stock,
    usuarioId: usuario?.id ?? 0,
  );
}
