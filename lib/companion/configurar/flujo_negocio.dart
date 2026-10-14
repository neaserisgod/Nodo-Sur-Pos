// Abre "Configurá tu negocio" con lo real detrás: la base local del celular, la cámara, el alta de productos de
// siempre (`ServicioCompanion.crearProducto`, con su rastro de stock) y horsepos.com/negocio en el navegador.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositorio_productos.dart' as repo_productos;
import '../../data/repositorio_servicios.dart' as repo_servicios;
import '../../data/repositorio_turnos.dart' show ConfigAgenda, configAgendaActual, guardarConfigAgenda;
import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart' show configuracionNegocioActual;
import '../base_local.dart';
import '../cuentas_del_celular.dart' show leerNegocioDeEstaCuenta;
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
  final nombreInicial = await _nombreParaElAsistente(db);
  final agenda = await configAgendaActual(db);
  if (!context.mounted) return;
  final ruta = MaterialPageRoute<void>(
    builder: (_) => AsistenteNegocio(
      pasoInicial: paso,
      nombreInicial: nombreInicial,
      categoriasExistentes: categorias,
      alCompletarPaso: (p) => marcarPasoHecho(p),
      alGuardarNegocio: (nombre, rubro) async {
        await guardarNegocio(db, nombre: nombre, rubro: rubro);
        unawaited(avisarNombreDelNegocio(nombre));
      },
      alEscanear: escanearCodigo,
      alGuardarProducto: (p) => _guardarProducto(p),
      alGuardarServicio: (s) => _guardarServicio(s),
      horarioInicial: agenda.horario,
      // Solo cambia el horario: el paso de turnos y la seña quedan como estaban (se ajustan en Configuración › Agenda y seña).
      alGuardarHorario: (horario) async {
        final c = await configAgendaActual(db);
        await guardarConfigAgenda(
          db,
          ConfigAgenda(horario: horario, pasoMinutos: c.pasoMinutos, sena: c.sena, aliasSena: c.aliasSena, titularSena: c.titularSena),
        );
      },
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

/// El nombre que ya se sabe del comercio: el de la base, o el que se le puso al crear el negocio ("Crear un negocio nuevo").
/// Antes salía de `marcaActual`, que en el celular nunca se llena, y el asistente volvía a pedirlo en blanco. El que el sitio le
/// pone solo a un negocio nuevo ("Negocio de …") no se propone.
Future<String> _nombreParaElAsistente(AppDatabase db) async {
  final local = (await configuracionNegocioActual(db)).nombreComercio.trim();
  if (local.isNotEmpty) return local;
  final delSitio = (await leerNegocioDeEstaCuenta())?.nombreNegocio?.trim() ?? '';
  return delSitio.startsWith('Negocio de ') || delSitio == 'Mi negocio' ? '' : delSitio;
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

/// El primer servicio de un negocio de servicios, por el mismo alta que la pestaña Servicios (`repositorio_servicios.dart`).
/// Sin insumos todavía: la receta se arma después.
Future<void> _guardarServicio(ServicioDePrueba s) async {
  final db = baseLocalCompanion();
  final usuario = await leerUsuario();
  int? categoriaId;
  if (s.categoria != null) {
    for (final c in await repo_productos.listarCategorias(db)) {
      if (c.nombre == s.categoria) categoriaId = c.id;
    }
  }
  await repo_servicios.crearServicio(
    db,
    nombre: s.nombre,
    precioCentavos: s.precioCentavos,
    duracionMinutos: s.duracionMinutos,
    categoriaId: categoriaId,
    usuarioId: usuario?.id ?? 0,
  );
}
