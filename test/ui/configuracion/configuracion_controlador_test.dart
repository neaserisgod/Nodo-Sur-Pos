import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/configuracion/configuracion_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late ConfiguracionControlador c;

  setUp(() async {
    db = baseDeTest();
    c = ConfiguracionControlador(db);
    await c.cargarTodo();
  });
  tearDown(() => db.close());

  test('cargarTodo trae configuración, categorías, usuarios, medios y secciones', () {
    expect(c.configuracion, isNotNull);
    expect(c.categorias, hasLength(11));
    expect(c.usuarios, hasLength(1));
    expect(c.mediosDePago, hasLength(2));
    expect(c.secciones, hasLength(3));
  });

  test('guardarRecargo actualiza y recarga', () async {
    await c.guardarRecargo(primerAtado: 50000, atadoAdicional: 20000, suelto: 10000);
    expect(c.configuracionNegocio!.recargoPrimerAtadoCentavos, 50000);
  });

  test('guardarFondoFijo y guardarPasoRedondeo actualizan y recargan', () async {
    await c.guardarFondoFijo(25000000);
    await c.guardarPasoRedondeo(50000);
    expect(c.configuracion!.fondoFijoCentavos, 25000000);
    expect(c.configuracionNegocio!.pasoRedondeoCentavos, 50000);
  });

  test('guardarProductoVuelto guarda el id elegido', () async {
    final id = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Caramelo', precioCentavos: const Value(500)),
        );
    await c.guardarProductoVuelto(id);
    expect(c.configuracionNegocio!.productoVueltoId, id);
  });

  test('guardarMarkupCategoria actualiza solo esa categoría', () async {
    final categoria = c.categorias.first;
    await c.guardarMarkupCategoria(categoria.id, 8000);
    expect(c.categorias.firstWhere((cat) => cat.id == categoria.id).markupDefaultBp, 8000);
  });

  test('agregarUsuario y alternarActivoUsuario', () async {
    await c.agregarUsuario('Ayuda finde');
    final nuevo = c.usuarios.firstWhere((u) => u.nombre == 'Ayuda finde');

    await c.alternarActivoUsuario(nuevo);
    expect(c.usuarios.firstWhere((u) => u.id == nuevo.id).activo, isFalse);

    await c.alternarActivoUsuario(c.usuarios.firstWhere((u) => u.id == nuevo.id));
    expect(c.usuarios.firstWhere((u) => u.id == nuevo.id).activo, isTrue);
  });

  test('renombrarUsuarioExistente cambia el nombre', () async {
    final bruno = c.usuarios.first;
    await c.renombrarUsuarioExistente(bruno.id, 'Bruno G.');
    expect(c.usuarios.firstWhere((u) => u.id == bruno.id).nombre, 'Bruno G.');
  });

  test('renombrarMedio y alternarActivoMedio', () async {
    final efectivo = c.mediosDePago.firstWhere((m) => m.esEfectivo);
    await c.renombrarMedio(efectivo.id, 'Contado');
    expect(c.mediosDePago.firstWhere((m) => m.id == efectivo.id).nombre, 'Contado');

    await c.alternarActivoMedio(c.mediosDePago.firstWhere((m) => m.id == efectivo.id));
    expect(c.mediosDePago.firstWhere((m) => m.id == efectivo.id).activo, isFalse);
  });

  test('alternarVisibleSeccion oculta y muestra', () async {
    final proveedores = c.secciones.firstWhere((s) => s.clave == 'proveedores');
    await c.alternarVisibleSeccion(proveedores);
    expect(c.secciones.firstWhere((s) => s.id == proveedores.id).visible, isFalse);
  });

  test('moverSeccion hacia arriba intercambia el orden con la anterior', () async {
    final segunda = c.secciones[1];
    await c.moverSeccion(1, arriba: true);
    expect(c.secciones.first.id, segunda.id);
  });

  test('moverSeccion en el primer lugar hacia arriba no hace nada', () async {
    final original = c.secciones.map((s) => s.id).toList();
    await c.moverSeccion(0, arriba: true);
    expect(c.secciones.map((s) => s.id).toList(), original);
  });
}
