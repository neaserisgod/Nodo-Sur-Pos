# App de PC vs. mock del celular + horsepos.com / antigravity (2026-10-05)

Rama `claude/horsepos-redesign-mock-2a305t`. **Etapa 1 (esta): comparación y mock de escritorio. No se tocó código de Flutter.**
Etapa 2 (después del OK del dueño): llevar el mock a `lib/ui/`, una fase por vez (ver "Plan" abajo).

- **Mock de PC (artifact, interactivo, claro/oscuro, 1920×1080):** https://claude.ai/artifact/P4VGSxmyWQBXaXo4QTbrYT
  Fuente en este repo: `docs/mock-pc/NodoSurPC.html` (un solo archivo, sin dependencias salvo la fuente Figtree de Google Fonts).
- **Referencias usadas:** paquete `nodo-sur-mock-celular` (175 capturas, docs 00–09; es el mismo que ya se calcó en el celular,
  APK 2133–2135), `NodoSurPage/theme.css` y `home.css` (horsepos.com) y antigravity.google.

## 1. Qué es antigravity y qué tomó cada pieza

antigravity.google: fondo blanco, bloques planos sin borde ni sombra, botones rectangulares redondeados y planos, mucho aire,
títulos grandes, un solo acento de enlace azul, imágenes en bloques. horsepos.com lo tradujo a: tinta `#121317`, bloques
`#F3F4F7`, Figtree, títulos en peso 450 con tracking negativo, pastillas, y azul `#2f5fe0` solo como acento de enlaces y foco.
El mock del celular fue un paso más: **mismo lenguaje, pero con azul de marca `#2f5be8` como color de acción** (Vender, Nueva venta,
Mercado Pago, pestaña activa), 4 tonos de estado, íconos de trazo propios, modales y toast. La PC quedó un paso atrás
de eso: tiene el lenguaje antigravity del 2026-10-03 pero no lo que el celular agregó después.

## 2. Diferencias de fondo (PC hoy → mock de PC)

| Tema | PC hoy (`lib/ui/tema/`) | Mock de PC |
|---|---|---|
| Acento | Tinta `#121317` como único acento; en oscuro, blanco (`colores_escritorio.dart`) | Tinta en claro y **azul `#2f5be8` en oscuro** para lo "activo" (`--prim`); **azul de marca fijo** para Venta, Nueva venta, Cobrar y Mercado Pago |
| Medios de pago | Efectivo naranja `#B45309`, QR azul `#3B6CFF`, débito verde agua `#0E9F85`, **mixto violeta** `#8A5CF6` (`acentos.dart`) | Efectivo verde `#0b7a5e`, MP azul `#2f5be8`, tarjeta gris `#4b5563`, mixto ámbar `#b45309`. **Sin violeta**, sin degradés |
| Tarjeta destacada | Degradé casi negro → azul oscuro (`_heroClaro/_heroOscuro`) | Color plano `--hero` (`#121317` claro, `#1c2231` oscuro) |
| Navbar | Pastillas de texto, la activa gris | Pastillas con **ícono de trazo + texto**; activa = burbuja azul claro con texto azul; **Venta siempre azul** (más oscuro si está activa); engranaje como `sliders` |
| Íconos | Material Icons Rounded (`iconos.dart`) | Trazo único 24×24, grosor 2 (ya existen en `lib/companion/kit/iconos_ns.dart`) |
| Títulos | Figtree 600–700 (`Pesos.fuerte`) | Figtree **450**, tracking −0,045 a −0,06 em, cifras tabulares. Las fuentes del proyecto son estáticas (400/500/600/700): **se usa 500** (desvío permitido por el doc 07 del mock) o se agrega la variable |
| Diálogos | `Modal` centrado, zoom desde 0,96 (`comun/modal.dart`) | **Modal al centro** (decisión del dueño, 05/10), radio 40, sombra suave, título 28/450, botones apilados, ancho 760 px (1040 los anchos); el velo cierra salvo terminal y "Venta cobrada" |
| Avisos | SnackBar | Toast oscuro flotante abajo, 2,6 s |
| Encabezados de sección | Varios estilos | 14/700 mayúsculas, +0,04 em, color `mute` |
| Campos | `campo_texto.dart` | Campo en bloque `--s`, radio 28, etiqueta 13/600 arriba, "grande" 40/450 para importes |
| Listas | Filas sueltas | Lista agrupada: un bloque con líneas finas de 1 px (`gap:1` sobre fondo hairline) |
| Interruptores | Material Switch | Pista 56×32, perilla 26 |

## 2b. Qué cubre el mock (v2, 2026-10-05)

Pantallas: Venta, Inicio, Proveedores, Separaciones, Historial (Ventas · Movimientos · Cierres), Encargues y deudas, Cierre de caja
(contar → resultado → "Caja cerrada") y Configuración (5 grupos). Búsqueda global con la lupa (Ctrl+F) fuera de Venta.

Modales: cobro en efectivo, QR/tarjeta (débito o crédito en 1 pago), terminal con sus estados (esperando, cliente confirma, aprobado,
rechazado, venció, sin conexión), mixto, venta cobrada, descuento ($ o %), ventas abiertas, cambiar de turno, Varios, gasto o
ingreso, contar la caja, abrir caja, cantidad exacta; Proveedores: nuevo, editar, pagar (con origen de la plata), cuenta corriente,
edición masiva (con aviso de ≥ 50 %), importar CSV, promos con sugerencias, comparar precios, leer una factura, editar producto;
Separaciones: ganancia del día, retirar plata, productos sin costo; Historial: editar y anular venta, cargar día histórico;
Encargues: nuevo, entregar, cobrar deuda; Configuración: datos del comercio, secciones del menú, ticket, impresión y terminal,
celular (código), cuenta, copias, categorías, colchón de reposición, asistente IA.

Hay un selector "Ir a un estado…" para saltar a cualquiera de ellos. Cosas del mock que son diseño propuesto y no existen todavía en
la app real: aplicar una factura (en la app solo hay lectura de prueba), el aviso de ≥ 50 % en la edición masiva y el botón "Ver
movimientos" de la cuenta corriente del proveedor. Confirmar cuáles se quieren antes de construirlas.

## 3. Por pantalla

**Venta** — se conserva el layout (grilla con "Más vendidos" por defecto + carrito y cobro fijos a la derecha; búsqueda, total y
medios siempre visibles; carrito scrollea). Cambia: navbar con íconos; total en tarjeta plana; medios 2×2 que se pintan al elegirse;
"Cobrar" azul; línea nueva del carrito con aro azul; cantidad exacta con doble clic en una hoja; Varios, Gasto/Ingreso, Arqueo y
Apertura como hojas. Archivos: `venta/pantalla_venta.dart`, `columna_busqueda.dart`, `columna_carrito.dart`, `columna_cobro.dart`,
`dialogo_*.dart`.

**Inicio** — "Hola, Ana" 56/450 y botón azul "Nueva venta" (hoy no hay saludo ni botón). Tarjeta "Hoy vendiste" con barra
efectivo / Mercado Pago, 4 indicadores, más vendidos, gráfico por hora (barras `s2`, pico azul), stock bajo, encargues y deudas, y
bloque "Este mes" contra los fijos. Archivo: `dashboard/pantalla_dashboard.dart`.

**Proveedores** — lista a la izquierda (fila = círculo de ícono + chip "Le debés"/"Al día"), detalle a la derecha con cuenta corriente
en tarjeta plana y "Pagar a proveedor"; tabla con insignia "N % gan."; edición de producto como hoja ancha (1040 px) con ganancia
en vivo. Archivos: `proveedores/*`.

**Separaciones** — cuatro tarjetas (cajón, Mercado Pago, reserva de fijos en ámbar, "Te queda" en verde) y lista agrupada con tilde
propio. Archivo: `separaciones/pantalla_separaciones.dart`.

**Historial** — pastillas Ventas · Movimientos · Cierres y períodos Hoy / Ayer / 7 días / Este mes; detalle como ticket;
Reimprimir, Editar, Anular (hoja, motivo obligatorio). Archivos: `historial/*`.

**Cierre de caja** — dos pasos centrados (contar a ciegas → resultado Cuadró / Faltan / Sobran), "Mercado Pago según Mercado Pago"
y "Traer saldo". Archivo: `cierre/pantalla_cierre.dart`.

**Configuración** — mismos 5 grupos, ahora con filas agrupadas e interruptores del mock; Apariencia con segmento Claro · Oscuro ·
Automático. Archivo: `configuracion/pantalla_configuracion.dart`.

## 4. Lo que NO cambia (reglas del negocio y del proyecto)

Montos en centavos; recargo de cigarrillos antes del redondeo; redondeo solo en efectivo; crédito en 1 pago y sin recargo; QR,
débito y crédito son un solo medio "Mercado Pago" en la caja; conteo a ciegas antes de ver la diferencia; "Más vendidos" de entrada;
atajos Alt; Venta es la pantalla principal; navbar superior centrada (no se pasa a barra inferior: es PC); búsqueda con lupa
(Ctrl+F) fuera de Venta; búsqueda y total siempre visibles en Venta; tema automático sigue a Windows.

## 5. Para que el dueño decida antes de tocar código

1. **¿"Cobrar" en azul o en negro?** El mock lo pone azul (como "Nueva venta" y "Vender" del celular). Hoy es negro.
2. ~~¿Hojas inferiores en PC?~~ **Resuelto (05/10): los modales van al centro**, como hoy; solo cambia el estilo.
3. **¿Se saca el violeta del mixto?** El mock lo pasa a ámbar y pone efectivo en verde (el naranja de hoy pasa a ser del mixto).
   Cambia el color al que el cajero ya está acostumbrado.
4. **¿El azul de acción vale también para "Cerrar caja" y botones de gestión?** En el mock quedan en tinta (negro) y solo el flujo de
   vender/cobrar es azul.
5. **Peso 450:** usar 500 con las fuentes actuales, o sumar Figtree variable (~100 KB) para ser fiel al mock.
6. Tira de "Sin conexión" y avisos de Mercado Pago de la campanita: el mock muestra la campanita con el aviso de arqueo y un
   cobro sin venta; confirmar que el diseño de esos avisos es el que quiere.

## 6. Plan para la etapa 2 (cada fase se prueba antes de la siguiente)

1. **Tokens y kit:** `colores_escritorio.dart` (acento azul en oscuro, hero plano), `acentos.dart` (paleta de medios), `iconos.dart`
   apuntando al set de trazo de `iconos_ns.dart`, `tokens.dart` (pesos), toast y hoja reutilizando `lib/companion/kit/hoja_ns.dart` y
   `aviso_ns.dart` donde se pueda.
2. **Navbar** (`navbar_superior.dart`): íconos, Venta azul, estados de la burbuja.
3. **Venta** completa + sus hojas (la de más uso).
4. **Cierre de caja** y **Separaciones** (tocan plata).
5. **Inicio**, **Proveedores**, **Historial**, **Configuración**.
6. Capturas con `test/ui/capturas_escritorio_test.dart` contra el mock, `flutter analyze` y la suite completa.

Nada de esto se probó en una PC real; el mock es HTML y las cifras son de ejemplo (iguales a las del mock del celular).
