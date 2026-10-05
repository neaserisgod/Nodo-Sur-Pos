# Plan: cargar facturas de compra con IA (2026-10-05)

Pedido del dueño: "automatizar al máximo las facturas de compra que recibo, que calcule todo automáticamente, con revisión humana".
Se armó mirando 13 facturas reales de 7 proveedores (fotos del celular, algunas torcidas, de costado o con dos facturas en una foto).

## Decisiones del dueño (2026-10-05)

- **Entra stock con la factura**, con una casilla por factura (hoy las reglas dicen que el stock solo baja: esto cambia esa regla).
- **Solo el costo y un precio sugerido.** Las anotaciones a mano (precios de venta, "Mío") NO se leen ni se aplican.
- **Plan gratis de Gemini**: acepta que Google use las facturas para mejorar sus productos.
- **El costo es lo que realmente paga** (es monotributista: no recupera IVA): neto + IVA + impuestos internos + su parte de las percepciones, menos su parte de los descuentos. Los descuentos del pie se reparten SIEMPRE entre los productos; las percepciones, por defecto también (`percepcionesAlCosto`).

## Flujo

1. Entra la foto o el PDF. Se endereza, se recorta y se achica (~2000 px, JPEG medio) antes de mandarla. Una foto puede traer VARIAS facturas.
2. Gemini transcribe (cabecera, líneas, pie). No hace cuentas.
3. El código normaliza cada línea (neto, IVA, internos) según la ficha del proveedor y calcula (`domain/factura_compra.dart`).
4. **Control de totales**: líneas + IVA + internos + percepciones tienen que dar el total impreso (tolerancia de centavos). Si no cierra, se marca en rojo: algo se leyó mal.
5. Se vincula cada línea con un producto: código de barras → vínculo ya aprendido de ese proveedor → parecido de nombre → Gemini elige entre los productos de ESE proveedor. Lo que no existe se da de alta desde Proveedores.
6. Pantalla de revisión: producto, unidades, costo viejo → nuevo, precio sugerido (fórmula de precio automático), casilla "no es del local". Todo verde = un solo "Confirmar".
7. Se aplica junto, con rastro y con "Deshacer": stock (si la casilla está), costo con historial, y la deuda en la cuenta corriente del proveedor (cuenta corriente) o un pago (contado). La imagen queda adjunta.
8. Cada vínculo y cada unidad por bulto que se confirma se aprende: la siguiente factura del proveedor sale casi sola.

## Fichas de lectura por proveedor (semillas)

| Proveedor | Importes de la línea | Descuentos | Extras al pie | Pago | Cuidado |
|---|---|---|---|---|---|
| **Serra** | Neto = P.UNIT × unidades − bonificación; el IMPORTE ya suma IVA e internos | % de bonificación por línea | Imp. internos (enormes en cigarrillos), IVA, saldo de cuenta corriente | Cta. cte. o contado | Trae un pagaré al pie; el tabaco/cigarrillos se tratan aparte (ganancia fija) |
| **Puelche** | Neto con 3 decimales; IVA solo al pie (21 % y 10,5 %) | Línea "Descuento 5 %" en negativo | IVA | Contado | **El % de descuento por producto es informativo, ya está aplicado: no volver a restarlo** |
| **Elpar** | Neto ya con su 5 % | % por línea | Percepción IIBB 1 % + IVA | Cta. cte. 2 días | **"Unid." son unidades sueltas; el "(24)" de la descripción es el pack del catálogo, no lo comprado** |
| **Maxiconsumo** | Factura B: "Pr. C/Imp." trae IVA | — | "IVA contenido" | Contado | "U. x" = unidades por bulto; hay un ticket pegado encima |
| **Bebidas del Lago** | IVA contenido en el importe | Bonificación % | Imp. internos + percepción IIBB al pie | Contado | Los combos listan componentes con total 0 (no sumar); 2 facturas por foto |
| **La Magdalena** | Neto "x des. I.I." | — | IVA al pie | Contado | Copia carbónica, columnas corridas; 2 facturas por foto |
| **Coca-Cola** | Factura B, foto de costado | — | "IVA contenido", envases | Contado | Se lee mal a baja resolución; hay que enderezarla primero |

## Estado

- **Hecho**: `lib/domain/factura_compra.dart` + `test/domain/factura_compra_test.dart` (costo real de cada línea y control de totales),
  probado con Elpar, Puelche (2) y Serra: las cuatro cierran con el total impreso con 0 a 2 centavos de diferencia.
- **Falta**: esquema de lectura y prompt de Gemini; CUIT del proveedor; tabla de vínculos (migración); pantalla de revisión; aplicar y deshacer;
  achicar/enderezar la foto; después, el celular con cámara.
- **Sin decidir**: tolerancia exacta del control; qué hacer con facturas de ajuste/nota de crédito.
