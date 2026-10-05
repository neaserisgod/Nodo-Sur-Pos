# Especificación de la app de PC v3 — rediseño desde cero (2026-10-05)

Documento para que una IA (o una persona) lleve **al pie de la letra** el mock de escritorio v3 a la app real de Flutter.
**Salvo las excepciones de la sección 14, todo lo que dice este documento se implementa tal cual.**

- **Mock vivo (interactivo, claro/oscuro):** https://claude.ai/artifact/DnUi6qvYDxZpgpD3uh14js
- **Fuente del mock en el repo:** `docs/mock-pc/NodoSurPC-v3.html` (un solo archivo; se abre en cualquier navegador; la fuente Figtree viene de Google Fonts).
  Es la **referencia visual y de comportamiento**. Si este documento y el mock difieren en un número, **gana el mock** (y este documento se corrige).
- **Reemplaza** al mock anterior (`docs/mock-pc/NodoSurPC.html`) y a `docs/COMPARACION-MOCK-PC.md`. Aquel mock conservaba la disposición de la app; este la rehace entera.
- Nada de lo que está acá toca `lib/domain/` ni `lib/data/`: es **solo capa de presentación** (`lib/ui/`). Las reglas de negocio no cambian (sección 11).

---

## 0. Cómo usar este documento (para la IA que implementa)

1. Leé `CLAUDE.md`, `REGLAS-NEGOCIO.md`, `ESTADO.md` y este documento, en ese orden. Este documento **manda sobre `DISENO.md` y sobre la sección "Hardware" y "Pantalla de venta" de `CLAUDE.md`** en todo lo visual y de movimiento (regla del repo: "vale lo más reciente"; este diseño es del 2026-10-05 y lo pidió el dueño). Cuando lo apliques, **corregí `DISENO.md` y `CLAUDE.md` en el mismo cambio** para que no se contradigan.
2. Abrí el mock en un navegador y recorrelo con el selector **"Ir a un estado…"** (arriba, fuera de la ventana): salta a 39 estados (modales, terminal, cierre, etc.).
3. Implementá **por capas y por pantallas, probando cada una** (sección 13). No mezcles la capa de tema con las pantallas en un solo cambio.
4. Decisiones técnicas (nombres, estructura de archivos, widgets) se toman sin preguntar. Decisiones de negocio o ambiguas: se marcan y se preguntan (sección 14.3 lista las pendientes).
5. Los montos del mock son **pesos enteros** solo por comodidad: en la app real todo sigue siendo **`int` en centavos** (regla 1 de `CLAUDE.md`).

---

## 1. Qué es este rediseño y de dónde sale

El dueño: la estética del sitio (horsepos.com, hoy "Nodo Sur") está basada en **antigravity.google**; la app del celular ya está bastante integrada con esa estética, **la de escritorio no le gusta para nada**. Pidió rehacerla de cero, pudiendo cambiar **la disposición de todo**, tomando como guía el sitio, antigravity y la app Android.

Decisiones del dueño para esta pasada (2026-10-05, respondidas en la conversación):

| Tema | Decisión |
|---|---|
| Navegación | **Pastilla flotante arriba + mega-menú** (como horsepos/antigravity) |
| Venta | **Buscador gigante + grilla + ticket alto a la derecha** |
| Carácter | **Alto en todo, también en Venta** (partículas, tipeo, reveal, cursor-pastilla, cifras que cuentan) |
| Heredadas | Modales al **centro**; "Cobrar" **azul**; medios de pago con colores propios; Venta es la pantalla principal; la app arranca en Venta |

### 1.1 Investigación (navegando las dos webs de verdad, no capturas)

Se navegó con Chromium (scroll, hover, clic, páginas internas) y se leyó el CSS/JS publicado. Lo que se aprendió y de dónde sale cada pieza del mock:

**horsepos.com** (`home.css`, `main.js`, `home.js`, `fx.js`, `theme.css`):
- Curva única de la marca: `cubic-bezier(.2,.7,.1,1)` (acá `--ease`). Botones: hover `translateY(-2px)` + sombra `0 14px 34px rgba(18,19,23,.22)`, `:active scale(.98)`. Tarjetas: hover `translateY(-4px)` y fondo un poco más oscuro, `.5s`.
- **Header que "se levanta"**: pastilla de vidrio (`rgba(255,255,255,.62)` + `blur(18px) saturate(1.6)`); al scrollear >8 px pasa a `.88` y suma sombra.
- **Reveal escalonado**: `opacity 0→1` y `translateY(34px)→0`, `.9s`, retraso `min(índice,5)*70ms` por hermano.
- **Producto 3D que se endereza**: `perspective:1600px`, `rotateX((1-p)*16deg)` y `scale(.93+p*.07)`, con `p = clamp((vh-top)/(vh*.75))`.
- **Titular que se enciende palabra por palabra** al scrollear (`opacity .2→1`).
- **Cifras que cuentan hacia arriba** (1100 ms, ease-out cúbico) y luego "la venta sigue": cada cambio hace un pulso (`.pop`).
- **Campo de partículas** (`fx.js`): puntos y rayitas que giran despacio alrededor de un centro y **huyen del mouse** (radio 120 px). Paleta `#4f7cff #8a5cf6 #d36bb5` + grises.
- Cinta de chips (marquee) con máscara en los bordes; carrusel con `scroll-snap`; barras que se llenan al verse; caret con gradiente que parpadea.
- Tipografía: **Figtree**, títulos en peso **450** con `letter-spacing` entre −0,045 y −0,06 em; texto de apoyo gris; botón principal tinta `#121317`; fondo de bloques `#F3F4F7`; radios muy grandes (`clamp(24px,3.4vw,48px)`); acento azul `#2f5fe0` solo para enlaces.

**antigravity.google** (CSS y JS de `/_astro/`: GSAP, ScrollTrigger, SplitText, ScrollSmoother):
- **Título que se tipea** (`TypedHeader`): `SplitText` por caracteres, cada uno aparece con `stagger` de 0,05 s (0,02 s en títulos largos) y un **caret con gradiente** (`#4f7cff → #b05cf0 → #ff6a5c → #f6c343`) que se mueve con el último carácter y parpadea.
- **Campo de partículas WebGL** que reacciona al mouse (anillo que desplaza puntos) y aparece con un fundido de 4 s; el logo sube `1em` y aparece en 2 s (`power2.out`).
- **Mega-menú**: al pasar el mouse por "Products / Use Cases / Resources" cae un **panel de ancho completo**, blanco, con esquinas inferiores redondeadas, que **atenúa el resto de la página**; a la izquierda un título grande (`Explore our next generation products`) y un botón "See overview"; a la derecha listas con íconos; los ítems entran en cascada (`stagger .05`).
- **Scroll suave** (`ScrollSmoother`, `smooth: .6`) y **cursor-pastilla** sobre ciertos bloques: una etiqueta blanca con ícono y texto que sigue al mouse (`quickTo` .35 s `power2.out`) y aparece con `back.out(1.7)`.
- Reveal de texto por caracteres (`stagger .005`), listas que entran `y:30 → 0` en `.6s power2.out`, íconos que flotan en seno (35 px, 7 s).
- Tokens: radios `4/8/16/24/36/48`, espaciado `4/8/16/24/36/48/60/80/88/120/180`, tipografía **Google Sans Flex** (peso 450 en títulos), tinta `#121317`, botón primario negro, `outline-variant #2122260f`, ~15 curvas nombradas (`out-expo`, `out-back`, `out-quart`…).
- Cambio de página: **sin transición de página** (navegación normal); lo que da la sensación de continuidad es el título que se tipea y las partículas que reaparecen. El mock agrega una salida corta (sección 5.2) porque en una app no hay "carga de página".

> Decisión de tipografía: se mantiene **Figtree** (la de la app, el celular y horsepos), no Google Sans Flex. Ver excepción E-1.

### 1.2 Lo que se tomó de la app Android (guía de contenido)

Paleta y tokens del mock del celular (tinta, azul de marca `#2f5be8`, 4 tonos de estado), íconos de trazo propios (los de `lib/companion/kit/iconos_ns.dart`), "Buscador de funciones", conteo a ciegas, hojas de gasto/ingreso, notificaciones con pendientes, y la separación Resumen/Separar/Ventas. Todo reinterpretado para pantalla grande.

---

## 2. Principios (en orden de prioridad)

1. **Operar > arrancar.** Nada de lo decorativo demora lo que se tipea, el foco, el escaneo ni el cobro. Todo lo animado es **no bloqueante**: el texto y los datos ya están en su lugar desde el primer cuadro; se puede hacer clic durante cualquier animación.
2. **Búsqueda, total y medios de pago siempre visibles en Venta**; el carrito scrollea (regla dura de `CLAUDE.md`, no cambia).
3. **El dueño mira esta pantalla 12 h/día.** Contraste medido, nunca blanco puro sobre negro puro (en oscuro: fondo `#0E0F13`, texto `#EEF0F4`). Ninguna línea de texto cruza la pantalla entera (anchos máximos).
4. **Lo expresivo va en lo que no es dinero.** Gradiente, partículas, tipeo y cursor-pastilla **nunca** sobre importes, botones de cobro ni estados de plata. (Excepción acotada: el importe del titular de Inicio lleva gradiente como en horsepos; es un saludo, no un dato operativo.)
5. **Un solo lenguaje**: bloques planos grandes, sin bordes ni sombras salvo donde se indica (modales, mega-menú, popovers, pastilla elevada, toast).
6. **Reducible**: Configuración › Tema y movimiento permite apagar partículas, cursor-pastilla y scroll suave, y pasar a "Reducido". "Reducir animaciones" de Windows apaga todo solo (sección 5.9).

---

## 3. Sistema visual (tokens)

### 3.1 Color

Se definen **una vez** (en `lib/ui/tema/colores_escritorio.dart` y `acentos.dart`) y se usan por nombre. Claro / Oscuro:

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| `ink` (texto) | `#121317` | `#EEF0F4` | texto principal |
| `paper` (fondo) | `#FFFFFF` | `#0E0F13` | fondo de ventana |
| `s` (bloque) | `#F3F4F7` | `#171A21` | tarjetas, campos, listas |
| `s2` (bloque hover/2.º nivel) | `#E6E9EF` | `#232733` | hover, tiles |
| `s3` | `#DDE1E9` | `#2D3240` | pistas, barras vacías, scrollbar |
| `mute` | `#566070` | `#A0A8B6` | texto secundario |
| `soft` | `#7B8494` | `#7E8696` | texto terciario, títulos de columna |
| `line` | `rgba(18,19,23,.12)` | `rgba(255,255,255,.16)` | contorno de chips/outline |
| `hair` | `rgba(18,19,23,.07)` | `rgba(255,255,255,.08)` | separadores de 1 px |
| `blue` (acción) | `#2F5BE8` | `#3D68F2` | Venta, Cobrar, activo, foco, íconos de acción |
| `blue-d` (hover) | `#1F3FA8` | `#2F5BE8` | hover/pressed del azul |
| `blue-l` (selección) | `#E8EDFF` | `#17254F` | fondo de lo elegido (tile con producto, fila seleccionada) |
| `prim` (botón principal neutro) | `#121317` | `#3D68F2` | botón oscuro (Cerrar caja, Nuevo proveedor) |
| `hero` | `#121317` | `#1C2231` | tarjeta destacada (total, "Hoy vendiste", cajón) — **plana, sin degradé** |
| `efe` (efectivo) | `#0B7A5E` | igual | medio Efectivo |
| `mp` (Mercado Pago/QR) | `#2F5BE8` | igual | medio QR |
| `tar` (tarjeta) | `#4B5563` | igual | medio Tarjeta |
| `mix` (mixto) | `#B45309` | igual | medio Mixto |
| estado OK | fondo `#E3F6EF` / texto `#0B6A52` | `#10342A` / `#63D9B0` | ganancia, "cuadró", vinculado |
| estado error | `#FBE0DE` / `#A4231B` | `#3A1613` / `#FF918A` | deuda, falta, anular |
| estado aviso | `#FDECD6` / `#7D3B03` | `#392510` / `#F5B56C` | stock bajo, reserva de fijos |
| estado info | `#E0E9FF` / `#1D3A9A` | `#17254F` / `#A3BCFF` | etiquetas azules, Mercado Pago |
| `scrim` | `rgba(18,19,23,.46)` | `rgba(0,0,0,.62)` | velo de modales |
| `navbg` | `rgba(255,255,255,.66)` (`.9` levantada) | `rgba(14,15,19,.62)` (`.9`) | pastilla de navegación |

Degradé decorativo (solo texto del saludo de Inicio y caret): `linear-gradient(100deg,#3b6cff 0%,#8a5cf6 48%,#18c3a4 100%)`. Caret: `linear-gradient(#4f7cff,#b05cf0 40%,#ff6a5c 70%,#f6c343)`.
Tintes de categoría (círculo con inicial en tiles y búsquedas), `fondo / letra`: Bebidas `#E3F6EF/#0B6A52`, Almacén `#FDECD6/#7D3B03`, Fiambres `#FBE0DE/#A4231B`, Lácteos `#E0E9FF/#1D3A9A`, Golosinas `#F1E6FF/#6B2FB3`, Cigarrillos `#E6E9EF/#3B4150`, Panificados `#FFF0C9/#7A5A00`.

**Cambia respecto de `DISENO.md` vigente:** el acento en claro pasa a ser azul para acciones (la tinta queda como botón neutro oscuro); desaparecen el naranja del efectivo (ahora verde), el violeta del mixto (ahora ámbar) y todo degradé de tarjetas.

### 3.2 Tipografía

**Figtree**. En el mock se usa la variable (`wght 300..900`) para llegar al **450** de los títulos; ver excepción E-1 si la app sigue con fuentes estáticas.

| Rol | Tamaño / peso / tracking | Notas |
|---|---|---|
| `h1` página | 76 / 450 / −0,055 em / lh 1 | Se tipea (5.3). Venta: 60 |
| `h1` hero de Inicio | 92 / 450 / −0,058 em | máx. 1380 px, centrado |
| `h2` | 44 / 450 / −0,045 em / lh 1,04 | modal: 38 |
| `h3` | 28 / 450 / −0,035 em | |
| `lead` | 21 / 400 / lh 1,5 / `mute` | máx. ancho 860 |
| Cifra grande (`fig`) | 56 / 450 / −0,055 em, tabulares | Total de Venta 84; héroe 84–92 |
| Texto | 16–18 / 400–500 | filas 17–19 |
| Chico | 13–15 / 500–600 | etiquetas, metadatos |
| `eyebrow` | 15 / 600 / `mute`, con punto azul 8 px | reemplaza al viejo "MAYÚSCULAS +0,04 em" |
| Atajos (`kbd`) | 12 / 600, +0,02 em, fondo 9 % del color de texto, radio 8 | impresos en botones |

Siempre **cifras tabulares** en importes. `text-wrap: balance` en títulos.

### 3.3 Radios, espaciado, medidas

- **Radios:** pastilla `999`; modal `48`; hero/total `40–44`; tarjeta `36`; ticket de Venta `52`; tile `34`; fila `30`; campo `28`; lista agrupada `30`; nota `24`.
- **Espaciado de página:** gutter lateral **64** (Venta: 56 izq / 36 der); separación entre bloques **30**; entre tarjetas **14–16**; padding interno de tarjeta `30×34` (compactas `24×28`).
- **Alturas de control:** botón `56` (sm 44, xs 36, lg 76); chip `46` (sm 38); segmento `46` (pista con padding 5); campo `~72`; fila de lista `≥ 64`.
- **Sombras (solo estas):** modal `0 40px 100px rgba(13,16,23,.35)`; mega-menú `0 30px 60px rgba(13,16,23,.12)`; popover/dropdown `0 30px 80px rgba(13,16,23,.22–.25)`; pastilla levantada `0 10px 40px rgba(13,16,23,.1)`; hover de botón `0 14px 34px` (neutro `.2`, azul `rgba(47,91,232,.32)`); segmento activo `0 2px 10px rgba(13,16,23,.1)`; toast `0 20px 50px rgba(0,0,0,.3)`. Los bloques (`Superficie`) siguen **sin sombra**.
- **Resolución de diseño:** 1920×1080, mínimo digno 1366×768 (ver 14.2).

### 3.4 Íconos

Trazo único 24×24, grosor 2, sin relleno, redondeados (el set del celular, `IconoNs`). Tamaños: 14–16 (en pastillas/steppers), 18–22 (botones, listas), 24–28 (buscador), 36–44 (estados vacíos), 60–84 (estados grandes). Íconos usados por nombre en el mock: `home cart box wallet dots scan swap clip sliders cal down cash card search bell back chev chevd arrow plus minus check lock warn save calc x pc trash store clock print edit phone sun chart truck list percent wifi wifioff reload mp smoke user users tag file shield info bolt image key cloud star gear`. Los que falten en `IconoNs` se agregan con su path (`IconoPlz._trazos`).

---

## 4. Estructura de la ventana

```
┌───────────────────────────────────────────────────────────────┐ 40 px  barra de ventana (propia)
│ ns La Plazoleta·Nodo Sur   ● Caja abierta·Ana·desde 8:02  Copia…  — ▢ ✕ │
├───────────────────────────────────────────────────────────────┤
│   ╭─ pastilla flotante (68 px, top 14) ───────────────────╮    │
│   │ ns La Plazoleta │ [Venta] Inicio▾ Proveed.▾ … │ 🔍 🔔 ⚙ │    │
│   ╰───────────────────────────────────────────────────────╯    │
│  contenido (scrolleable; Venta no scrollea la pantalla)        │
└───────────────────────────────────────────────────────────────┘
```

Capas (de abajo a arriba): contenido → velo del mega-menú → mega-menú → pastilla → popover de notificaciones / buscador de funciones → modales → toast → cursor-pastilla. La barra de ventana va siempre encima de todo (z más alto salvo modales).

### 4.1 Barra de ventana (40 px) — `lib/ui/ventana/ventana_escritorio.dart`
Fondo `s`, texto 13,5/600 `mute`. Izquierda: logo "ns" (26 px) + "La Plazoleta · Nodo Sur". Centro: punto verde + "Caja abierta · {usuario} · desde {hora}" (o punto gris "Caja cerrada") y "Copia de hoy 8:00 ✓". Derecha: minimizar, maximizar, cerrar (46×34, hover `s2`; cerrar hover rojo `#C5221F` con ✕ blanca). **Cerrar con caja abierta pregunta antes** (no cambia, ver doc de ventana).

### 4.2 Pastilla de navegación flotante — `lib/ui/navegacion/navbar_superior.dart` (reescribir)
- Posición: `top = 40 + 14`, centrada, **máx. 1760 px**, alto **68**, radio 999, padding `0 12 0 18`, `gap 10`. Fondo de vidrio (`BackdropFilter` blur 18 + saturación 1,6) con borde interior de 1 px `navline`. **No ocupa el ancho entero**: flota con 40 px de margen.
- **Levantada**: cuando la pantalla scrolleó > 8 px, el fondo pasa a `navbg2` (`.9`) y suma la sombra de 3.3; transición `.3s`.
- Izquierda: logo "ns" 40 px + "La Plazoleta" 18/700 (la marca va acá; ya no se esconde).
- Centro (`links`, centrado, `gap 4`): **Venta** (pastilla azul, ícono carrito 20, `padding 0 24`, 16/600, blanca; activa = `blue-d`), **Inicio▾, Proveedores▾, Separaciones▾, Historial▾, Encargues▾**: 16/500 `mute`, alto 46, `padding 0 20`; hover y "abierto" = fondo `s` + texto `ink`; **activa (`aria-current`) = fondo `s`, `ink`, 600**; el chevron `▾` rota 180° (`.25s`) al abrirse.
- Derecha:
  - En **Venta**: botón `sm` tonal **"Cambiar de turno"** y botón `sm` oscuro **"Cerrar caja"**.
  - En el resto: chip `s` con punto verde con halo "Caja abierta · Ana" (o "Caja cerrada").
  - Siempre: **lupa** (círculo 46, `data-cur` "Buscar · Ctrl+F"), **campana** (con globito rojo y cantidad de pendientes) y **ajustes** (engranaje/`sliders`; `aria-pressed` cuando la pantalla es Configuración → fondo `ink`, ícono `paper`).
- **El orden de secciones y cuáles se ven sigue siendo configurable** (Configuración › Menú); Venta no se puede ocultar; Configuración es siempre el engranaje.
- **Búsqueda dentro de la pastilla (Ctrl+F, fuera de Venta):** las pastillas, la marca y los botones se desvanecen (`.25s`) y un campo de 22/450 ocupa toda la pastilla con un botón "Cerrar Esc"; debajo cae un panel de resultados (radio 36, máx. 1100 px, 6 productos con círculo de categoría, nombre, categoría y precio, flechas + Enter). Elegir un resultado **vuelve a Venta con el texto cargado** (no agrega al carrito). En Venta, Ctrl+F **enfoca el campo único** (nunca se esconde tras la lupa). Al cerrar vuelve vacío.

### 4.3 Mega-menú (antigravity)
Se abre al pasar el mouse por Inicio/Proveedores/Separaciones/Historial/Encargues (con 70 ms de retardo de intención) o al enfocar con teclado. **Venta no tiene.**
- Panel de **ancho completo de la ventana**, fondo `paper`, **esquinas inferiores 48**, sombra de 3.3, `padding 96 120 44` (los 96 de arriba dejan lugar a la pastilla, que queda por encima). Grilla `420px | 1fr | 1fr`.
- Columna 1: título `h3` 36/450 (balance), párrafo `mute` 16 y botón `sm` tonal "Ver {sección}".
- Columnas 2 y 3 (separadas por una línea `hair`): encabezado 14/600 `soft` ("Pantallas", "Acciones"); ítems de 18/450 con ícono 22 (`mute`), `padding 11×14`, radio 20, hover `s`, y a la derecha un dato chico (13 `soft`: "Alt+N", "IA", "Conteo físico").
- **Animación**: panel `opacity 0→1` `.2s` + `translateY(-14→0)` `.24s` con `quart`; **los ítems entran en cascada** (`translateY(10)→0`, `.4s`, retraso `60ms + 50ms*i`).
- **Velo**: el resto de la ventana se atenúa (`rgba(18,19,23,.12)` + `blur(2px)`, `.25s`).
- **Cierre**: al sacar el mouse del panel y de las pastillas (150 ms), con Esc, o al navegar.
- Contenido exacto de cada panel (título · descripción · [pantallas] · [acciones]):

| Sección | Título | Pantallas | Acciones |
|---|---|---|---|
| Inicio | Cómo va el negocio — "El día en una mirada y el mes contra los fijos." | Hoy · Este mes · Venta diaria de equilibrio | Nueva venta (Alt+N) · Registrar pago de un fijo · Cargar monto de un fijo |
| Proveedores | Proveedores y productos — "Lista, cuenta corriente, precios por ganancia y stock." | Proveedores y productos · Contar stock por góndola · Comparar precios | Nuevo proveedor · Edición masiva de precios · Leer una factura (IA) · Importar productos (CSV) · Promos |
| Separaciones | Qué separar hoy — "Cuánto apartar por proveedor y por caja, y lo que te queda." | Separaciones del día · Cierre de caja | Ganancia del día · Retirar ganancia · Productos sin costo (3) |
| Historial | Lo que pasó en la caja — "Ventas, movimientos y cierres; editá o anulá lo ya cobrado." | Ventas · Movimientos · Cierres | Cargar un día histórico · Reimprimir un ticket · Generar PDF del día |
| Encargues | Apartados y deudas — "Lo que un cliente pidió y está en el local, y lo que quedó debiendo." | Encargues · Deudas de clientes | Nuevo encargue · Cobrar una deuda |

> **Aclaración de alcance:** el mega-menú solo **agrupa accesos que ya existen** (pantallas y diálogos). No agrega funciones. Las únicas funciones que no existen hoy en la PC son las de 14.3.

### 4.4 Notificaciones (campana)
Popover anclado debajo de la campana (`right 130`, `top 128`, ancho 520, radio 40, sombra, entra `translateY(18)→0` `.26s quart`). Título "Notificaciones" + etiqueta "N pendientes". Tarjetas (cada una descartable con "Visto"):
1. **Arqueo** (ámbar): "Pasaron 2 horas desde el último arqueo" + botón "Hacer arqueo". Solo si el módulo de turnos está activo.
2. **Cobro de Mercado Pago sin venta** (azul): "Entró un cobro de $ 6.400 sin venta · hace 7 min. Solo avisa: no toca la caja ni el stock." (un cobro espera 5 min antes de avisar; contracargos y reclamos igual, con la venta cruzada si se puede).
3. **Falta separar** $ 295.000 (botón "Ver" → Separaciones).
4. **Versión nueva** disponible (se instala al cerrar la app).
Vacío: ícono ✓ 40 + "Sin novedades por ahora". Clic fuera o Esc cierra. Las de Mercado Pago siguen existiendo aunque el módulo de turnos esté apagado.

### 4.5 Buscador de funciones (Ctrl+K) — propuesta, ver 14.3
Panel central (ancho 820, `top 150`, radio 40, sombra) con campo de 22/450 en pastilla y lista agrupada ("Pantallas", "Acciones de caja", "Acciones", "Ayuda"), 22 entradas, flechas + Enter, ignora acentos y mayúsculas, máx. alto 640 con scroll, Esc cierra; velo detrás. Es el "Buscador de funciones" del celular llevado a la PC.

### 4.6 Atajos de teclado (todos con Alt para no chocar con la escritura)
`Alt+E/Q/D/X` medio de pago · `Alt+M` cobro manual (con canal QR/débito elegido) · `Enter` con el campo vacío cobra / con dropdown agrega · `Esc` cancela la venta entera (con el campo lleno, lo vacía primero) · `Alt+V` Varios · `Alt+I` ingreso rápido · `-` gasto rápido · `Alt+N` venta nueva · `Alt+S` siguiente venta · `Alt+C` caramelo del vuelto · `Ctrl+F` buscar · `Ctrl+K` buscador de funciones · `Inicio` vuelve a Venta (salvo escribiendo en un campo). Diálogo de ayuda "Atajos de teclado" (botón "Atajos" del mock; en la app, entrada en Configuración o `?`). Guardas existentes que **se mantienen**: AltGr no dispara atajos; cerrar un diálogo secundario **no roba el foco** del campo de búsqueda; agregar al carrito y cobrar **devuelven** el foco a la búsqueda.

---

## 5. Movimiento (catálogo completo)

Todo se implementa en `lib/ui/tema/movimiento.dart` (extender `Entrada`/`Pulso`) y se **apaga** con "reducir animaciones" del sistema o con Movimiento = Reducido. Curvas (nombre → cubic-bezier): `ease` = `(.2,.7,.1,1)`; `quart` = `(.165,.84,.44,1)`; `back` = `(.34,1.85,.64,1)`; `easeOutCubic` = `1-(1-t)³`.

### 5.1 Reglas de seguridad (obligatorias)
- Ninguna animación **retrasa** el foco, lo tipeado, el escaneo, el Enter ni el cobro. Los elementos aparecen ya clickeables aunque estén en fade (no se deshabilita nada).
- Lo que se reproduce al **entrar** a una pantalla no se vuelve a reproducir al actualizar datos (los tiles, líneas y tarjetas que no cambian **no se re-animan**).
- Listas largas: solo se escalonan las primeras 12–14; lo que aparece al scrollear entra sin retraso.
- Una sola cosa "llamativa" por zona de pantalla a la vez.

### 5.2 Cambio de pantalla
Salida: `opacity 1→0` y `translateY(0→-6)` en **140 ms**; recién entonces se monta la nueva (scroll arriba, pastilla sin "levantar"); entrada = los reveals/tipeo de la pantalla (no hay animación global de entrada). Un clic en la misma sección no re-anima salvo `force`. En Movimiento = Reducido el cambio es instantáneo.

### 5.3 Título que se tipea (antigravity `TypedHeader`)
Cada `h1` (y los `h2` marcados) se parte en caracteres (agrupados por palabra para no cortar palabras al saltar de línea). Arranca a los **140 ms**; cada carácter pasa de oculto a visible con paso `clamp(560/n, 14, 52) ms` (≤ ~0,56 s en total); el **caret** (ancho 0,055 em, alto 0,82 em, radio 3, gradiente de 3.1, parpadeo `1.1s steps(1)` entre 100 % y 15 %) se coloca después del último carácter visible; al terminar, 1,5 s después se desvanece (`.5s`). Texto accesible completo desde el primer cuadro (`aria-label`/`Semantics`). Con gradiente en un tramo (`<span class="grad">`), el gradiente cubre el tramo entero, no cada letra. Los títulos de Inicio "Este mes"/Configuración usan `data-typed-v` (arrancan al hacerse visibles, umbral 50 %).

### 5.4 Reveal escalonado (horsepos `.rv`)
`opacity 0→1` + `translateY(28→0)`; `.8s ease`; retraso `min(índice entre hermanos, 5) × 70 ms`; se dispara al entrar al viewport (umbral 8 %, margen inferior −4 %; bloques más altos que 80 % de la vista, apenas asoman). Post-reveal, las tarjetas con hover conservan `transform .5s ease`.

### 5.5 Microinteracciones
| Elemento | Efecto |
|---|---|
| Botón | hover `translateY(-2)` + sombra (`.3s ease`); `:active scale(.98)`, sin sombra |
| Botón azul | hover fondo `blue-d` + sombra azul |
| Tarjeta/`hv` | hover `translateY(-4)`, `.5s ease` |
| Chip | hover fondo `s` + `translateY(-1)`; activo = fondo `ink`, texto `paper` |
| Segmento | el activo se "levanta" (`paper` + sombra), `.25s ease` |
| Interruptor | pista 56×32, perilla 26 con resorte `back` `.35s`; pista a azul `.3s` |
| Tile de producto | hover `translateY(-3)` + `s2`; `:active scale(.98)`; entrada `.5s` desde `translateY(16) scale(.97)` con retraso `22 ms × min(i,14)` **solo** al mostrar/cambiar grilla |
| Contador de unidades del tile | aparece/cambia con `pop` (`.45s`) |
| Línea nueva del carrito | `translateY(10) scale(.96)→1`, `.4s ease` (solo la nueva); el aro azul de 2 px queda en la última agregada |
| Total de Venta / cifras vivas | *tween* de 320 ms (easeOutCubic) del valor anterior al nuevo + **pulso** `scale 1→1.045→1` `.5s` |
| Botón de medio | al elegirlo, el color **llena** con transición (`.3s`) y late (`pop .45s`) |
| Cobrar | hover sube 2 y sombra azul; desactivado `opacity .38` |
| Cerrar (✕) de modal | hover rota 90° (`.3s`) |
| Tilde "separado" | círculo vacío → lleno verde con tilde (`.25s`) |
| Cinta de chips (marquee) | `translateX` continuo, **48 s linear infinite**, pausa al pasar el mouse, máscara de 10 % en los bordes |
| Barras (gráfico por hora) | alto 0→valor en **1 s `ease`**, retraso `40 ms × índice`, al verse (umbral 40 %); pico en azul |
| Barra de progreso | ancho 0→valor en 1 s `ease` al verse |
| Cifras de Inicio/Separaciones/Cierre (`data-count`) | cuentan de 0 al valor en **1100 ms easeOutCubic** al verse (umbral 30 %); en pantalla ya vista no se repiten |
| Tablero 3D (Inicio) | `perspective 1800`, `rotateX((1−p)·16°)` y `scale(.93+p·.07)`, `transform-origin 50% 100%`, sombra `0 40px 90px -30px rgba(13,16,23,.28)`; `p = clamp((vh−top)/(vh·.75), 0, 1)` según el scroll |
| Titular "Este mes" | cada palabra pasa `opacity .2→1` (`.4s`) según `p = clamp((vh·.85−top)/(vh·.5+alto·.4), 0, 1)`; n palabras = `round(p·total)` |
| Placeholder del buscador de Venta | **se escribe solo**: frases rotativas ("Escaneá un código o buscá un producto", "200 queso barra", "coca 2,25 l", "7790001000011"), 48 ms/carácter, pausa 1,7 s, se borra a 22 ms; se detiene si el campo tiene foco o texto |
| Anillo de espera / spinner | `spin 1s linear infinite`; aro `ring 1.8s ease infinite` (escala .8→1.7, opacidad .7→0) |
| Tilde dibujado (cobrada, aprobado, caja cerrada) | `stroke-dashoffset` 60→0 en `.6s ease`, retraso `.15s` |
| Toast | entra `translateY(20→0)` con `back` `.45s` + fade `.3s`; visible 2,6 s |

### 5.6 Campo de partículas (horsepos `fx.js`)
`CustomPainter` + `Ticker`, **solo decorativo**. Cantidad `clamp(ancho·alto/3600, 110, 380)`. Cada partícula: ángulo, radio `R·rand^0.7` con `R = 0,55·diagonal`, velocidad angular `±0,00022 rad/ms`, ondulación radial `sin(t·.0006+fase)·6`, elipse `y·0,72`, largo 1,2–2,2 px (40 % son rayitas de 4–8 px), trazo 1,6 redondeado, opacidad .25–.95, color de la paleta. **Huyen del mouse**: radio 120 px, desplazamiento máx. 28 px con suavizado `0,12` (y vuelta `×0,9`). Se pausa fuera de pantalla y no corre si la pantalla está oculta. Paletas: `hero` (azul/violeta/rosa + grises; Inicio), `soft` (azul/lila + grises; encabezados de página y Venta, opacidad del contenedor `.55` en Venta), `ok` (verde agua, azul, amarillo, rojo, violeta; **venta cobrada** y **caja cerrada**), `blue`. Contenedor con máscara `linear-gradient(#000 40–55%, transparent)` para que se disuelva hacia abajo; altura 420 (560 en "Caja cerrada"). Debe poder apagarse (Configuración › Campo de partículas).
Dónde va: héroe de Inicio, encabezado de **todas** las pantallas de gestión, columna izquierda de Venta (detrás del título y buscador), modal "Venta cobrada", pantalla "Caja cerrada".

### 5.7 Cursor-pastilla (antigravity `CustomCursor`)
Solo con mouse (`hover: hover`, puntero fino). Sobre elementos marcados (`data-cur`: tiles de producto "Agregar", botón "Nueva venta", buscador "Escribir o escanear", lupa "Buscar · Ctrl+F") aparece una pastilla `paper` con ícono 18 y texto 14,5/600, alto 42, `padding 0 18 0 12`, contorno 1 px `line` y sombra `0 8px 30px rgba(13,16,23,.18)`. Entra con escala 0→1 `.3s back`; sigue al mouse con *lerp* `0,24`/cuadro, **desplazada (+18, +20) px** (el puntero real **no se oculta**: en un POS la precisión manda). Desaparece al salir del elemento. No aparece sobre tiles sin stock ni elementos deshabilitados. Se apaga en Configuración.

### 5.8 Scroll suave (antigravity `ScrollSmoother`, `smooth .6`)
En las pantallas scrolleables (Inicio y páginas de gestión), la rueda del mouse mueve un **destino** y el scroll lo persigue con *lerp* `0,12`/cuadro (~0,5–0,6 s de inercia); `deltaY` se normaliza por la escala de la ventana; `deltaMode=1` (líneas) ×40. **No** intercepta: listas internas que todavía pueden scrollear en esa dirección (carrito, grilla, tablas, modales), `Ctrl+rueda`, scroll horizontal ni toque/trackpad con inercia propia. Se apaga en Configuración. En Flutter: `Listener` + `PointerSignalEvent` con `animateTo(...)` o un `ScrollPhysics` propio; respetar las reglas anteriores.

### 5.9 Reducción de movimiento
Con `MediaQuery.disableAnimations` o Movimiento = Reducido: sin tipeo (texto completo), sin reveal (todo visible), sin partículas animadas (campo estático opcional), sin marquee, sin cursor-pastilla, sin scroll suave, sin 3D (el tablero queda plano), cifras en su valor final, transiciones de ~1 ms. Los **cambios de estado** (selección, foco) siguen siendo visibles pero instantáneos.

---

## 6. Componentes

Cada uno ya existe como clase en el mock (entre paréntesis). Implementar como widgets reutilizables en `lib/ui/comun/` y `lib/ui/tema/`.

- **Botón (`btn`)**: alto 56 (`sm` 44, `xs` 36, `lg` 76), `padding 0 28`, 17/600, pastilla. Variantes: `prim` (tinta; en oscuro azul), `blue`, `dark` (ink/paper), `ton` (fondo `s`, sobre tarjeta gris pasa a `paper`; hover `s2`), `out` (transparente + contorno 1,5 `line`), `red` (fondo `bbg`, texto `b`), `wide` (100 %). Con flecha: círculo 44 (lg 54) `rgba(255,255,255,.2)` a la derecha, `margin-right −14`. Desactivado: `opacity .38`, sin eventos.
- **Chip (`chip`)**: alto 46 (sm 38), `padding 0 22`, 16/500, fondo `paper` + contorno `line`; `aria-pressed` = fondo `ink`.
- **Segmento (`seg`)**: pista `s` padding 5; botones alto 46 `padding 0 24` 16/600 `mute`; activo `paper` + sombra. `fill` = ocupa el ancho, botones iguales.
- **Etiqueta (`tag`)**: alto 30, `padding 0 13`, radio 999, 13,5/600. Tonos: neutro (`s2`/`mute`), `g`, `b`, `w`, `i`, `dark`.
- **Tarjeta (`card`)**: fondo `s`, radio 36, `padding 30×34`. Variantes `w/g/b/i` (fondo+texto de estado), `line` (fondo `paper` + contorno 1,5). **Hero (`hero`)**: fondo `hero`, texto `onhero #fff`, subtítulo `rgba(255,255,255,.62)`, radio 40; `hero.blue` = azul.
- **Lista agrupada (`list`)**: contenedor con radio 30, fondo = `hair` y filas de 1 px de separación (`gap:1`), filas `s`. **Fila clave-valor (`kv`)**: `padding 18×26`, min-alto 64, 17 `mute` + valor `600 ink` tabular.
- **Campo (`field`)**: fondo `s`, radio 28, `padding 14×24 12`; etiqueta 13/600 `mute` arriba; valor 21/500; foco = anillo 2,5 px `focus #3B6CFF`. **Grande (`field big`)**: valor 56/450 tabular (importes, conteos).
- **Interruptor/fila (`tg`)**: fila `padding 18×26`, min 76, título 18/600, detalle 14,5 `mute`, pista 56×32.
- **Nota (`note`)**: radio 24, `padding 16×22`, 15 `mute`; variantes `w g b i`.
- **Fila de lista maestra (`rowb`)**: radio 30, `padding 16×22`, círculo de ícono 46 + título 19/550 + detalle 14,5; seleccionada = fondo `blue-l` + aro 2 px azul; hover `s2` + `translateY(-2)`.
- **Tile de producto (`tile`)**: ver 7.1.
- **Línea de carrito (`cl`)**: ver 7.1.
- **Stepper (`stp`)**: pastilla `s` con botones circulares 34 y valor central (min 54, 16/600 tabular); **doble clic en el valor** abre "Cantidad exacta".
- **Barra (`bar`)**: alto 16, pista `s3`, relleno animado.
- **Ticket (`ticket`)**: fondo `s`, radio 44, `padding 34×38`; separadores punteados 2 px `line`.
- **Estado vacío (`empty`)**: ícono 44 (trazo 1,6) + texto 19 `mute` centrado; en el carrito, con un aro pulsante detrás del ícono.
- **Modal**: ver 8. **Toast**: alto 60, pastilla `toast` (`#121317`; oscuro `#2A2E38`), texto 17/600 con tilde, abajo al centro a 34 px, 2,6 s.
- **Cursor-pastilla, partículas, título tipeado, cifra que cuenta, barras, marquee**: sección 5.

---

## 7. Pantallas

Para cada una: **qué es, layout, contenido, interacciones, estados**. Datos de ejemplo del mock = los de `REGLAS-NEGOCIO`/celular (ver apéndice A). "Archivos" = dónde tocar en `lib/ui/`.

### 7.1 Venta (pantalla principal; arranca acá) — `venta/pantalla_venta.dart`, `columna_busqueda.dart`, `columna_carrito.dart`, `columna_cobro.dart`
Pantalla **fija** (no scrollea; `fixed`). Grilla `1fr | 640 px`, `gap 28`, `padding 122 36 30 56`.

**Columna izquierda**
1. Fila superior: `eyebrow` "Caja abierta · {usuario} · lunes 5 de octubre" + `h1` **"Vender"** 60 (tipeado) a la izquierda; a la derecha dos etiquetas: "61 ventas hoy" (info) y "Alt+N venta nueva". Campo de partículas `soft` detrás (opacidad .55).
2. **Buscador gigante** (`sbig`): alto **84**, pastilla `s`, ícono lupa 28, campo 24/450, `kbd` "Ctrl+F" a la derecha; foco = anillo azul 3 px + fondo `paper`. Placeholder tipeado (5.5). A su derecha, dos botones `ton` de alto 84: **"Varios · Alt+V"** y **"Gasto o ingreso · Alt+I"**. **Foco al arrancar.** Dropdown **anclado al campo** (radio 36, sombra, `padding 12`, entra `up .22s`): hasta **7** filas con círculo de categoría 40, nombre 21/450, stock (15 `mute`) y precio (21/600, ancho 110); flechas + Enter; una sola coincidencia viene preseleccionada. "Sin coincidencias" si no hay (dar de alta un producto **nunca** es desde acá).
3. **Categorías** (`vcats`): chips "Más vendidos" (entrada por defecto, calculada con el historial real sin anuladas; sin historial muestra el catálogo entero), "Todos" y una por categoría.
4. **Grilla** de productos: **5 columnas**, `gap 14`, scroll propio (`padding` para no cortar hover), tiles de min-alto **168**, radio 34, `padding 20×22`:
   - Círculo de categoría 44 (inicial) arriba a la izquierda.
   - Si está en el carrito: fondo `blue-l`, aro azul 2 px y **contador** arriba a la derecha (pastilla azul 30 alto; pesables muestran gramos, ej. "250 g").
   - Nombre 18/500 (máx. 2 líneas) y precio 27/500 tabular; pesables con "/kg". **"Quedan N"** (etiqueta ámbar) si el stock < 15 u. y no es pesable; **"Sin stock"** (rojo) y el tile queda atenuado (`opacity .45`) y **no se puede agregar** ("Sin stock: no se puede agregar").
   - Clic agrega 1 (pesables: 250 g). Cursor-pastilla "Agregar".

**Columna derecha — el ticket** (aside `s`, radio **52**, `padding 22`, alto completo, `gap 14`)
- **Pestañas de ventas abiertas** (`vtabs`): "Venta 1 ③ · Venta 2 ② · + Nueva Alt+N · … · Ver abiertas". La activa = `paper` + sombra. Son borradores persistentes (no descuentan stock ni tocan la caja hasta cobrar; sobreviven a cambiar de pantalla o cerrar la app). **No se puede cerrar caja ni cambiar de turno con ventas abiertas con productos.**
- **Carrito** (scrolleable, `gap 6`): una línea por producto (`cl`, fondo `paper`, radio 28, grilla `1fr auto auto auto`): nombre 17/500 (**2 líneas**) + debajo "$ 2.100 c/u" (pesables: "$ 14.600 el kilo") 13 `soft`; **stepper** (− / cantidad o gramos / +; en pesables ±50 g; restar en 1 unidad saca la línea); subtotal 19/600 tabular (mín. 96); tacho. Última agregada con aro azul. **Nombre en rojo** si el stock quedó en 0 o negativo (se vende igual). Doble clic en la cantidad → "Cantidad exacta". Vacío: ícono scan con aro pulsante + "Escaneá un código o buscá un producto para empezar la venta".
- **Total** (`tot`, hero, radio 44, `padding 20×30`): línea "Total a cobrar" + botón pequeño **Descuento** (abre el diálogo; si hay descuento dice "Cambiar descuento"); importe **84/450** con *tween*+pulso; debajo, etiquetas (30 alto, `herochip`) **solo cuando corresponden**: "Descuento 10 % −$ 1.625", "Recargo cigarrillos +$ 300", "Redondeo +$ 50".
- **Medios de pago**: grilla **2×2**, `gap 10`, botones de alto 72, radio 30, fondo `paper`: círculo de ícono + nombre 20/600 + atajo `ALT+E/Q/D/X` 12. Elegido = se llena con su color (`efe`, `mp`, `tar`, `mix`) y texto blanco. Efectivo · QR · Tarjeta · Mixto. **Ninguno elegido ⇒ "Cobrar" desactivado** (una venta nueva arranca sin medio).
- **Cobrar**: pastilla azul de alto 78, 24/600, "Cobrar" + `kbd` Enter, círculo con flecha a la derecha. Debajo, **solo con QR o Tarjeta elegidos**: botón `sm out` "Cobrar a mano, sin terminal · Alt+M" (reserva 44 px de alto siempre para no mover nada).
- Si el carrito es más largo que el espacio, **solo el carrito scrollea**; total, medios y Cobrar quedan siempre a la vista.

**Cálculo (no cambia, ver 11.1):** bruto → descuento (sobre el total, nunca por línea) → recargo de cigarrillos (solo con medio virtual) → redondeo (solo efectivo y mixto).

**Estados clave:** vacía · con búsqueda · con pesable (`200 queso` filtra solo pesables y muestra el subtotal calculado: "$ 1.960 por 200 g") · con cigarrillos y QR (recargo) · caja cerrada (al entrar aparece "Abrir caja" sin poder cerrarse) · varias abiertas.

**Teclado:** 4.6. **Escáner:** código exacto (8–14 dígitos) + Enter agrega 1 y vuelve a sumar si se repite; código desconocido → toast "Sin coincidencias".

### 7.2 Inicio — `dashboard/pantalla_dashboard.dart` (+ `equilibrio/` para "Este mes")
Pantalla **scrolleable**, sin padding de página. Secciones:
1. **Héroe** (centrado, `padding-top 176`, campo de partículas `hero` detrás): pastilla "**Hoy** · Lunes 5 de octubre · caja abierta desde las 8:02"; `h1` 92 **"Hola, {quien abrió la caja}. Hoy llevás [$ 482.300]"** (tipeado; el importe con gradiente; sin caja abierta: "Inicio"); `lead` "Cobraste 61 ventas, ganaste $ 168.900 y te falta separar $ 295.000 para los proveedores."; botones `lg`: **"Nueva venta →"** (azul, con círculo-flecha) y **"Ver separaciones"** (tonal); línea chica "Cambio de turno a las 14:00 · próxima copia a las 20:00".
2. **Tablero** dentro del marco 3D (`stage3d`, tarjeta `s` radio 56, `padding 30`), que **se endereza al scrollear** (5.5). Grilla `1.25fr 1fr 1fr`:
   - Fila 1: **héroe "Hoy vendiste"** ($ 482.300, 84/450, cuenta de 0; "Ganancia $ 168.900" en verde; barra efectivo/Mercado Pago 48/52 que se llena; cifras de cada medio) · **2×2 de indicadores**: Ganancia hoy, Tickets (61), Ticket promedio, **Falta separar** (tarjeta ámbar clickeable → Separaciones) · **Más vendidos hoy** (1–5 con unidades e importe).
   - Fila 2: **Ventas por hora** (13 barras 8–20 h, pico en azul, etiqueta "pico 18 h") · **Stock bajo** (4 productos con etiqueta; "Sin stock" en rojo) · **Encargues y deudas** (3 filas + "Ver todos").
3. **Cinta de avisos** (marquee): chips clickeables que repiten lo pendiente ("Falta separar…", "4 productos con stock bajo", "3 encargues para hoy", "Cobro de Mercado Pago sin venta: $ 6.400", "Versión … disponible", "Última copia…", "Redondeo de hoy…", "Ganancia por hora…").
4. **"Este mes · octubre"** (`#mes`, ancla de "Este mes" del mega-menú, que scrollea hasta acá con suavidad): `eyebrow`; **titular que se enciende por palabras**: "Llevás cubierto el 78 % de los fijos del mes y te faltan $ 418.000 para el equilibrio."; 4 tarjetas: *Ganancia bruta del mes* (hero) · *Fijos cubiertos* (78 % + barra) · *Venta diaria de equilibrio* · *Fijos pendientes de pago* (ámbar); dos columnas: **Estado de resultados** (ventas, costo de la mercadería, ganancia bruta con %, fijos, variables, resultado, sueldo objetivo, "queda para el negocio", ya retirado, **retirable hoy** + botón "Retirar ganancia") y **Margen necesario** (2 campos: venta deseada, ganancia deseada; margen necesario vs. actual; etiqueta "Tu margen alcanza"/"Te faltan N puntos"; nota de que el precio sugerido no cambia nada solo); lista **Fijos del mes** (nombre, importe, estado Pagado/Pendiente/Falta cargar con "Registrar pago"/"Cargar monto") + "Nuevo concepto".
Aviso de la regla 12: si falta cargar un fijo, la tarjeta que depende de él muestra un aviso en vez de un número.

### 7.3 Proveedores — `proveedores/*`
Página (`phead` con `eyebrow` "Lista, cuenta corriente y precios" + `h1` tipeado). Acciones: **Promos**, **Importar CSV** (tonales) y **Nuevo proveedor** (oscuro, ícono +). Grilla `520 px | 1fr`.
- **Izquierda**: buscador `sbig` (alto 64) "Buscar un proveedor…", chips "Todos / Con deuda", lista de filas `rowb` (círculo-camión, nombre, "N productos · pedido martes", y a la derecha etiqueta **"Le debés $ X"** roja o **"Al día"** verde). Seleccionada = azul claro.
- **Derecha (detalle)**: fila de dos bloques —
  (a) tarjeta con nombre `h2` 40, "Editar", "Pedido {día} · entrega {día} · colchón de reposición N %" y botones tonales: **Edición masiva, Comparar precios, Leer una factura, Contar stock, Avanzado**;
  (b) **hero de cuenta corriente**: "Cuenta corriente · le debés" + importe 60 + **"Pagar a proveedor"** (azul) y "Ver movimientos".
  Debajo, encabezado "Productos de {proveedor}" + "Nuevo producto", y **tabla** (en lista redondeada, encabezado fijo): Producto (+ etiqueta "pesable") · Costo · Precio · **Ganancia** (etiqueta "N % gan." verde ≥ 30, neutra 22–29, ámbar < 22; la ganancia es **sobre el precio**) · Stock (ámbar < 15; "Sin stock" rojo) · Editar.
- Cambiar de proveedor re-renderiza solo el detalle (con reveal); la lista no se re-anima.
- "Contar stock" lleva a la subpantalla 7.9.

### 7.4 Separaciones — `separaciones/pantalla_separaciones.dart`
Página con `eyebrow` "Solo lo de hoy · lunes 5 de octubre". Acciones: **Ganancia** (tonal), **Retirar plata** (oscuro). Cuatro tarjetas (cifras que cuentan): **A separar del cajón** (hero) · **A separar de Mercado Pago** (hero azul) · **Reserva diaria de fijos** (ámbar) · **Te queda** (verde). Debajo: `sec` "A separar por proveedor" + "Separaste $ X de $ 295.000"; chip ámbar "⚠ 3 productos sin costo" (abre el diálogo para cargarlos); **lista de filas** (min 84): tilde circular a la izquierda (lleno verde al marcar y el nombre se **tacha** y atenúa), nombre 20/550 + "Pedido martes · entrega jueves", etiqueta de caja (**Cajón** verde / **Mercado Pago** azul) e importe 22/600. Marcar actualiza el progreso al instante. Solo lo de hoy; el redondeo y la lata no se mezclan acá.

### 7.5 Historial — `historial/*`
`h1` "Historial" + acciones: **"Cargar día histórico"** y segmento **Ventas · Movimientos · Cierres**. Debajo, chips **Hoy / Ayer / Últimos 7 días / Este mes** (no en Cierres) y buscador (420).
- **Ventas · Hoy**: grilla `620 | 1fr`. Izquierda: encabezado hero ("5 ventas · hoy" + total) y filas (círculo con ícono del medio, "Venta #1181", "12:48 · Efectivo", importe). Derecha: **ticket** de la seleccionada (título 38, fecha · hora · cajero, etiqueta del medio, líneas, subtotal, redondeo, **Total 32/450**, ganancia verde) con botones **Reimprimir** (toast "Ticket enviado a la impresora"), **Editar** (→ 7.8) y **Anular venta** (rojo → diálogo con motivo obligatorio).
- **Ventas · otros períodos** y **Cierres**: lista de días (fecha, N ventas, importe, etiqueta **Cuadró / Faltaron $ X / Sobraron $ X**) → clic abre **Detalle del día** (7.7).
- **Movimientos**: tabla Hora · Tipo (Gasto/Ingreso/Pago a proveedor/Retiro) · Motivo · Caja (Cajón/Lata/Mercado Pago) · Monto (rojo −, verde +).
- Anular **solo mientras la sesión de caja siga abierta**; revierte stock y caja, **nunca borra** la venta; si se cobró por Mercado Pago, se devuelve por Mercado Pago.

### 7.6 Encargues — `encargues/pantalla_encargues.dart`
`h1` "Encargues" + **Nuevo encargue** (oscuro). Tres tarjetas: **Apartados** (hero, cuenta), **Deudas por cobrar** (ámbar), **Para hoy**. Sección **Apartados**: lista (círculo calendario, cliente 19/600, detalle, importe, **Entregar** azul, **Cancelar** rojo — devuelve el stock). Sección **Deudas**: lista (inicial del cliente, detalle, importe, **Cobrar**). Apartar **descuenta el stock en el momento**; "Entregar" abre un diálogo con **"Cobrar ahora (abre la venta con eso cargado)"** y **"Entregar y anotar deuda"** (el fiado se unificó acá).

### 7.7 Detalle de un día cerrado — `historial/pantalla_detalle_dia.dart`
Desde Historial › Cierres. `eyebrow` "Historial · Cierres", `h1` con el día, etiqueta del resultado, **Generar PDF** y **Volver a Cierres**. Cuatro cifras: **Vendido** (hero, "72 ventas"), **Efectivo**, **Mercado Pago**, **Ganancia** (verde). Debajo: tabla de ventas (# · hora · medio · total · reimprimir/editar) a la izquierda; a la derecha tarjeta **"Vendido por proveedor"** y tarjeta **"Anuladas"** (con motivo).

### 7.8 Editor de una venta cobrada — `historial/pantalla_editor_venta.dart`
`eyebrow` "Venta #1181 · 12:48", `h1` "Editar venta", "Volver al historial". Izquierda: tarjeta **Productos** (líneas con stepper, tacho, "Agregar producto") y tarjeta **Medio de pago** (segmento Efectivo/Mercado Pago/Débito/Mixto). Derecha: hero **Total corregido** (con *tween*) + "Original $ 16.300 · diferencia ±$ X", nota ámbar ("Al guardar se revierten el stock y la caja de la venta original y se vuelven a aplicar… Queda registrado quién y cuándo"), **Guardar cambios** (azul, vuelve a Historial con toast "Venta #1181 corregida") y **Descartar cambios**.

### 7.9 Contar stock por proveedor — `stock_proveedor/*`
Desde Proveedores › "Contar stock" (y mega-menú). `h1` "Contar stock · {proveedor}" + Volver. Cuatro tarjetas: **Contados** (n/n), **Con diferencia** (ámbar si hay), **Falta, a costo**, **Tilde "está igual"** (botón "Marcar todo igual"). Chips **Todos / Con diferencia / Agotados primero**. Tabla: Producto (+código) · Dice el sistema · **Contado** (stepper, o tipeado) · **Diferencia** (etiqueta verde "igual", ámbar +N, roja −N). **Nada toca la base hasta "Aplicar ajustes"** (azul, abajo a la derecha); cada ajuste deja rastro en `movimientos_stock`.

### 7.10 Cargar un día histórico — `carga_historica/*`
Desde Historial. Producto por producto (no planilla). Izquierda: tarjeta **Fecha del día** (chips de fechas + nota "el costo se estima con el costo de hoy; después se puede corregir") y tarjeta de **búsqueda** con chips de productos para agregar. Derecha: **ticket** "Venta del 2 de octubre" con líneas (stepper, tacho), **Total**, segmento de medio y **Guardar venta**. Mismo espíritu que Venta pero deliberadamente más simple (sin atajos).

### 7.11 Cierre de caja — `cierre/*`
Pantalla de **foco**: **sin pastilla de navegación**; arriba logo + "Paso N de 2" + "Volver a Venta" (hasta el paso 3). Columna centrada de 900 px. **No se puede cerrar sin contar.**
1. **Paso 1 — Contar (a ciegas):** `eyebrow` "Cierre obligatorio · conteo a ciegas", `h1` 64 "¿Cuánta plata hay en cada caja?", lead. Si hay ventas abiertas con productos: nota ámbar con **"Descartar"** y el botón de confirmar queda desactivado. Campo grande **Efectivo contado (cajón)** (con chips "Cuadra justo", "$ 250.000", "$ 255.500"), campo **Mercado Pago contado (según la app)** con botón **"Traer saldo"** (llena el saldo real de Mercado Pago y queda editable) y campo **Lata de cigarrillos contada**. Nota con candado: la diferencia y la separación de cigarrillos se ven al confirmar. **Confirmar conteo** (azul) desactivado hasta tener efectivo.
2. **Paso 2 — Resultado:** `h1` dinámico ("Cuadró el cajón" / "Faltan $ X en el cajón" / "Sobran $ X…"); hero **Diferencia del cajón** (importe 72 + etiqueta de tono); tres tarjetas: **Mercado Pago** (la diferencia suele ser la comisión), **Lata de cigarrillos**, **Redondeo de hoy** (línea informativa, no es descuadre); lista (debería haber / contaste / fondo para el vuelto de mañana / separación de cigarrillos / reserva de fijos del día); tarjeta **"Mercado Pago según Mercado Pago"** (cobrado en la app, comisiones, neto, cobros sin venta, ventas sin cobro; **nunca frena el cierre**); **Cerrar caja** (azul) y "Volver a contar".
3. **Paso 3 — "Caja cerrada":** celebración: campo de partículas `ok` (560 alto), círculo verde 150 con tilde dibujado, `h1` 84 tipeado "Caja cerrada", lead con el resumen del día y la copia, botones **Cerrar el sistema** y **Volver a Venta** (reabre y fuerza el diálogo **Abrir caja**).
Reglas: caja esperada = inicial + efectivo de ventas − gastos en efectivo (**el redondeo no se suma aparte**); MP esperado = inicial + pagos por MP − gastos con MP; la lata se arquea igual; un día cerrado se puede reabrir con confirmación; si se termina tarde el día queda abierto y se cuenta a la mañana siguiente.

### 7.12 Configuración — `configuracion/*`
Página con `eyebrow` "5 grupos, 16 secciones", `h1` y buscador "Buscar un ajuste…" (filtra secciones por palabras clave, ignora acentos). **Dos paneles**: izquierda **navegación vertical** (380 px; encabezados de grupo 13/700 mayúsculas `soft`; secciones como filas pastilla alto 50 con chevron, la activa `ink`/`paper`) y derecha el **contenido de la sección** (máx. 1000 px) con `eyebrow` del grupo, `h2` tipeado, descripción y controles. Grupos y secciones:
- **Negocio:** Comercio (nombre, rubro, encabezado del ticket, logo, imprimir logo) · Usuarios (lista con rol; renombrar; agregar).
- **Caja y cobros:** Caja y redondeo (redondear efectivo; paso $ 50/100/200; fondo fijo; reserva diaria de fijos; día del retiro semanal) · Cigarrillos (primer atado 300, adicional 100, suelto 50; ganancia fija por atado ~1.000; "Distribuidora cobra solo en efectivo") · Vuelto (producto del botón: Caramelo; atajo Alt+C) · Medios de pago (Efectivo, Mercado Pago [QR+débito+crédito], Mixto; renombrar).
- **Productos:** Ganancia por categoría (stepper % por categoría).
- **Equipos y cuenta:** Cuenta de Nodo Sur (Google, negocio, sucursal, miembros, sincronización, interruptor de nube, desconectar) · Impresión y posnet (impresora, carpeta de PDF, "Cobrar e imprimir por Nodo Sur", terminal Point, token local avanzado, **vista previa del ticket** en monoespaciada, probar impresión/terminal) · Celular (código de 6 dígitos grande en tarjeta hero, vinculados, descargar APK) · Asistente IA (clave Gemini, "Probar y guardar", interruptor) · Respaldo (carpeta, última copia, copia automática, hacer copia, restaurar con confirmación, últimas copias) · Versión (instalada, canal Estable/Beta, actualizar en 3 pasos).
- **Apariencia:** **Tema y movimiento** (Claro/Oscuro/Automático **en vivo**; Completo/Reducido; interruptores de partículas, cursor-pastilla y scroll suave) · Menú (orden ↑↓ y mostrar/ocultar; Venta no se oculta) · Módulos (turnos y arqueo cada 2 h, encargues, fiado, Point).

---

## 8. Diálogos (modales al centro) — `lib/ui/comun/modal.dart` (reescribir estilo)

**Contenedor:** velo `scrim` + blur 6 (`.25s`); modal centrado, ancho **760** (`n`: 620; `w`: 1060), radio 48, `max-height = alto−100`, sombra; entra `translateY(22→0) + scale(.96→1) + fade`, `.32s ease`; encabezado `padding 36×40` con `h2` 38 + subtítulo 17 `mute` y **✕** (46, rota al hover); cuerpo scrolleable `padding 14×40`, `gap 14`; pie `padding 16×40×36` con botones **apilados** a ancho completo: primario `lg` (azul; rojo para destructivo) y secundario `out` "Cancelar" (o fila de 2 en el editor de producto). **El velo cierra**, salvo diálogos marcados `nodismiss` (terminal Point y "Abrir caja"). **Esc cierra** (mismas excepciones). Enter confirma el primario (con guarda: no confirma en los primeros 350 ms ni con tecla repetida, para no auto-confirmar el Enter que lo abrió). Al abrir, foco al primer campo.

Catálogo (nombre en el mock → contenido):

**Caja / Venta**
- `efectivo` **Cobrar en efectivo**: hero con el total (72); campo grande **"Con cuánto paga"**; chips *Justo* y los siguientes billetes ≥ total (hasta 4, entre múltiplos de 1.000/5.000/10.000 y 20.000/50.000); tarjeta **vuelto** (verde "Dale el vuelto $ X" / roja "Faltan $ X"); si el vuelto es **exactamente $ 100**: nota ámbar + botón **"Dar caramelo · Alt+C"** (agrega la línea y actualiza). Confirmar cobro.
- `canal` **QR/Tarjeta**: hero azul con el total; segmento **QR · Débito · Crédito**; nota ("el crédito va siempre en 1 pago y sin recargo…"; "QR, débito y crédito son un solo medio en la caja: Mercado Pago"); botones **Cobrar con la terminal**, **Cobrar a mano (Alt+M)**, Cancelar.
- `terminal` **Terminal Point** (sin ✕, no se cierra con el velo): estados **esperando** (anillo pulsante + spinner, "Mandamos la orden de $ X (QR). La orden vence a los 2 minutos."), **confirma** ("Confirmá en la terminal"), **aprobado** (círculo verde + tilde dibujado; cierra solo a los 0,9 s y abre *Venta cobrada*), **rechazado**, **venció** (2 min) y **sin conexión**, estos tres con **Reintentar** / **Cobrar a mano** / **Cancelar**. En el mock avanza solo (2,8 s → 2,6 s → aprobado) y hay una **barra "Solo del mock · simular"** (ver E-3).
- `mixto` **Pago mixto**: hero con total; campo grande **"Parte en efectivo"**; chips *Mitad / $ 10.000 / $ 20.000*; lista "En efectivo" (verde) / "Con Mercado Pago (el resto)" (azul); el recargo de cigarrillos se aplica **completo**. Al cobrar pasa al diálogo de canal para la parte virtual.
- `cobrada` **Venta cobrada**: partículas `ok`, círculo verde 132 + tilde dibujado, importe 80, "Venta #N · {medio}{ · cobrada a mano}{ · vuelto $ X}"; botones **Nueva venta** (azul; cierra, descarta la venta cobrada de las abiertas o la deja vacía) e **Imprimir ticket**.
- `descuento`: segmento **Porcentaje % / Monto $**; campo grande; chips 5/10/15/20/30 %; lista Subtotal / Descuento / **Total con descuento**; **Aplicar** y **Quitar descuento**.
- `abiertas` **Ventas abiertas**: lista (nombre, "N productos · medio", total, **Abrir**, **Descartar**), nota sobre cierre/turno, **Nueva venta · Alt+N**.
- `cantidad` **Cantidad / Peso en gramos**: campo grande con selección; chips 100/200/250/500/1000 g; subtotal en vivo.
- `varios` **Varios**: monto suelto; chips $ 500/1.000/2.000/5.000; "No descuenta stock y queda marcado para revisar al cierre".
- `movimiento` **Gasto o ingreso**: segmento Gasto/Ingreso, segmento **Cajón normal / Lata de cigarrillos / Mercado Pago**, monto, **motivo obligatorio** con chips sugeridos (gasto: Proveedor, Limpieza, Fletes, Retiro, Otro; ingreso: Cambio, Aporte del dueño, Cobro de deuda, Otro).
- `arqueo` **Arqueo intermedio** (a ciegas → resultado con diferencia y tono).
- `apertura` **Abrir caja** (sin ✕): tres campos precargados con lo último contado (caja normal $ 30.000, lata $ 41.500, Mercado Pago $ 250.800), nota; **Abrir caja**.
- `turno` **Cambiar de turno** (3 pasos): elegir quién entra (+ nota ámbar si hay ventas abiertas con productos → bloquea) → **contar el cajón** a ciegas → resultado (esperado/contado/fondo) → "Abrir el turno de {nombre}".
- `atajos` **Atajos de teclado** (lista de 4.6).

**Proveedores:** `nuevoProv` · `editarProv` · `avanzadoProv` (solo cobra en efectivo; excluir de reposición) · `pagarProv` (monto + chips *Todo*/*Mitad* + **de dónde sale la plata**: Cajón / Mercado Pago / Lata / Fuera de la caja) · `ctaCte` (movimientos: compras restan, pagos suman) · `edMasiva` (segmento: Subir precio % · Subir costo % · Cambiar proveedor · Cambiar categoría; **previsualiza cada precio nuevo** `ceil`; aviso ámbar si ≥ 50 %) · `csv` (zona de arrastre + resumen nuevos/actualizados/errores) · `promos` (lista + **"Sugerir promos con IA"**: "se llevan juntos (90 días)" con "Crear"; la IA solo sugiere) · `comparar` (costo por proveedor, "Más barato", % extra, nota de margen) · `factura` (**lectura de prueba**: renglones vinculados/a revisar; no actualiza costos sola) · `editarProd` (1060 px: nombre, código, costo, **ganancia sobre el precio** con chips 20–40 % que recalculan el precio con `ceil(costo/(1−g))`, precio editable, aviso "Ganás $ X por unidad" verde/ámbar < 20 %, stock actual/mínimo, interruptor **Pesable**, **historial de precios**).

**Separaciones / Inicio:** `gananciaProv` (tabla Vendido/Costo/Ganancia por proveedor) · `retirar` (monto, de dónde; aviso si supera lo retirable) · `sinCosto` (campo de costo por producto) · `pagoFijo` · `nuevoFijo`.

**Historial / Encargues:** `anular` (nota + motivo obligatorio + chips; botón rojo) · `nuevoEnc` (cliente, para cuándo, producto, seña) · `entregarEnc` · `cobrarDeuda` (monto + Efectivo/Mercado Pago).

**Configuración:** `renombrar` · `restaurar` (nota ámbar; botón rojo) · `actualizar` (3 pasos: novedades → barra de descarga → "Lista para instalar").

---

## 9. Estados vacíos, errores y avisos
- Sin coincidencias en búsqueda: "Sin coincidencias" (dropdown, listas); nunca alta rápida desde Venta.
- Carrito vacío, notificaciones vacías, listas filtradas vacías: ícono + frase (ver 6).
- Errores de negocio **explican qué pasó y cómo seguir**, en toast o nota: "El motivo es obligatorio", "Falta plata: el pago no alcanza", "Cobrá o descartá las ventas abiertas primero", "La parte en efectivo tiene que ser mayor a 0 y menor al total", "Sin stock: no se puede agregar", "Elegí un medio de pago (Alt+E, Alt+Q, Alt+D o Alt+X)".
- Terminal: rechazado / venció / sin conexión con salida a cobro manual (7.1/8).
- Mercado Pago **solo avisa**: nunca bloquea un cierre ni toca caja/stock por su cuenta.

---

## 10. Datos de ejemplo del mock (para fixtures y capturas)
Productos (25 + "Varios"), proveedores (7), ventas del día (5), movimientos (6), días cerrados (6), encargues (3) y deudas (2) están en el bloque `P`, `PROV`, `NS.VENTAS`, `MOVS`, `DIAS`, `ENC`, `DEU` del mock. Cifras ancla: **venta inicial** 2×Cerveza $ 2.100 + 250 g Jamón ($ 14.600/kg) + 3×Pan $ 2.800 = $ 16.250 → efectivo redondea a **$ 16.300**; **día** $ 482.300 / ganancia $ 168.900 / 61 tickets / falta separar $ 295.000; **cierre** esperado cajón $ 253.000, MP $ 481.300, lata $ 58.400.

---

## 11. Reglas de negocio que NO cambian (y que el mock ya respeta)

### 11.1 Total de una venta (regla 8 de `CLAUDE.md`)
`total = redondeo( bruto − descuento + recargoCigarrillos )`
- Descuento sobre el **total de la venta entera** ($ o %), nunca por línea; la ganancia sale neta del descuento (se prorratea).
- **Recargo de cigarrillos** solo con medio **virtual** (QR, Point o mixto), **completo en mixtos**, y se queda en la caja normal. Regla real: primer atado **$ 300**, cada atado adicional **$ 100**, cigarro suelto **$ 50**. *(El mock modela solo atados; los sueltos se suman igual en la app real.)* Si el medio cambia, el recargo aparece/desaparece en el momento.
- **Redondeo** hacia arriba al paso (default $ 100) **solo en efectivo y mixto**; el virtual cobra exacto. El redondeo acumulado se muestra como línea propia en el cierre.
- **Pesables**: `subtotal = ceil(precioPorKg × gramos / 1000)`, siempre por su helper (nunca multiplicar directo).
- **Vuelto** exacto de $ 100 ⇒ caramelo como **venta** (descuenta stock, genera reposición, computa ganancia), no como redondeo.
- **Sin stock no se vende** (no se puede agregar; pasa solo si ya estaba en el carrito o con stock negativo previo).
- **Varios**: monto suelto, no descuenta stock, queda marcado para revisión al cierre.
- QR, débito y crédito = **un solo medio "Mercado Pago"** en la caja; el canal es dato del pago. **Crédito siempre en 1 pago y sin recargo.**
- Una venta cobrada se puede **editar** (revierte y reaplica stock y caja; queda quién/cuándo) y **anular** (solo con la sesión abierta, motivo obligatorio, devolución por MP si corresponde).
- **Cierre**: conteo a ciegas obligatorio antes de ver la diferencia; cajón + Mercado Pago + lata se arquean aparte; la comisión de MP explica la diferencia de MP; el cierre nunca se frena por avisos de MP.
- Todo **movimiento de stock deja rastro**; todo cálculo vive **en un solo lugar** (`lib/domain/`); la UI no recalcula.

### 11.2 Lo que sigue configurable
Los tres montos del recargo, ganancia de referencia por categoría, fondo fijo, reserva diaria de fijos, día del retiro, colchón por proveedor, paso de redondeo, producto del botón de vuelto, rutas de respaldo y PDF, qué secciones se ven y en qué orden, productos/precios/costos/proveedores/categorías/medios/fijos.

---

## 12. Mapeo a la base de código (dónde tocar)

| Capa | Archivos | Qué cambia |
|---|---|---|
| Tema | `ui/tema/colores_escritorio.dart`, `acentos.dart`, `tokens.dart`, `tema.dart`, `iconos.dart` | paleta 3.1; escala tipográfica 3.2 (Figtree variable o 500); radios/medidas 3.3; íconos de trazo |
| Movimiento | `ui/tema/movimiento.dart` (+ nuevos) | `TituloTipeado`, `Reveal`, `CifraQueCuenta`, `CampoParticulas`, `CursorPastilla`, `ScrollSuave`, `Tablero3D`, `Marquee`; flag global de reducción |
| Kit | `ui/comun/*` | `Boton`, `Chip`, `Segmento`, `Etiqueta`, `Tarjeta/Hero`, `ListaAgrupada`, `Campo`, `Interruptor`, `Stepper`, `Modal` (nuevo estilo), `Toast`, `EstadoVacio` |
| Navegación | `ui/navegacion/*` | `NavbarSuperior` → pastilla flotante + `MegaMenu` (OverlayEntry) + búsqueda en la pastilla + `BuscadorFunciones` |
| Ventana | `ui/ventana/ventana_escritorio.dart` | barra de 40 px (estado de caja y copia) |
| Pantallas | `venta/*`, `dashboard/*`, `equilibrio/*`, `proveedores/*`, `separaciones/*`, `historial/*`, `encargues/*`, `cierre/*`, `configuracion/*`, `stock_proveedor/*`, `carga_historica/*`, `impresion/*`, `respaldo/*` | disposición y contenido de la sección 7; la **lógica** de cada controlador **no cambia** |
| Dominio/datos | `domain/*`, `data/*` | **sin cambios** |

Equivalentes en Flutter: título tipeado = `AnimatedBuilder` por carácter con `Semantics(label)`; reveal = `Entrada` + detector de visibilidad (puede usarse `visibility_detector`: ya no hay restricción de hardware); partículas = `CustomPainter` + `Ticker` y `MouseRegion` para el mouse; cursor-pastilla = `Overlay` + `MouseRegion` + posición con *lerp*; mega-menú = `OverlayEntry` con `FadeTransition`/`SlideTransition`; vidrio = `BackdropFilter(ImageFilter.blur)`; 3D = `Transform` con `Matrix4.identity()..setEntry(3,2,0.001)..rotateX()`; scroll suave = `Listener(onPointerSignal)` + `animateTo`; *count-up* = `TweenAnimationBuilder<double>`.

---

## 13. Plan de implementación (una fase por vez, cada una se prueba)

1. **Tema y kit**: tokens, paleta, tipografía, íconos, componentes de la sección 6, `Modal`, `Toast`. Capturas de la vitrina (`test/capturas/pantalla_muestra_kit.dart`) en claro y oscuro.
2. **Movimiento**: widgets de la sección 5 + flag de reducción y los tres interruptores de Configuración. Pruebas de que **no retrasan** foco/teclado.
3. **Ventana y navegación**: barra de 40 px, pastilla flotante, mega-menús, búsqueda en la pastilla, notificaciones, Ctrl+K.
4. **Venta** completa + todos sus diálogos de caja (la de más uso; se prueba con escáner y teclado reales).
5. **Cierre de caja** y **Separaciones** (tocan plata; correr `conciliacion_caja_test`).
6. **Inicio**, **Proveedores** (+ conteo), **Historial** (+ detalle, editor, carga histórica), **Encargues**, **Configuración**.
7. Capturas `test/ui/capturas_escritorio_test.dart` contra el mock, `flutter analyze` ("No issues found!") y `flutter test --exclude-tags bench`. Corregir `DISENO.md`/`CLAUDE.md`/`ESTADO.md` (en el mismo cambio de cada fase).

Criterios de aceptación transversales: (a) la regla dura de Venta se cumple a 1366×768 y 1920×1080 (búsqueda, total, medios y Cobrar siempre visibles); (b) con Movimiento = Reducido y con "reducir animaciones" de Windows no hay ninguna animación; (c) escaneo + Enter + cobro no se demoran con todo encendido; (d) claro y oscuro con contraste legible; (e) ningún importe, botón de cobro ni estado de plata lleva gradiente, partículas o cursor-pastilla; (f) los textos del mock se usan **tal cual** (voz rioplatense, sin jerga).

---

## 14. Excepciones, límites del mock y pendientes

### 14.1 Excepciones explícitas (se aplican en la app real distinto del mock)
- **E-1 Peso 450 / fuente.** El mock usa Figtree variable. Si la app mantiene fuentes estáticas (400/500/600/700), los títulos van en **500** (desvío ya aceptado por el dueño el 05/10 para el celular). Alternativa fiel: sumar Figtree variable (~100 KB) con `FontVariation('wght', 450)`.
- **E-2 Montos.** El mock usa pesos enteros; la app usa `int` en centavos con `formatearARS`.
- **E-3 Elementos que son solo del mock (no se implementan):** la **barra de herramientas** de arriba (selector "Ir a un estado…", Tema, Movimiento, "Atajos", chips de pantalla), la barra **"Solo del mock · simular"** del diálogo de terminal, la simulación automática de la terminal, los datos de ejemplo, la escala 1920×1080 y la ventana dibujada en HTML (la real es `ventana_escritorio.dart`).
- **E-4 Recargo de cigarrillos:** el mock modela solo atados (300 + 100 por adicional); la app suma además 50 por cigarro suelto.
- **E-5 Tipos de pago de la terminal real:** el mock usa tiempos fijos; la app usa la Orders API real (la orden vence a los 2 minutos; cancelar por API solo en `created`).
- **E-6 Factura:** el mock muestra el resultado de leer una factura; en la app solo hay **lectura de prueba**.
- **E-7 Cursor-pastilla:** el puntero real **no se oculta** (a diferencia de antigravity); la pastilla va desplazada. Decisión tomada por precisión en el mostrador.
- **E-8 Pantalla de venta y animación:** `CLAUDE.md` dice "animaciones menores a un quinto de segundo" y "nunca demoran lo que se tipea ni el cobro". Esta v3 usa duraciones largas (0,3–1,1 s) **solo en elementos no bloqueantes**; eso es una decisión del dueño de hoy y **actualiza** esa regla (ver 5.1 para las garantías).

### 14.2 Responsive de escritorio
Diseñado a 1920×1080. En **1366×768** (piso digno): la grilla de Venta pasa a **4 columnas**, el ticket baja a 560 px, la pastilla de navegación oculta la marca y el texto de "Cambiar de turno" pasa a ícono; el título de Inicio baja a 72; las páginas de dos columnas mantienen la lista a 420 px. No hay diseño para menos de 1280 px de ancho. *(El mock no incluye estos ajustes: se definen acá y se validan al implementar.)*

### 14.3 Funciones o decisiones **nuevas** que aparecen en el mock y hay que confirmar con el dueño antes de construir
1. **Mega-menú** que agrupa accesos (no agrega funciones, pero cambia cómo se llega a Edición masiva, Comparar precios, Conteo, etc.).
2. **Buscador de funciones (Ctrl+K)** — viene del celular; no existe hoy en la PC.
3. **Marquee de avisos en Inicio** (repite lo pendiente).
4. **Tablero 3D** que se endereza al scrollear, **titular que se enciende** en "Este mes" y **gradiente en el importe del saludo**.
5. **Contar stock** y **Comparar precios** accesibles desde el menú (existían como pantallas/diálogos sueltos).
6. **Ver movimientos** de la cuenta corriente y el **aviso de ≥ 50 %** en edición masiva (ya propuestos en el mock anterior, nunca confirmados).
7. **"Marcar todo igual"** en Contar stock (tilde "está igual" del celular).
8. **Colores de medio**: se mantienen los del celular (Efectivo verde, MP azul, Tarjeta gris, Mixto ámbar), que cambian el color al que el cajero está acostumbrado hoy (naranja/violeta).
9. **Cursor-pastilla y partículas en Venta** (el dueño eligió "alto en todo"; si en el uso real cansan, el interruptor ya existe).

### 14.4 Lo que no se verificó
El mock se probó en Chromium (flujos con mouse y teclado, claro/oscuro, reducido) sin errores de consola; **no se probó en Windows real ni con escáner/impresora/terminal reales**, ni en 1366×768 (14.2 es diseño, no verificación). El rendimiento del campo de partículas y del `BackdropFilter` hay que medirlo en la PC del local antes de dejarlos encendidos por defecto.

---

## Apéndice A — Qué hay en el mock, por pantalla y estado (para recorrerlo)

Selector "Ir a un estado…" (39): Venta vacía · buscando "coca" · pesable "200 queso" · cigarrillos con QR (recargo) · Cobro efectivo · QR/tarjeta · Terminal esperando · Terminal rechazada · Cobro mixto · Venta cobrada · Descuento · Ventas abiertas · Cambiar de turno · Abrir caja · Gasto o ingreso · Arqueo intermedio · Notificaciones · Mega-menú de Proveedores · Búsqueda global · Buscador de funciones · Inicio "Este mes" · Editar producto · Pagar a proveedor · Edición masiva · Leer factura · Conteo de stock · Ganancia del día · Historial movimientos · Historial cierres · Anular venta · Detalle de un día · Editar una venta · Cargar día histórico · Cierre resultado · Caja cerrada · Config tema · Config impresión · Config celular · Atajos.

## Apéndice B — Correspondencia de clases del mock con piezas del kit
`btn`→Boton · `chip`→ChipPlz · `seg`→Segmento · `tag`→Etiqueta · `card/hero`→Tarjeta/TarjetaHero · `list/kv`→ListaAgrupada/FilaClaveValor · `field`→CampoPlz · `tg`→FilaInterruptor · `note`→Nota · `rowb`→FilaMaestro · `tile`→TileProducto · `cl`→LineaCarrito · `stp`→Stepper · `bar`→BarraProgreso · `ticket`→TicketPlz · `empty`→EstadoVacio · `.rv`→Reveal · `data-typed`→TituloTipeado · `data-count`→CifraQueCuenta · `canvas.particles`→CampoParticulas · `data-cur`→CursorPastilla · `.mega`→MegaMenu · `.nav`→NavPastilla · `.modal`→Modal · `.toast`→Toast · `.popn`→PopoverNotificaciones · `.cp`→BuscadorFunciones.
