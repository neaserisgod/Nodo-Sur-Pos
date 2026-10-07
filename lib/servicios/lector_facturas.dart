// Lee facturas de compra con Gemini (El dueño, 2026-10-05: "automatizar al máximo las facturas de compra, con revisión humana").
// La IA SOLO transcribe lo impreso; las cuentas las hace el código (`domain/factura_compra.dart`) y el control contra el total impreso
// (`domain/lectura_factura.dart`) atrapa lo que se haya leído mal. Plan completo en `docs/PLAN-FACTURAS.md`.
//
// Privacidad: el plan gratis de Google puede usar lo que recibe para mejorar sus productos, y una factura muestra costos y datos del
// comercio. El dueño lo aceptó (2026-10-05). Por eso se le pide a la IA no transcribir los datos del comprador.

import 'package:http/http.dart' as http;

import '../domain/lectura_factura.dart';
import 'gemini.dart';

/// Se lee con el modelo que el dueño eligió (Configuración › Asistente IA; por defecto `gemini-3.5-flash-lite`, que anduvo bien en las
/// seis facturas reales y es el más barato — El dueño, 2026-10-05). Si ese está saturado o sin cupo, se prueba con este, más fuerte.
const modeloDeRespaldoParaFacturas = 'gemini-3.8-flash';

const instruccionesDeLecturaDeFacturas = '''
Sos un lector de facturas de compra de un almacén de barrio en Argentina. Recibís fotos o PDF de facturas, remitos o comprobantes de proveedores. Transcribí SOLO lo que está impreso; no hagas cuentas, no corrijas y no adivines.

Reglas:
- Una imagen puede traer MÁS DE UNA factura (por ejemplo dos facturas una debajo de la otra). Devolvé una entrada por cada factura. Si el archivo trae varias páginas, leé todas.
- La foto puede estar torcida, de costado, con sombras o con objetos y papeles encima: leela igual.
- IGNORÁ todo lo escrito a mano, los resaltados, los sellos y los papeles pegados. No los transcribas.
- NO transcribas los datos del comprador (el cliente): ni su nombre, ni su CUIT, ni su domicilio. Solo los del proveedor que emite la factura.
- Los números van como número JSON, con punto decimal y sin separador de miles (1234.56). Si un dato no se lee con seguridad, devolvé null: nunca lo inventes. Si hay algo dudoso o ilegible, anotalo en "advertencias".
- "importe" de cada línea es el importe FINAL de esa línea tal como está impreso en la última columna de importes (no lo recalcules). "precio_unitario" es el precio de UNA unidad tal como está impreso (puede tener 3 decimales). "cantidad" es lo que dice la columna de cantidad, sin multiplicarla por nada. "descuento_pct" es el PORCENTAJE de descuento impreso en la línea (un número de 0 a 100), aunque diga que es informativo. Si la factura imprime el descuento como un MONTO en pesos y no como porcentaje, ponelo en "descuento_importe" y dejá "descuento_pct" en null.
- "alicuota_iva" de la línea: 21, 10.5 o 0, si la factura lo indica por línea; si no, null.
- "internos_importe": el impuesto interno de la línea, si hay una columna de impuestos internos; si no, 0.
- Si un combo se detalla en líneas hijas sin importe propio, ponelas con "es_detalle": true y "importe": 0.
- Si la factura tiene una línea de descuento general (por ejemplo "Descuento 5%") o un descuento al pie, ponelo en "pie.descuento_global" como número POSITIVO y no como línea de producto.
- "pie.percepciones" es la suma de percepciones de IIBB u otras. "pie.impuestos_internos" es el total de impuestos internos del pie. "pie.total" es el total de la factura.
- "condicion_pago": "contado" o "cuenta_corriente" según diga la factura (cuenta corriente, plazo, a X días = cuenta_corriente); null si no lo dice.
- "tipo": "A", "B", "C", "remito" u "otro". "fecha": AAAA-MM-DD. "cuit" del proveedor solo con los 11 dígitos.

Respondé únicamente JSON, con esta forma:
{"facturas":[{"proveedor":{"razon_social":"...","cuit":"..."},"tipo":"A","numero":"0001-00001234","fecha":"2026-08-25","condicion_pago":"contado","lineas":[{"codigo":"...","descripcion":"...","cantidad":3,"precio_unitario":1714.05,"descuento_pct":5,"descuento_importe":null,"importe":4885.04,"alicuota_iva":21,"internos_importe":0,"es_detalle":false}],"pie":{"subtotal":0,"descuento_global":0,"impuestos_internos":0,"percepciones":0,"iva_total":0,"total":0},"advertencias":[]}]}
''';

class ResultadoDeLectura {
  const ResultadoDeLectura({required this.lectura, required this.json, required this.modelo});

  final LecturaDeFacturas lectura;

  /// Lo que contestó la IA, tal cual (para poder copiarlo y ver qué leyó).
  final Object? json;
  final String modelo;
}

/// Manda [adjuntos] (fotos ya achicadas y/o PDF) a Gemini y devuelve lo que leyó. Lanza [ErrorGemini] con un mensaje listo para mostrar
/// si no hay clave, no hay cupo o no hay internet.
///
/// Los modelos más nuevos se saturan seguido (Google contesta 503 "overloaded") y cada modelo tiene su propio cupo gratis: ante un 503 se
/// reintenta una vez ([espera] después) y, si sigue, se pasa al modelo siguiente; ante un 404 (no está para esta clave) o un 429 (se
/// acabó el cupo de ESE modelo) se pasa directo. Cualquier otro fallo (clave mala, sin internet) no lo arregla otro modelo.
Future<ResultadoDeLectura> leerFacturasConGemini(
  List<AdjuntoGemini> adjuntos, {
  http.Client? client,
  Duration espera = const Duration(seconds: 3),
}) async {
  if (adjuntos.isEmpty) throw const ErrorGemini('No hay nada para leer: elegí una foto o un PDF.');
  if (!ClaveGemini.configurada) throw const ErrorGemini('Falta cargar la clave de la IA en Configuración › Asistente IA.');

  final modelos = {ClaveGemini.modelo ?? modeloGeminiPorDefecto, modeloDeRespaldoParaFacturas};
  ErrorGemini? ultimo;
  for (final modelo in modelos) {
    for (var intento = 0; intento < 2; intento++) {
      // Leer una hoja entera tarda más que ponerle nombre a una promo.
      // La clave de este equipo o la del negocio (por el sitio): el pedido es el mismo.
      final cliente = ClienteGemini.guardado(modelo: modelo, client: client, timeout: const Duration(seconds: 180));
      try {
        final json = await cliente.generarJson(
          'Transcribí las facturas de los archivos adjuntos.',
          sistema: instruccionesDeLecturaDeFacturas,
          temperatura: 0,
          adjuntos: adjuntos,
        );
        return ResultadoDeLectura(lectura: leerRespuestaDeFacturas(json), json: json, modelo: modelo);
      } on ErrorGemini catch (e) {
        ultimo = e;
        final saturado = (e.estado ?? 0) >= 500;
        if (saturado && intento == 0) {
          await Future<void>.delayed(espera);
          continue;
        }
        if (saturado || e.estado == 404 || e.estado == 429) break; // al modelo siguiente
        rethrow;
      } finally {
        cliente.close();
      }
    }
  }
  throw ultimo!;
}
