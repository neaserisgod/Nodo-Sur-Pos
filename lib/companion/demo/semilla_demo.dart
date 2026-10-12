// Los negocios de ejemplo de la demo (horsepos.com/demo/, `docs/PLAN-DEMO-SERVICIOS.md`): uno por rubro de servicios, con
// servicios, insumos, dos personas que atienden, clientes, la agenda de la semana y la caja del día con lo ya cobrado.
//
// Todo entra por los mismos repositorios que usa la app (alta de servicios, `crearTurno`, `abrirSesion`, el cobro de un turno):
// así lo que se ve en la demo son las cuentas de verdad, no números pegados a mano. Los datos son inventados.

import 'dart:convert';
import 'dart:math';

import '../../data/database.dart';
import '../../data/repositorio_productos.dart' as repo_productos;
import '../../data/repositorio_servicios.dart' as repo_servicios;
import '../../data/repositorio_turnos.dart' as repo_turnos;
import '../../data/repositorio_usuarios.dart' as repo_usuarios;
import '../../data/repositorio_ventas.dart' as repo_ventas;
import '../../domain/medio_pago.dart';
import '../../domain/plantillas_rubro.dart';
import '../../domain/servicios.dart';
import '../../domain/turnos.dart';
import '../cliente_companion.dart' show UsuarioCompanion;
import '../configurar/negocio_nuevo.dart' show guardarNegocio;

/// Un servicio de ejemplo. [receta]: nombre del insumo → cuánto usa, en la unidad del insumo.
class ServicioDemo {
  const ServicioDemo(this.nombre, this.categoria, this.pesos, this.minutos, {this.pideSena = false, this.receta = const {}});
  final String nombre;
  final String categoria;
  final int pesos;
  final int minutos;
  final bool pideSena;
  final Map<String, int> receta;
}

/// Un insumo de ejemplo: el envase que se compra y cuántos hay.
class InsumoDemo {
  const InsumoDemo(this.nombre, this.unidad, this.contenido, this.costoPesos, {this.envases = 3});
  final String nombre;
  final UnidadInsumo unidad;
  final int contenido;
  final int costoPesos;
  final int envases;
}

class NegocioDemo {
  const NegocioDemo({
    required this.rubro,
    required this.nombre,
    required this.duenio,
    required this.empleado,
    required this.servicios,
    this.insumos = const [],
  });

  final PlantillaRubro rubro;
  final String nombre;

  /// Quien "usa" la demo: el dueño, que ve todo.
  final String duenio;
  final String empleado;
  final List<ServicioDemo> servicios;
  final List<InsumoDemo> insumos;

  static const barberia = NegocioDemo(
    rubro: PlantillaRubro.barberia,
    nombre: 'Barbería El Faro',
    duenio: 'Nico',
    empleado: 'Tomi',
    insumos: [
      InsumoDemo('Tintura para barba', UnidadInsumo.ml, 60, 9000),
      InsumoDemo('Cera para peinar', UnidadInsumo.g, 100, 7000, envases: 4),
    ],
    servicios: [
      ServicioDemo('Corte', 'Cortes', 14000, 30, receta: {'Cera para peinar': 5}),
      ServicioDemo('Corte y barba', 'Cortes', 18000, 45, receta: {'Cera para peinar': 5}),
      ServicioDemo('Corte de chicos', 'Cortes', 10000, 30),
      ServicioDemo('Perfilado de barba', 'Barba', 8000, 20),
      ServicioDemo('Color de barba', 'Color', 16000, 45, pideSena: true, receta: {'Tintura para barba': 20}),
      ServicioDemo('Platinado', 'Color', 35000, 90, pideSena: true),
    ],
  );

  static const peluqueria = NegocioDemo(
    rubro: PlantillaRubro.peluqueria,
    nombre: 'Peluquería Coihue',
    duenio: 'Caro',
    empleado: 'Agus',
    insumos: [
      InsumoDemo('Tintura', UnidadInsumo.ml, 60, 9000, envases: 6),
      InsumoDemo('Oxidante', UnidadInsumo.ml, 1000, 8000),
      InsumoDemo('Shampoo', UnidadInsumo.ml, 1000, 12000, envases: 2),
    ],
    servicios: [
      ServicioDemo('Corte', 'Cortes', 18000, 45, receta: {'Shampoo': 20}),
      ServicioDemo('Lavado y brushing', 'Peinados', 12000, 30, receta: {'Shampoo': 20}),
      ServicioDemo('Color de raíz', 'Color', 35000, 90, pideSena: true, receta: {'Tintura': 60, 'Oxidante': 90}),
      ServicioDemo('Mechas', 'Color', 60000, 150, pideSena: true, receta: {'Tintura': 60, 'Oxidante': 120}),
      ServicioDemo('Alisado', 'Tratamientos', 80000, 180, pideSena: true),
      ServicioDemo('Peinado para evento', 'Peinados', 25000, 60),
    ],
  );

  static const unas = NegocioDemo(
    rubro: PlantillaRubro.unas,
    nombre: 'Lupe Nails',
    duenio: 'Lupe',
    empleado: 'Mica',
    insumos: [
      InsumoDemo('Esmalte semipermanente', UnidadInsumo.ml, 10, 7000, envases: 8),
      InsumoDemo('Gel para esculpir', UnidadInsumo.g, 30, 15000),
    ],
    servicios: [
      ServicioDemo('Esmaltado semipermanente', 'Manos', 15000, 60, receta: {'Esmalte semipermanente': 1}),
      ServicioDemo('Kapping', 'Manos', 22000, 90, receta: {'Gel para esculpir': 4}),
      ServicioDemo('Esculpidas', 'Manos', 30000, 120, pideSena: true, receta: {'Gel para esculpir': 8}),
      ServicioDemo('Pedicura', 'Pies', 18000, 60, receta: {'Esmalte semipermanente': 1}),
      ServicioDemo('Perfilado de cejas', 'Cejas y pestañas', 8000, 30),
      ServicioDemo('Lifting de pestañas', 'Cejas y pestañas', 20000, 60, pideSena: true),
    ],
  );

  static const estetica = NegocioDemo(
    rubro: PlantillaRubro.estetica,
    nombre: 'Estética Arrayán',
    duenio: 'Sofi',
    empleado: 'Juli',
    insumos: [
      InsumoDemo('Crema hidratante', UnidadInsumo.ml, 250, 20000),
      InsumoDemo('Cera descartable', UnidadInsumo.g, 500, 10000, envases: 4),
      InsumoDemo('Aceite de masajes', UnidadInsumo.ml, 500, 14000),
    ],
    servicios: [
      ServicioDemo('Limpieza facial', 'Faciales', 28000, 60, receta: {'Crema hidratante': 15}),
      ServicioDemo('Depilación de piernas', 'Depilación', 16000, 45, receta: {'Cera descartable': 60}),
      ServicioDemo('Depilación de axilas', 'Depilación', 7000, 20, receta: {'Cera descartable': 15}),
      ServicioDemo('Masaje descontracturante', 'Masajes', 25000, 60, receta: {'Aceite de masajes': 20}),
      ServicioDemo('Drenaje linfático', 'Corporales', 26000, 60, pideSena: true, receta: {'Aceite de masajes': 20}),
      ServicioDemo('Radiofrecuencia', 'Corporales', 32000, 45, pideSena: true),
    ],
  );

  static const todos = [barberia, peluqueria, unas, estetica];
}

/// Clientes inventados; los teléfonos no son de nadie (2944 00…).
const _clientes = [
  'Valentina Ruiz',
  'Martín Gómez',
  'Lucía Fernández',
  'Joaquín Pérez',
  'Sofía Álvarez',
  'Mateo Díaz',
  'Camila Romero',
  'Bruno Sosa',
  'Florencia Torres',
  'Julián Medina',
  'Micaela Herrera',
  'Santiago Castro',
  'Paula Ríos',
  'Lautaro Vega',
];

String _telefono(int i) => '2944 00${(1000 + i * 37).toString().padLeft(4, '0')}';

/// La demo atiende todos los días: abierta un domingo a la noche, igual tiene que mostrar una agenda con vida.
const horarioDemo = HorarioAtencion({
  1: (desdeMin: 540, hastaMin: 1200),
  2: (desdeMin: 540, hastaMin: 1200),
  3: (desdeMin: 540, hastaMin: 1200),
  4: (desdeMin: 540, hastaMin: 1200),
  5: (desdeMin: 540, hastaMin: 1200),
  6: (desdeMin: 540, hastaMin: 1200),
  7: (desdeMin: 600, hastaMin: 1080),
});

/// Ratos libres para los dos a la vez: "Nuevo turno" con "Cualquiera" ofrece solo los horarios en que no atiende nadie, y una
/// agenda llena de punta a punta no dejaría probar dar un turno. Un rato al mediodía y, desde mañana, otro a la tarde.
List<(int, int)> _huecosDelDia(int dia) => [(780, 840), if (dia > 0) (960 + (dia % 3) * 60, 1050 + (dia % 3) * 60)];

/// Si [desde, hasta) pisa un rato libre, dónde termina ese rato (para seguir desde ahí).
int? _huecoQuePisa(int dia, int desde, int hasta) {
  for (final (d, h) in _huecosDelDia(dia)) {
    if (desde < h && hasta > d) return h;
  }
  return null;
}

/// Fondo con que se abre la caja de la demo.
const fondoDemoCentavos = 2000000;

/// Arma el negocio [n] en [db] (una base nueva, vacía) y devuelve el perfil del dueño, que es con el que se entra.
/// [ahora] decide qué turnos de hoy ya pasaron (se cobraron) y cuáles vienen. Con la misma [semilla], los mismos datos.
Future<UsuarioCompanion> sembrarNegocioDemo(AppDatabase db, NegocioDemo n, {DateTime? ahora, int semilla = 7}) async {
  final momento = ahora ?? DateTime.now();
  final azar = Random(semilla);

  await guardarNegocio(db, nombre: n.nombre, rubro: n.rubro);
  await repo_turnos.guardarConfigAgenda(
    db,
    repo_turnos.ConfigAgenda(
      horario: horarioDemo,
      sena: const ConfigSena(modo: ModoSena.algunos, porcentaje: 30),
      aliasSena: '${n.nombre.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '.')}.mp',
      titularSena: n.duenio,
    ),
  );

  final duenioId = await repo_usuarios.crearUsuario(db, n.duenio);
  final empleadoId = await repo_usuarios.crearUsuario(db, n.empleado);

  final categorias = {for (final c in await repo_productos.listarCategorias(db)) c.nombre: c.id};
  final insumos = <String, int>{};
  for (final i in n.insumos) {
    insumos[i.nombre] = await repo_servicios.crearInsumo(
      db,
      nombre: i.nombre,
      unidad: i.unidad,
      contenidoEnvaseMilesimas: i.contenido * 1000,
      costoEnvaseCentavos: i.costoPesos * 100,
      stockMinimoMilesimas: i.contenido * 1000,
      stockInicialMilesimas: i.contenido * 1000 * i.envases,
      usuarioId: duenioId,
    );
  }
  final servicios = <int>[];
  for (final s in n.servicios) {
    servicios.add(
      await repo_servicios.crearServicio(
        db,
        nombre: s.nombre,
        precioCentavos: s.pesos * 100,
        duracionMinutos: s.minutos,
        categoriaId: categorias[s.categoria],
        pideSena: s.pideSena,
        receta: [for (final e in s.receta.entries) (insumoId: insumos[e.key]!, milesimas: e.value * 1000)],
        usuarioId: duenioId,
      ),
    );
  }

  final sesionId = await repo_ventas.abrirSesion(db, usuarioId: duenioId, fondoInicialCentavos: fondoDemoCentavos);

  // La semana: hoy y los seis días que siguen. Cada persona llena su día con turnos y algún hueco libre, para que la agenda
  // se vea ocupada pero con lugar para dar uno más.
  final hoy = DateTime(momento.year, momento.month, momento.day);
  var cliente = 0;
  var cobrados = 0;
  for (var d = 0; d < 7; d++) {
    final dia = hoy.add(Duration(days: d));
    final franja = horarioDemo.delDia(dia)!;
    for (final profesional in [duenioId, empleadoId]) {
      // Más lleno hoy y mañana; hacia el fin de la semana quedan más huecos.
      final ocupacion = d == 0 ? 0.8 : (d == 1 ? 0.7 : 0.55 - d * 0.04);
      var minuto = franja.desdeMin + (profesional == empleadoId ? 30 : 0);
      while (true) {
        final indice = azar.nextInt(servicios.length);
        final s = n.servicios[indice];
        if (minuto + s.minutos > franja.hastaMin) break;
        final hueco = _huecoQuePisa(d, minuto, minuto + s.minutos);
        if (hueco != null) {
          minuto = hueco;
          continue;
        }
        if (azar.nextDouble() > ocupacion) {
          minuto += 30;
          continue;
        }
        final inicio = dia.add(Duration(minutes: minuto));
        final nombre = _clientes[cliente % _clientes.length];
        final telefono = _telefono(cliente % _clientes.length);
        cliente++;
        final yaPaso = !inicio.add(Duration(minutes: s.minutos)).isAfter(momento);
        final producto = await (db.select(db.productos)..where((p) => p.id.equals(servicios[indice]))).getSingle();
        final senaPedida = await repo_turnos.senaParaServicio(db, producto);
        // Los que pidió el bot (uno de cada cuatro de los que vienen) y piden seña la están esperando: así se ve cómo trabaja el bot.
        // De los demás que piden seña, dos de cada tres ya la dejaron (por transferencia).
        final delBot = !yaPaso && cliente % 4 == 0;
        final esperando = delBot && senaPedida > 0;
        final pagoSena = senaPedida > 0 && !esperando && cliente % 3 != 0;
        final turnoId = await repo_turnos.crearTurno(
          db,
          servicioId: servicios[indice],
          inicio: inicio,
          nombreCliente: nombre,
          telefono: telefono,
          profesionalId: profesional,
          usuarioId: duenioId,
          senaCentavos: pagoSena ? senaPedida : 0,
          senaEsEfectivo: false,
          sesionCajaId: sesionId,
          estado: esperando ? EstadoTurno.esperandoSena : EstadoTurno.confirmado,
          senaVence: esperando ? momento.add(const Duration(hours: 12)) : null,
          origen: delBot ? 'BOT' : 'APP',
          idRemoto: delBot ? 'demo-$cliente' : null,
        );
        if (yaPaso) {
          if (cliente % 7 == 0 && !pagoSena) {
            await repo_turnos.marcarNoVino(db, turnoId);
          } else {
            // Los de hoy que ya pasaron se cobraron: mitad en efectivo, mitad por Mercado Pago.
            final efectivo = cobrados.isEven;
            cobrados++;
            await repo_ventas.registrarVentaSegunMedio(
              db,
              lineas: [await repo_turnos.lineaDeTurno(db, turnoId)],
              medio: efectivo ? ComposicionPago.efectivo : ComposicionPago.virtual,
              canal: efectivo ? null : 'qr',
              sesionCajaId: sesionId,
              usuarioId: profesional,
              turnoId: turnoId,
            );
          }
        }
        minuto += s.minutos;
      }
    }
  }

  return UsuarioCompanion(id: duenioId, nombre: n.duenio);
}

/// Para tests: los turnos como texto, para comparar dos siembras.
Future<String> resumenDeTurnos(AppDatabase db) async {
  final filas = await db.select(db.turnos).get();
  return jsonEncode([for (final t in filas) '${t.inicio.toIso8601String()} ${t.servicioNombre} ${t.estado}']);
}
