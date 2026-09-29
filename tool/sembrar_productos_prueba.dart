// Carga un puñado de productos de prueba directo en la base real de la app,
// para poder probar la pantalla de venta a mano.
//
// Usa `package:sqlite3` puro (no las clases de drift de la app): importar
// `package:la_plazoleta/data/database.dart` arrastra `drift_flutter` →
// `path_provider` → `dart:ui`, que no existe fuera de `flutter run`/`flutter
// test` — un script de línea de comandos con `dart run` no lo tiene
// disponible. Los nombres de columna de acá abajo están sacados del propio
// esquema real (`sqlite_master`), no adivinados.
//
// Uso: dart run tool/sembrar_productos_prueba.dart
// Cerrá la app antes de correrlo (si sqlite3.dll ya la tiene abierta, mejor
// no escribirle al mismo tiempo).
//
// Es idempotente: si un producto con ese nombre ya existe, lo saltea.

// ignore_for_file: avoid_print — es un script de línea de comandos, el
// feedback al usuario ES el print.

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main() {
  final perfil = Platform.environment['USERPROFILE'];
  if (perfil == null) {
    stderr.writeln('No se encontró USERPROFILE.');
    exit(1);
  }
  final ruta = '$perfil\\Documents\\la_plazoleta.sqlite';
  if (!File(ruta).existsSync()) {
    stderr.writeln('No existe $ruta — abrí la app al menos una vez antes de correr esto.');
    exit(1);
  }

  final db = sqlite3.open(ruta);

  final proveedores = <String, int>{
    for (final fila in db.select('SELECT id, codigo FROM proveedores'))
      fila['codigo'] as String: fila['id'] as int,
  };

  void agregar({
    String? codigoBarras,
    required String nombre,
    required String proveedorCodigo,
    bool esPesable = false,
    String tipoCigarrillo = 'ninguno',
    int? precioCentavos,
    int? costoCentavos,
    int? precioPorKiloCentavos,
    int? costoPorKiloCentavos,
    int stock = 0,
    int? stockGramos,
  }) {
    final yaExiste = db.select('SELECT id FROM productos WHERE nombre = ?', [nombre]);
    if (yaExiste.isNotEmpty) {
      print('Ya existe "$nombre", lo salteo.');
      return;
    }

    db.execute(
      '''
      INSERT INTO productos (
        codigo_barras, nombre, proveedor_id, es_varios, tipo_cigarrillo,
        es_pesable, precio_centavos, costo_centavos,
        precio_por_kilo_centavos, costo_por_kilo_centavos, stock, stock_gramos
      ) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        codigoBarras,
        nombre,
        proveedores[proveedorCodigo],
        tipoCigarrillo,
        esPesable ? 1 : 0,
        precioCentavos,
        costoCentavos,
        precioPorKiloCentavos,
        costoPorKiloCentavos,
        stock,
        stockGramos,
      ],
    );
    print('Agregado: $nombre');
  }

  // Almacén común, con código de barras (para probar el escaneo).
  agregar(
    codigoBarras: '7790895000782',
    nombre: 'Coca-Cola 500ml',
    proveedorCodigo: 'C',
    precioCentavos: 150000,
    costoCentavos: 100000,
    stock: 24,
  );
  agregar(
    codigoBarras: '7790115000123',
    nombre: 'Cerveza Quilmes 1L',
    proveedorCodigo: 'W',
    precioCentavos: 220000,
    costoCentavos: 150000,
    stock: 18,
  );
  agregar(
    codigoBarras: '7790040000456',
    nombre: 'Alfajor Jorgito',
    proveedorCodigo: 'G',
    precioCentavos: 90000,
    costoCentavos: 50000,
    stock: 40,
  );
  agregar(
    codigoBarras: '7790310000789',
    nombre: 'Fernet Branca 750ml',
    proveedorCodigo: 'B',
    precioCentavos: 900000,
    costoCentavos: 600000,
    stock: 8,
  );

  // Pesables (Mazzota / fiambres), sin código de barras — se buscan por
  // nombre con el patrón "200 nombre".
  agregar(
    nombre: 'Jamón cocido',
    proveedorCodigo: 'F',
    esPesable: true,
    precioPorKiloCentavos: 900000,
    costoPorKiloCentavos: 500000,
    stockGramos: 5000,
  );
  agregar(
    nombre: 'Queso cremoso',
    proveedorCodigo: 'F',
    esPesable: true,
    precioPorKiloCentavos: 850000,
    costoPorKiloCentavos: 480000,
    stockGramos: 4000,
  );

  // Cigarrillos: atado con ganancia fija ~$1.000 (Regla 6), suelto sin
  // recargo. Sin código de barras — entran por la grilla de directos.
  agregar(
    nombre: 'Marlboro Box',
    proveedorCodigo: 'S',
    tipoCigarrillo: 'atado',
    precioCentavos: 350000,
    costoCentavos: 250000,
    stock: 30,
  );
  agregar(
    nombre: 'Marlboro suelto',
    proveedorCodigo: 'S',
    tipoCigarrillo: 'suelto',
    precioCentavos: 20000,
    costoCentavos: 12500,
    stock: 100,
  );

  db.close();
  print('Listo.');
}
