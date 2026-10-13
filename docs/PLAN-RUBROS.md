# Plan: una base para muchos rubros (empezando por quien emprende con comidas)

El dueño, 2026-10-13: *"estaría bueno diversificarnos a todos los rubros, pero quiero tener una base lista para un poco más
de variantes"* y, primero, *"la gente que emprende con comidas: budín, tortas…"*. Pidió evaluar qué es lo más rápido. Este
documento es el plan; **no hay código todavía**. Las preguntas de negocio abiertas están al final y se contestan antes de
arrancar cada etapa.

## 1. Cómo está hoy

- Una sola app (PC, celular, web). El rubro (`PlantillaRubro`, `lib/domain/plantillas_rubro.dart`) decide la **forma de
  trabajar** (`FormaDeTrabajo`: `productos` o `servicios`), y la forma decide qué pestañas se ven (Inicio ↔ Agenda,
  Productos ↔ Servicios, Vender con buscador ↔ grilla) y qué módulos valen (`lib/domain/modulos.dart`).
- Cada rubro hoy es solo **datos**: nombre, categorías de arranque, gastos fijos y forma. Agregar una verdulería o un
  consultorio no necesita pantallas nuevas.
- Lo que cambia por forma está escrito como `if (forma == servicios)` en unos pocos lugares (menú, asistente de alta,
  configuración, buscador de funciones). Con dos formas alcanza; con una tercera conviene ordenarlo (etapa 0).

## 2. La idea: tres formas cubren casi todo el comercio chico

| Forma | Cómo compra el cliente | Rubros | Estado |
|---|---|---|---|
| **Mostrador** (`productos`) | Llega, elige, paga | Almacén, kiosco, fiambrería, verdulería, carnicería, dietética, pet shop, ferretería, librería | Hecha |
| **Turnos** (`servicios`) | Reserva un horario | Uñas, barbería, peluquería, estética, consultorios, tatuajes, veterinaria, lavadero | Hecha |
| **Pedidos** (nueva) | Encarga para un día y lo retira o se lo llevan | Budines y tortas, viandas, comida casera, catering; después rotisería, pizzería, hamburguesería | A construir |

Encima de la forma, cada rubro prende o apaga **capacidades** (que ya son módulos o lo serían): productos por peso,
variantes y agregados, delivery, seña, stock de lo elaborado, mesas. Así un rubro nuevo es una plantilla, no una app.

## 3. Por qué "comidas por encargo" es lo más rápido de lo nuevo

Casi todo ya existe, en las otras dos formas:

| Lo que necesita quien vende budines | Ya existe en |
|---|---|
| Producto **elaborado con receta** (harina, huevos, manteca) y su costo real | Servicios: `recetaServicio`, insumos por envase, costo por servicio y precio sugerido por ganancia buscada |
| Comprar insumos por envase y saber cuánto queda | Servicios: insumos con stock en milésimas |
| Pedido con **varios productos** y **seña** | Almacén: Encargues (`Pendientes`: líneas, seña, estado, venta al completarse) |
| Seña por **link de Mercado Pago** que se confirma sola | Servicios (turnos) |
| Ver los pedidos **por día** | Servicios: la Agenda (hoy muestra turnos) |
| Tomar pedidos por **WhatsApp** con varias líneas | Bot en modo comercio (pide nombre y confirma; hoy solo "para retirar") |
| Caja simple, QR, efectivo, gastos | Las dos formas |

Lo que **falta** de verdad:

1. **Fecha de entrega en el pedido** (columna nueva en `Pendientes`) y estados propios (por confirmar → confirmado →
   listo → entregado).
2. **Agenda de entregas**: la misma Agenda, mostrando pedidos del día en vez de turnos.
3. **"Qué cocinar"**: los pedidos de mañana (o de la semana) sumados por producto, y los insumos que hacen falta contra los
   que hay → lista de compras. Es la cuenta de la receta que ya existe, multiplicada.
4. **Elaborado vendible**: hoy la receta es del "servicio" (sin stock, con duración). Un budín es lo mismo sin duración,
   con stock opcional (si también vende lo que ya tiene hecho).
5. **Bot**: pedir la fecha de entrega y la seña por link en el modo pedidos.
6. **Catálogo para compartir** (link con fotos y precios para Instagram o WhatsApp). No es imprescindible para arrancar.

## 4. Etapas (cada una se prueba antes de la siguiente)

| Etapa | Qué | Tamaño | Reutiliza |
|---|---|---|---|
| **0. Base ordenada** | La plantilla del rubro pasa a describir también: pestañas, palabras ("turno"/"pedido", "clienta"/"cliente"), módulos prendidos al arrancar y textos del bot. Los `if (forma == …)` pasan a leer de ahí. Sin cambios visibles. | Chico | Todo |
| **1. Rubros que ya entran** | Plantillas nuevas, solo datos: verdulería, carnicería, dietética, pet shop, ferretería (mostrador); consultorio, tatuajes, veterinaria (turnos). Textos del bot por rubro. | Chico | Mostrador y turnos |
| **2. Modo simple de almacén** | Un comercio chico arranca con los módulos avanzados apagados (lata, separaciones, carga histórica, promos). | Chico | Módulos |
| **3. Pedidos: comidas por encargo** | Lo de la sección 3: fecha de entrega, Agenda de entregas, "Qué cocinar", elaborados con receta, bot con fecha y seña. Rubros: pastelería y budines, viandas, comida casera. | Mediano | Servicios + Encargues + bot |
| **4. Pedidos al momento** | Pedido para ya con estados (preparando → listo), **variantes y agregados**, delivery con dirección y costo de envío, comanda impresa. Rubros: rotisería, pizzería y empanadas, hamburguesería. | Mediano-grande | Etapa 3 + Point/QR |
| **5. Mesas** | Cuentas abiertas por mesa. Bar, restó. | Grande | Ventas abiertas (pestañas) de la PC |

Orden recomendado: **0 → 1 → 3 → 2 → 4**; la 5 solo si hay demanda. La 0 primero porque cada rubro que se suma después
es más barato; la 1 porque es casi gratis y amplía a quién se le puede vender ya; la 3 porque es lo que pidió el dueño
y reutiliza más.

## 5. Preguntas de negocio (contestar antes de la etapa que las usa)

1. **¿En qué app va lo de comidas?** (a) dentro de Nodo Sur Servicios, mismo APK y plan Emprendedor; (b) una edición
   aparte (otro nombre en el celular, por ejemplo "Nodo Sur Emprende"). Recomendado: (a), y cambiar el nombre visible si
   hace falta, porque cada edición aparte es otro APK que publicar y mantener.
2. **¿Lo elaborado lleva stock?** Solo por encargo, o también lo que ya tiene hecho (budines en la vidriera).
   Recomendado: las dos, con stock apagado por defecto.
3. **Seña en pedidos de comida**: ¿por defecto sí? ¿Qué porcentaje? (En turnos es 30 % en algunos servicios.)
4. **Envíos en la etapa 3**: ¿solo retiro, o también "lo llevo" con costo fijo? Recomendado: retiro y un costo de envío
   fijo opcional; el delivery con zonas va en la etapa 4.
5. **Precio**: ¿el plan Emprendedor ($ 18.000) cubre también a quien vende comida?
