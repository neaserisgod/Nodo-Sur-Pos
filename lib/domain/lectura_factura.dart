// Lo que la IA transcribe de una factura de compra, y cómo se lleva a la forma que usan las cuentas (`factura_compra.dart`).
// Funciones puras: no saben de Gemini ni de la base. Lo que llega de una IA no se da por bueno sin mirarlo, así que acá se lee con
// cuidado (una línea rota se descarta y se avisa) y después se controla contra el total impreso.
//
// IDEA CENTRAL (El dueño, 2026-10-05, con 13 facturas de 7 proveedores): cada proveedor imprime los importes de una manera — neto,
// con IVA adentro, con IVA e impuestos internos adentro (docs/PLAN-FACTURAS.md). En vez de una regla escrita a mano por proveedor,
// se PRUEBAN las formas posibles de leer los importes y se queda con la que cierra con el total impreso. Si ninguna cierra, algo se
// leyó mal y se revisa a mano.

import 'dinero.dart';
import 'factura_compra.dart';

/// Cómo vienen impresos los importes de las líneas.
enum ModoImportes {
  /// El importe es el neto (sin IVA). Puelche, Elpar.
  neto,

  /// El importe ya trae el IVA adentro. Maxiconsumo, Bebidas del Lago.
  conIva,

  /// El importe trae el IVA y los impuestos internos de la línea adentro. Serra.
  conIvaEInternos,
}

class LineaLeida {
  const LineaLeida({
    required this.descripcion,
    required this.importeCentavos,
    this.codigo,
    this.cantidad,
    this.precioUnitarioCentavos,
    this.descuentoPct,
    this.alicuotaBp,
    this.internosCentavos = 0,
    this.esDetalle = false,
  });

  final String? codigo;
  final String descripcion;

  /// Lo que dice la columna de cantidad, tal cual (puede ser bultos o unidades según el proveedor).
  final double? cantidad;

  /// Precio de UNA unidad, tal cual está impreso (a veces con 3 decimales: se guarda en centavos con redondeo).
  final int? precioUnitarioCentavos;

  /// El % de descuento impreso en la línea (puede ser solo informativo: el importe ya lo trae aplicado).
  final double? descuentoPct;

  /// IVA de la línea en puntos básicos (2100 = 21 %). Null = no lo dice: se asume 21 %.
  final int? alicuotaBp;
  final int internosCentavos;
  final int importeCentavos;

  /// Una línea que solo detalla de qué se compone un combo, sin importe propio: no se suma.
  final bool esDetalle;
}

class PieLeido {
  const PieLeido({
    this.subtotalCentavos,
    this.descuentoGlobalCentavos = 0,
    this.internosCentavos = 0,
    this.percepcionesCentavos = 0,
    this.ivaCentavos,
    this.totalCentavos,
  });

  final int? subtotalCentavos;

  /// En positivo: la IA lo informa así aunque la factura lo imprima restando.
  final int descuentoGlobalCentavos;
  final int internosCentavos;
  final int percepcionesCentavos;
  final int? ivaCentavos;
  final int? totalCentavos;
}

class FacturaLeida {
  const FacturaLeida({
    required this.lineas,
    required this.pie,
    this.proveedorNombre,
    this.proveedorCuit,
    this.tipo,
    this.numero,
    this.fecha,
    this.condicionPago,
    this.advertencias = const [],
  });

  final String? proveedorNombre;

  /// Solo dígitos (11), o null si no se pudo leer.
  final String? proveedorCuit;

  /// 'A', 'B', 'C', 'remito' u otro, tal cual lo informó la IA.
  final String? tipo;
  final String? numero;
  final DateTime? fecha;

  /// 'contado' | 'cuenta_corriente' | null.
  final String? condicionPago;
  final List<LineaLeida> lineas;
  final PieLeido pie;

  /// Lo que la IA o la lectura marcaron como dudoso o ilegible.
  final List<String> advertencias;
}

class LecturaDeFacturas {
  const LecturaDeFacturas({required this.facturas, this.advertencias = const []});

  /// Una foto puede traer más de una factura.
  final List<FacturaLeida> facturas;
  final List<String> advertencias;
}

// ─── Leer la respuesta de la IA ───────────────────────────────────────────

/// Interpreta el JSON que devolvió la IA: `{"facturas":[{...}]}`. Nunca tira por datos raros: una línea rota se descarta (y se
/// avisa), un dato ilegible queda en null.
LecturaDeFacturas leerRespuestaDeFacturas(Object? json) {
  final avisos = <String>[];
  final crudas = json is Map ? json['facturas'] : (json is List ? json : null);
  if (crudas is! List) {
    return const LecturaDeFacturas(facturas: [], advertencias: ['La IA no devolvió ninguna factura.']);
  }
  final facturas = <FacturaLeida>[];
  for (var i = 0; i < crudas.length; i++) {
    final f = crudas[i];
    if (f is! Map) continue;
    final advertencias = <String>[
      for (final a in (f['advertencias'] is List ? f['advertencias'] as List : const [])) if (a is String && a.trim().isNotEmpty) a.trim(),
    ];
    final lineas = <LineaLeida>[];
    var descartadas = 0;
    for (final l in (f['lineas'] is List ? f['lineas'] as List : const [])) {
      final leida = _leerLinea(l);
      if (leida == null) {
        descartadas++;
      } else {
        lineas.add(leida);
      }
    }
    if (descartadas > 0) advertencias.add('$descartadas línea(s) no se pudieron leer y se descartaron.');
    final proveedor = f['proveedor'] is Map ? f['proveedor'] as Map : const {};
    final pie = f['pie'] is Map ? f['pie'] as Map : const {};
    facturas.add(
      FacturaLeida(
        proveedorNombre: _texto(proveedor['razon_social']),
        proveedorCuit: _cuit(proveedor['cuit']),
        tipo: _texto(f['tipo']),
        numero: _texto(f['numero']),
        fecha: _fecha(f['fecha']),
        condicionPago: _condicionPago(f['condicion_pago']),
        lineas: lineas,
        advertencias: advertencias,
        pie: PieLeido(
          subtotalCentavos: _centavos(pie['subtotal']),
          descuentoGlobalCentavos: (_centavos(pie['descuento_global']) ?? 0).abs(),
          internosCentavos: (_centavos(pie['impuestos_internos']) ?? 0).abs(),
          percepcionesCentavos: (_centavos(pie['percepciones']) ?? 0).abs(),
          ivaCentavos: _centavos(pie['iva_total']),
          totalCentavos: _centavos(pie['total']),
        ),
      ),
    );
  }
  if (facturas.isEmpty) avisos.add('La IA no devolvió ninguna factura.');
  return LecturaDeFacturas(facturas: facturas, advertencias: avisos);
}

LineaLeida? _leerLinea(Object? l) {
  if (l is! Map) return null;
  final importe = _centavos(l['importe']);
  if (importe == null) return null;
  final alicuota = _numero(l['alicuota_iva']);
  return LineaLeida(
    codigo: _texto(l['codigo']),
    descripcion: _texto(l['descripcion']) ?? '(sin descripción)',
    cantidad: _numero(l['cantidad']),
    precioUnitarioCentavos: _centavos(l['precio_unitario']),
    descuentoPct: _numero(l['descuento_pct']),
    alicuotaBp: alicuota == null ? null : (alicuota * 100).round(),
    internosCentavos: (_centavos(l['internos_importe']) ?? 0).abs(),
    importeCentavos: importe,
    esDetalle: l['es_detalle'] == true,
  );
}

String? _texto(Object? v) {
  if (v is! String) return v is num ? '$v' : null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Un número, venga como número o como texto ("1.234,56" o "1234.56").
double? _numero(Object? v) {
  if (v is num) return v.toDouble();
  if (v is! String) return null;
  var t = v.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',') && t.contains('.')) {
    // El último separador es el decimal.
    t = t.lastIndexOf(',') > t.lastIndexOf('.') ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else if (t.contains(',')) {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}

/// Pesos con decimales (como los imprime la factura) → centavos. Es el único lugar donde un decimal se vuelve entero.
int? _centavos(Object? v) {
  final n = _numero(v);
  return n == null || n.isNaN || n.isInfinite ? null : (n * centavosPorPeso).round();
}

String? _cuit(Object? v) {
  final digitos = (_texto(v) ?? '').replaceAll(RegExp(r'\D'), '');
  return digitos.length == 11 ? digitos : null;
}

DateTime? _fecha(Object? v) {
  final t = _texto(v);
  if (t == null) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
  final local = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(t);
  final (int, int, int)? ymd = iso != null
      ? (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!))
      : local != null
          ? (int.parse(local[3]!), int.parse(local[2]!), int.parse(local[1]!))
          : null;
  if (ymd == null) return null;
  final (y, m, d) = ymd;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

String? _condicionPago(Object? v) {
  final t = _texto(v)?.toLowerCase().replaceAll(' ', '_');
  return t == 'contado' || t == 'cuenta_corriente' ? t : null;
}

// ─── Llevarla a la forma de las cuentas ───────────────────────────────────

class FacturaNormalizada {
  const FacturaNormalizada({
    required this.leida,
    required this.modo,
    required this.factura,
    required this.lineas,
    required this.control,
    required this.lineasSospechosas,
  });

  final FacturaLeida leida;

  /// La forma de leer los importes con la que se calculó (la que cerró, si alguna cerró).
  final ModoImportes modo;

  /// Lo que se le pasa a `costosDeFactura`: solo las líneas que cuentan (sin detalle de combos ni descuentos).
  final FacturaDeCompra factura;

  /// Las líneas leídas que corresponden, en el mismo orden que `factura.lineas`.
  final List<LineaLeida> lineas;

  /// Null si la factura no trae el total impreso (no se puede controlar).
  final ControlDeFactura? control;

  /// Posiciones (en [lineas]) donde cantidad × precio no da el importe: es donde mirar primero si algo no cierra.
  final List<int> lineasSospechosas;

  bool get cierra => control?.cierra ?? false;
}

/// Lleva [leida] a la forma de las cuentas probando las formas de leer los importes ([ModoImportes]). Con [preferido] (lo que ya se
/// sabe de este proveedor) se prueba primero; gana la primera que cierra con el total impreso. Si ninguna cierra, devuelve la
/// preferida (o `neto`) con `cierra == false`: hay que revisarla.
///
/// Las líneas de detalle de un combo y las líneas de descuento en negativo no son productos: el descuento pasa a ser el descuento global.
FacturaNormalizada normalizarFactura(FacturaLeida leida, {ModoImportes? preferido}) {
  final productos = <LineaLeida>[];
  var descuentoEnLineas = 0;
  for (final l in leida.lineas) {
    if (l.importeCentavos < 0) {
      descuentoEnLineas += -l.importeCentavos;
    } else if (!l.esDetalle && l.importeCentavos > 0) {
      productos.add(l);
    }
  }
  final descuentoGlobal = leida.pie.descuentoGlobalCentavos + descuentoEnLineas;
  final internosDeLineas = productos.fold<int>(0, (a, l) => a + l.internosCentavos);

  FacturaDeCompra armar(ModoImportes modo) => FacturaDeCompra(
        lineas: [for (final l in productos) _lineaNormalizada(l, modo)],
        descuentoGlobalCentavos: descuentoGlobal,
        // Los impuestos internos del pie ya están sumados en las líneas si las líneas los traen: no contarlos dos veces.
        internosAlPieCentavos: internosDeLineas > 0 ? 0 : leida.pie.internosCentavos,
        percepcionesCentavos: leida.pie.percepcionesCentavos,
      );

  final orden = [?preferido, ...ModoImportes.values.where((m) => m != preferido)];
  final total = leida.pie.totalCentavos;

  List<int> sospechosasDe(FacturaDeCompra f) => [
        for (var i = 0; i < productos.length; i++)
          if (_esSospechosa(productos[i], f.lineas[i].netoCentavos)) i,
      ];

  var elegido = orden.first;
  ControlDeFactura? control;
  FacturaDeCompra? factura;
  List<int>? sospechosas;
  if (productos.isEmpty) {
    factura = const FacturaDeCompra(lineas: []);
    sospechosas = const [];
  } else if (total == null) {
    factura = armar(elegido);
    sospechosas = sospechosasDe(factura);
  } else {
    for (final modo in orden) {
      final candidata = armar(modo);
      final c = _controlarSinTirar(candidata, total);
      if (c == null) continue;
      final sosp = sospechosasDe(candidata);
      // La primera forma que cierra gana. Si ninguna cierra, se queda con la que deja MENOS líneas sospechosas (la forma correcta
      // solo marca la línea mal leída; una forma equivocada las marca todas) y, a igual cantidad, con la de menor diferencia.
      final mejora = control == null ||
          sosp.length < sospechosas!.length ||
          (sosp.length == sospechosas.length && c.diferenciaCentavos.abs() < control.diferenciaCentavos.abs());
      if (c.cierra || mejora) {
        elegido = modo;
        factura = candidata;
        control = c;
        sospechosas = sosp;
      }
      if (c.cierra) break;
    }
    if (factura == null) {
      factura = armar(elegido);
      sospechosas = sospechosasDe(factura);
    }
  }

  return FacturaNormalizada(
    leida: leida,
    modo: elegido,
    factura: factura,
    lineas: productos,
    control: control,
    lineasSospechosas: sospechosas!,
  );
}

LineaDeFactura _lineaNormalizada(LineaLeida l, ModoImportes modo) {
  final unidades = l.cantidad == null || l.cantidad! < 1 ? 1 : l.cantidad!.round();
  final alicuota = l.alicuotaBp ?? 2100;
  final neto = switch (modo) {
    ModoImportes.neto => l.importeCentavos,
    ModoImportes.conIva => netoDesdeImporteConIva(l.importeCentavos, alicuota),
    ModoImportes.conIvaEInternos => netoDesdeImporteConIva(l.importeCentavos - l.internosCentavos, alicuota),
  };
  return LineaDeFactura(unidades: unidades, netoCentavos: neto < 0 ? 0 : neto, alicuotaBp: alicuota, internosCentavos: l.internosCentavos);
}

ControlDeFactura? _controlarSinTirar(FacturaDeCompra f, int total) {
  try {
    return controlarFactura(f, totalImpresoCentavos: total);
  } on ArgumentError {
    // Por ejemplo, un descuento mayor que la factura en esta forma de leer: esa forma no sirve.
    return null;
  }
}

/// Una línea es sospechosa si ni cantidad × precio ni ese mismo importe con el descuento de la línea dan su neto. Con el descuento
/// y sin él: en algunas facturas el % es informativo y el precio ya lo trae (Puelche), en otras hay que aplicarlo (Elpar).
bool _esSospechosa(LineaLeida l, int netoCentavos) {
  final precio = l.precioUnitarioCentavos;
  final cantidad = l.cantidad;
  if (precio == null || cantidad == null) return false;
  final sinDescuento = precio * cantidad;
  final conDescuento = sinDescuento * (1 - (l.descuentoPct ?? 0) / 100);
  final tolerancia = (sinDescuento * 0.001).round().clamp(5, 1 << 30);
  return (sinDescuento - netoCentavos).abs() > tolerancia && (conDescuento - netoCentavos).abs() > tolerancia;
}
