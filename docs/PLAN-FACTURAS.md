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

- **Hecho (cuentas)**: `lib/domain/factura_compra.dart`: costo real de cada línea y control de totales, probado con Elpar, Puelche (2) y Serra.
- **Hecho (lectura, 2026-10-05)**:
  - `ClienteGemini` acepta fotos y PDF (`AdjuntoGemini`).
  - `servicios/lector_facturas.dart`: el pedido a Gemini (transcribir sin hacer cuentas, ignorar lo escrito a mano y los datos del comprador, varias facturas por foto, combos, descuento global) con el modelo `gemini-3.8-flash` y, si no está para la clave, el que le anduvo al guardarla.
  - `domain/lectura_factura.dart`: interpreta la respuesta con cuidado (una línea rota se descarta y se avisa; CUIT, fechas y números en formato argentino) y **prueba las formas de leer los importes** (neto / con IVA / con IVA e internos) **hasta que una cierra con el total impreso**: no hace falta una regla por proveedor. Marca las líneas donde cantidad × precio no da el importe.
  - `servicios/preparar_imagen.dart`: achica la foto (2000 px, JPEG 85), respeta el giro del celular; los PDF van tal cual.
  - Pantalla de prueba: Proveedores › Más acciones › "Leer una factura (prueba)". Muestra el costo por unidad y si cierra; "Copiar lectura" deja el JSON de la IA en el portapapeles. **No guarda nada.**
- **Primera lectura real (2026-10-05)**: Serra 0051-00194239 (17 líneas). Gemini leyó bien las 17 líneas, el proveedor, el CUIT, el número, la fecha y la condición
  (cuenta corriente); ignoró lo escrito a mano y los datos del comprador; no inventó nada. El sistema eligió solo "importes con IVA adentro" y la factura cierra con
  **0 centavos** de diferencia contra el total impreso ($94.676,88), sin líneas sospechosas. Quedó como caso de prueba (`test/fixtures/lectura_serra_0051_00194239.json`).
  En esa factura "cantidad" son unidades (4 × 939,22), no bultos.
- **Hecho (vincular con los productos, 2026-10-05)**:
  - `domain/vinculo_factura.dart`: propone el producto de cada línea: 1) lo ya aprendido de ese proveedor (por código y por descripción) = verde, 2) código de barras = verde, 3) parecido de nombre
    con abreviaturas ("ALF" ≈ alfajor, "BL" ≈ blanco; los tamaños tienen que ser iguales; el producto del mismo proveedor desempata) = amarillo, para confirmar. Sin parecido claro queda sin vincular
    y se ofrecen alternativas: nunca se inventa un vínculo. Probado con las descripciones reales de Serra.
  - `servicios/vinculador_ia.dart`: para lo que el parecido no resuelve, Gemini elige ENTRE los productos del proveedor (solo nombres, sin precios ni costos); lo que devuelve se valida contra esa lista y queda en amarillo.
  - Se aprende: migración v52 con `vinculos_factura` (por proveedor, código o descripción → producto, con "unidades por cantidad") y `cuits_proveedor` (el CUIT reconoce al proveedor sin preguntar). Locales: no se sincronizan.
  - La pantalla de prueba muestra el proveedor, el producto de cada línea (se cambia con un selector), "× unid." (un bulto de 6 = 6, recalcula el costo por unidad) y "Aprender estos vínculos".
- **Falta**: probarla con las otras facturas reales (Coca-Cola de costado, carbónicas y matriz de puntos son las difíciles); CUIT del proveedor; tabla de vínculos (migración); pantalla de revisión final; aplicar (costo, stock, deuda y precio sugerido) y deshacer;
  enderezar fotos de costado; después, el celular con cámara.
- **Sin decidir**: tolerancia exacta del control; qué hacer con facturas de ajuste/nota de crédito.
