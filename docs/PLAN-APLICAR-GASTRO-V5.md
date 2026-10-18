# Plan · llevar el mock v5 de Nodo Gastro a Flutter

El dueño, 2026-10-18: aprobó el mock completo (`docs/mock-gastro/NodoGastro.html`, vivo:
https://claude.ai/artifact/As8mcQ9WVRsTCdTZSVADsb) y pidió "llevalo a flutter". Se hace por etapas, como el rediseño v4 de la
PC (`docs/PLAN-APLICAR-V4.md`): cada etapa se prueba con `flutter analyze` y los tests afectados antes de la siguiente.

## Alcance

**Solo la edición Gastronomía.** El aspecto cambia por la edición (`esEdicionGastronomia`): almacén y Nodo Sur Servicios
quedan como están. La marca del sitio es de las tres ediciones, así que llevar este aspecto a las otras dos es una decisión
del dueño que queda para después.

## Cómo está armado

- **Colores:** `TokensNs` (`lib/companion/kit/tokens_ns.dart`) suma `gastroClaro` y `gastroOscuro` (los de
  NodoSurPage/nodo.css) y tres tokens nuevos: `onPrim` (texto sobre el primario; en el oscuro de Gastro el primario es claro),
  `acento` y `onAcento` (la acción que más importa: naranja con texto negro en Gastro, igual al primario en las demás).
  `TokensNs.paraBrillo` elige los de la edición; el tema y `context.ns` lo usan, así que las pantallas no preguntan la edición.
- **Letras:** Bricolage Grotesque (títulos y cifras, `tituloNs`) y Geist (texto, `estiloNs` y el tema) en `fonts/`, con su OFL.
  En las otras ediciones sigue Figtree.
- **Barra de pestañas:** cápsula flotante con cinco pestañas iguales y el globo de pedidos por aceptar (`BarraInferiorNs`
  con `conPedidos`).
- **Botón de acento:** `BotonNs.acento` para lo que más importa de cada pantalla.

## Etapas

1. **Base visual** (colores, letras, barra, botón de acento). ✅ 2026-10-18.
2. **Pedidos** (`pantalla_pedidos_ns.dart`): tablero en mosaicos ("Sale ahora" con cuenta regresiva, Nuevos, En la cocina con
   atrasados), filtros en cápsula, tarjetas con la comanda renglón por renglón y un botón principal, la cocina en un botón
   redondo que abre su hoja. ✅ 2026-10-18. Captura: `flutter test test/companion/capturas_gastro_test.dart` → `capturas/gastro/`.
3. **Alta:** bienvenida de tres pantallas propia de Gastro (`bienvenida/bienvenida_gastro.dart`: el bot, la cocina manda, la caja
   cierra sola; "Ya tengo cuenta" la saltea) antes de entrar con la cuenta, y los botones principales del asistente en naranja
   (`BotonNs.acento`). ✅ 2026-10-18. El asistente ya tenía el paso de progreso y "Después" del mock; con la paleta y las letras
   nuevas queda igual.
4a. **Carta, primer retoque:** "+ Nuevo" en naranja y "Traer de mi catálogo de WhatsApp" como banda naranja suave. ✅ 2026-10-18.
4. **Carta, lo que falta:** segmentos Platos · Bebidas · Insumos, "Traer de mi catálogo" arriba, ganancia en verde o rojo por plato,
   insumos por acabarse primero. Hoja del plato con el costo y la ganancia que se recalculan. Pendiente.
5. **Vender y cobrar:** más vendidos en mosaicos, total grande, los cuatro medios; hoja de cobro con "con cuánto paga" y
   vuelto, QR en pantalla esperando la aprobación, "Venta cobrada" que se cierra sola. Pendiente.
6. **Caja y cierre:** tablero (vendido, efectivo en el cajón, cuánto trajo el bot), las cuatro acciones en mosaicos,
   Resumen · Ventas · Movimientos, cierre en dos etapas como el mock. Pendiente.
7. **Más y páginas:** buscador arriba, mosaicos de Asistente y Bot, grupos Pedidos · Carta y compras · Esta aplicación;
   páginas internas con título grande y "Volver" en cápsula. Pendiente.

## Lo que el mock tiene y la app todavía no

Para confirmar con el dueño antes de construirlo (no son solo aspecto):

- Promos que la app sugiere ("se piden juntos 7 de cada 10 veces").
- "Contesta en 4 s" y pedidos tomados hoy en la página del bot.
- Separar para proveedores con el detalle por rubro de insumo.
