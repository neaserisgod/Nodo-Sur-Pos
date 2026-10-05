# Especificación de la app de PC v3 — versión sobria, sin scroll (2026-10-05)

Documento para que una IA (o una persona) lleve **al pie de la letra** el mock de escritorio v3 a la app real de Flutter.
**Salvo las excepciones de la sección 14, todo lo que dice este documento se implementa tal cual.**

- **Mock vivo (interactivo, claro/oscuro):** https://claude.ai/artifact/Kq4qCixuDtGpRKS1sjKxxj
- **Fuente del mock en el repo:** `docs/mock-pc/NodoSurPC-v3.html` (un solo archivo; Figtree viene de Google Fonts). Es la **referencia
  visual y de comportamiento**. Si este documento y el mock difieren en un número, **gana el mock** (y este documento se corrige).
- **Hermano guardado para la web:** la primera versión de este rediseño, más expresiva (títulos que se tipean, partículas, tablero 3D,
  cinta de avisos, scroll suave), le gustó al dueño **para el sitio**, no para la caja. Está en
  [`ESTILO-EXPRESIVO-WEB.md`](./ESTILO-EXPRESIVO-WEB.md) y `docs/mock-pc/NodoSurPC-v3-expresivo.html`
  (vivo: https://claude.ai/artifact/DnUi6qvYDxZpgpD3uh14js). **No se aplica a la PC.**
- **Ronda 3 (2026-10-05, la más reciente):** el dueño pidió **rapidez inmediata y cero fricción**, la **IA siempre a mano**, **Pagar proveedor** como acción principal de caja (gasto/ingreso pasa a secundario), **navbar sin logo ni nombre del local ni lupa**, la **tuerca** de vuelta para Configuración, y mucha información a la vista **sin perder claridad**. Está incorporada en todo este documento y resumida en la **sección 15**.
- **Reemplaza** al mock anterior (`docs/mock-pc/NodoSurPC.html`) y a `docs/COMPARACION-MOCK-PC.md`.
- Nada de esto toca `lib/domain/` ni `lib/data/`: es **solo capa de presentación** (`lib/ui/`). Las reglas de negocio no cambian (sección 11).

---

## 0. Cómo usar este documento (para la IA que implementa)

1. Leé `CLAUDE.md`, `REGLAS-NEGOCIO.md`, `ESTADO.md` y este documento, en ese orden. Este documento **manda sobre `DISENO.md` y sobre las
   secciones "Hardware" y "Pantalla de venta" de `CLAUDE.md`** en todo lo visual y de disposición (regla del repo: "vale lo más reciente";
   esto es del 2026-10-05 y lo pidió el dueño). Al aplicarlo, **corregí `DISENO.md` y `CLAUDE.md` en el mismo cambio** para que no se contradigan.
2. Abrí el mock en un navegador y recorrelo con el selector **"Ir a un estado…"** (arriba, fuera de la ventana): salta a 39 estados.
3. Implementá **por capas y por pantallas, probando cada una** (sección 13).
4. Decisiones técnicas (nombres, archivos, widgets) se toman sin preguntar. Decisiones de negocio o ambiguas se marcan y se preguntan (14.3).
5. Los montos del mock son **pesos enteros** solo por comodidad: en la app real todo sigue siendo **`int` en centavos**.

---

## 1. Qué es este rediseño y de dónde sale

El dueño: la estética del sitio (horsepos.com, hoy "Nodo Sur") está basada en **antigravity.google**; la app del celular ya está integrada con
esa estética, **la de escritorio no le gusta para nada**. Pidió rehacerla de cero (disposición incluida), guiándose por el sitio, antigravity y la app Android.

**Dos rondas:**
1. *Versión expresiva* (guardada para la web). Feedback del dueño: **"exageramos un poquito: muchas de las páginas deben ser claras de leer y, en lo posible, sin scroll"**; pero **le gustó para la web**.
2. *Esta versión sobria*, para la caja. Conserva el **lenguaje visual** (bloques planos grandes, tinta + azul de acción, radios grandes, Figtree liviana, pastilla flotante con mega-menú, íconos de trazo) y quita lo que estorba a la lectura y al mostrador.

Decisiones del dueño que siguen vigentes: **pastilla flotante arriba + mega-menú**; **Venta = buscador grande + grilla + ticket alto a la derecha**; modales **al centro**; **"Cobrar" azul**; colores de medios propios; Venta es la pantalla principal (la app arranca ahí).

### 1.1 Qué se tomó de cada referencia (investigación navegando las webs, no capturas)

Se navegó horsepos.com y antigravity.google con Chromium (scroll, hover, clics, páginas internas) y se leyó su CSS/JS. Detalle completo de lo observado, con valores, en [`ESTILO-EXPRESIVO-WEB.md`](./ESTILO-EXPRESIVO-WEB.md) §1.1. De ahí **sí** se tomó para la caja:

| Pieza | Origen | Cómo queda en la caja |
|---|---|---|
| Curva `cubic-bezier(.2,.7,.1,1)` | horsepos | única curva de las transiciones |
| Botón que se levanta 2 px con sombra, `:active scale(.98)` | horsepos | igual |
| Pastilla de vidrio que "se levanta" (fondo más opaco + sombra) | horsepos | se levanta **al abrir el mega-menú** (la ventana no scrollea) → 4.2 y E-9 |
| Mega-menú de ancho completo con velo, título grande + lista de ítems | antigravity | igual, cascada de ítems corta (25 ms) |
| Bloques `#F3F4F7`, tinta `#121317`, radios 24–48, Figtree 450 | horsepos/antigravity | igual |
| Cifras que cuentan hacia arriba | horsepos | solo en Inicio ("Hoy vendiste") y Separaciones, 700 ms |
| Campo de partículas | ambas | **solo celebraciones** (venta cobrada, caja cerrada) |
| Título que se tipea, tablero 3D, titular que se enciende, cinta de avisos, scroll suave, cursor-pastilla | ambas | **fuera** (o apagado por defecto); quedan para la web |

> Decisión de tipografía: **Figtree** (la de la app, el celular y horsepos), no Google Sans Flex. Ver excepción E-1.

### 1.2 Lo que se tomó de la app Android (guía de contenido)
Paleta y tokens del mock del celular (tinta, azul `#2f5be8`, 4 tonos de estado), íconos de trazo propios (`lib/companion/kit/iconos_ns.dart`), "Buscador de funciones", conteo a ciegas, hojas de gasto/ingreso, notificaciones con pendientes y la separación Resumen/Separar/Ventas, reinterpretados para pantalla grande.

---

## 2. Principios (en orden de prioridad)

1. **Sin scroll de página.** Cada pantalla **entra completa en 1920×1080** (y se degrada con dignidad en 1366×768, ver 14.2). La ventana **nunca** scrollea: lo único que scrollea son **listas y tablas internas** (carrito, grilla de productos, lista de proveedores, tabla de productos, historial, navegación de Configuración, etc.), siempre dentro de un contenedor con alto acotado (`min-height: 0`), con el **encabezado de la tabla fijo** y sin que el scroll tape los controles de la pantalla. Si algo no entra, **se reorganiza** (columnas, pestañas, interruptor Hoy/Este mes), no se agrega scroll de página.
2. **Claro de leer.** Títulos de página de **48 px** (no gigantes), una sola línea de contexto arriba (`eyebrow`), cifras grandes solo donde son el dato principal, texto de 15–18 px, líneas de texto con ancho máximo (nunca cruzan la pantalla), mucho contraste, sin texto sobre imágenes ni degradés.
3. **Operar > arrancar.** Nada decorativo demora lo que se tipea, el foco, el escaneo ni el cobro.
4. **Búsqueda, total y medios de pago siempre visibles en Venta**; el carrito scrollea (regla dura de `CLAUDE.md`, no cambia).
5. **El dueño mira esta pantalla 12 h/día.** Nunca blanco puro sobre negro puro (oscuro: fondo `#0E0F13`, texto `#EEF0F4`).
6. **Un solo lenguaje**: bloques planos grandes, sin bordes ni sombras salvo donde se indica (modales, mega-menú, popovers, pastilla elevada, toast).
7. **Movimiento corto y con propósito** (sección 5). Reducible: Configuración › Tema y movimiento y "reducir animaciones" de Windows.
8. **Rapidez inmediata, cero fricción** (sección 15): todo lo frecuente se hace con el teclado y con el menor número de pasos; lo que ya se sabe viene **precargado**; no se pide confirmación si se puede **deshacer**; lo que no aporta se saca.
9. **IA a mano, nunca escondida** (sección 15.2): presente en la navegación, en Venta, en Inicio y en Proveedores, siempre marcada con ✦ y la etiqueta **IA**, y **siempre solo sugiere** (vos confirmás).
10. **Mucha información, bien jerarquizada** (sección 15.3): más datos útiles por pantalla, ordenados con una escala tipográfica corta, columnas alineadas, cifras tabulares y color solo para estado.

---

## 3. Sistema visual (tokens)

### 3.1 Color
Igual que en [`ESTILO-EXPRESIVO-WEB.md`](./ESTILO-EXPRESIVO-WEB.md) §3.1 (mismos valores en claro y oscuro: tinta `#121317`/`#EEF0F4`, fondo `#FFF`/`#0E0F13`, bloque `s` `#F3F4F7`/`#171A21`, `s2`, `s3`, `mute`, `soft`, `line`, `hair`, azul `#2F5BE8`/`#3D68F2`, `blue-d`, `blue-l`, `hero` `#121317`/`#1C2231`, medios Efectivo `#0B7A5E` · MP `#2F5BE8` · Tarjeta `#4B5563` · Mixto `#B45309`, cuatro estados OK/error/aviso/info, tintes de categoría). Se definen **una vez** en `colores_escritorio.dart` y `acentos.dart`. **Sin degradés** en ninguna tarjeta ni botón; el degradé decorativo del saludo y el caret **no existen** en esta versión.

### 3.2 Tipografía
**Figtree** (variable `wght` 300–900 en el mock para llegar al 450; ver E-1).

| Rol | Tamaño / peso / tracking |
|---|---|
| `h1` página | **48** / 450 / −0,045 em / lh 1,05 (Venta: **40**; Cierre: 40–46; "Caja cerrada": 56) |
| `h2` | **34** / 450 / −0,045 em (modal: 38; ficha de proveedor: 28) |
| `h3` | 28 / 450 |
| `lead` | 17–19 / 400 / `mute` (máx. 640–860 px) |
| Cifra (`fig`) | **44** / 450 / −0,055 em tabular (hero de Inicio 68; indicadores 34–42; total de Venta **76**; importe de cierre 60) |
| Texto de filas | 15,5–18 / 400–600 |
| Chico | 12,5–14 / 500–600 |
| `eyebrow` | 15 / 600 / `mute`, con punto azul de 8 px |
| `kbd` (atajos) | 12 / 600, fondo 9 % del color del texto, radio 8 |

Siempre cifras tabulares en importes.

### 3.3 Radios, espaciado, medidas
- **Radios:** pastilla 999; modal 48; hero 34; tarjeta 32; ticket de Venta 52; ticket de Historial 36; total de Venta 44; tile 30; fila 26; campo 28; lista agrupada 28–30; nota 24.
- **Retícula de página (`.page`):** `padding 106 56 26` (los 106 de arriba dejan lugar a la pastilla: 14 + 68 + 24), `gap 16`. Estructura fija: **`phead`** (eyebrow + h1 a la izquierda, acciones a la derecha, no se achica) y **cuerpo `flex:1; min-height:0`**.
- **Tarjetas:** `padding 22×28` (hero 24×30); entre tarjetas `gap 14`; filas de lista 52–62 de alto; botones `sm` (44) para acciones de fila.
- **Alturas de control:** botón 56 (`sm` 44, `xs` 36, `lg` 76); chip 46 (`sm` 38); segmento 46; campo ~72; buscador de Venta 72.
- **Sombras (solo estas):** modal `0 40px 100px rgba(13,16,23,.35)`; mega-menú `0 30px 60px rgba(13,16,23,.12)`; popover/dropdown `0 30px 80px rgba(13,16,23,.22–.25)`; pastilla elevada `0 10px 40px rgba(13,16,23,.1)`; hover de botón `0 14px 34px` (neutro `.2`, azul `rgba(47,91,232,.32)`); segmento activo `0 2px 10px rgba(13,16,23,.1)`; toast `0 20px 50px rgba(0,0,0,.3)`. Los bloques siguen **sin sombra**.
- **Resolución de diseño:** 1920×1080 (alto útil 1040 bajo la barra de ventana de 40). Piso digno 1366×768 (14.2).

### 3.4 Íconos
Trazo único 24×24, grosor 2, sin relleno, redondeados (set del celular `IconoNs`). Tamaños: 14–16 (steppers, pastillas), 18–22 (botones, listas), 24–28 (buscador), 36–44 (estados vacíos), 60–84 (estados grandes). Los que falten en `IconoNs` se agregan con su path (`IconoPlz._trazos`).

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

Capas (de abajo a arriba): contenido → velo del mega-menú → mega-menú → pastilla → popover de notificaciones / asistente → modales → toast → cursor-pastilla. La barra de ventana va siempre encima de todo (z más alto salvo modales). **Ninguna pantalla scrollea la ventana**: lo único que scrollea son listas y tablas internas (sección 2, regla 1).

### 4.1 Barra de ventana (40 px) — `lib/ui/ventana/ventana_escritorio.dart`
Fondo `s`, texto 13,5/600 `mute`. Izquierda: logo "ns" (26 px) + "La Plazoleta · Nodo Sur". Centro: punto verde + "Caja abierta · {usuario} · desde {hora}" (o punto gris "Caja cerrada") y "Copia de hoy 8:00 ✓". Derecha: minimizar, maximizar, cerrar (46×34, hover `s2`; cerrar hover rojo `#C5221F` con ✕ blanca). **Cerrar con caja abierta pregunta antes** (no cambia, ver doc de ventana).

### 4.2 Pastilla de navegación flotante — `lib/ui/navegacion/navbar_superior.dart` (reescribir)
- Posición: `top = 40 + 14`, centrada, **máx. 1760 px**, alto **68**, radio 999, padding `0 12 0 18`, `gap 10`. Fondo de vidrio (`BackdropFilter` blur 18 + saturación 1,6) con borde interior de 1 px `navline`. **No ocupa el ancho entero**: flota con 40 px de margen.
- **Levantada**: mientras el mega-menú está abierto, el fondo pasa a `navbg2` (`.9`) y suma la sombra de 3.3; transición `.3s` (la ventana no scrollea, ver E-9).
- **Sin logo ni nombre del local** (el nombre ya está en la barra de la ventana). La pastilla empieza directamente con las secciones.
- Izquierda (`links`, alineados al inicio, `gap 4`): **Venta** (pastilla azul, ícono carrito 20, `padding 0 24`, 16/600, blanca; activa = `blue-d`), **Inicio▾, Proveedores▾, Separaciones▾, Historial▾, Encargues▾**: 16/500 `mute`, alto 46, `padding 0 20`; hover y "abierto" = fondo `s` + texto `ink`; **activa (`aria-current`) = fondo `s`, `ink`, 600**; el chevron `▾` rota 180° (`.25s`) al abrirse.
- Derecha:
  - En **Venta**: botón `sm` tonal **"Cambiar de turno"** y botón `sm` oscuro **"Cerrar caja"**.
  - En el resto: chip `s` con punto verde con halo "Caja abierta · Ana" (o "Caja cerrada").
  - Siempre, en este orden: botón **✦ Asistente** (pastilla `blue-l` con texto azul 15/600, ícono destello 18 y `kbd` "Ctrl+K"; abre el asistente universal, 4.5), **campana** (con globito rojo y cantidad de pendientes) y **tuerca** de Configuración (ícono de **engranaje/cog**, no los controles deslizantes; `aria-label` "Configuración"; `aria-pressed` cuando la pantalla es Configuración → fondo `ink`, ícono `paper`).
  - **No hay lupa**: era redundante (Venta tiene su campo único con foco permanente, cada pantalla de gestión tiene su propio buscador y `Ctrl+F`/`Ctrl+K` abren el asistente).
- **El orden de secciones y cuáles se ven sigue siendo configurable** (Configuración › Menú); Venta no se puede ocultar; Configuración es siempre el engranaje.
- **Búsqueda:** en Venta, `Ctrl+F` enfoca el campo único (nunca se esconde). Fuera de Venta, `Ctrl+F` abre el **asistente** con el cursor listo para escribir; elegir un producto lo **agrega a la venta y lleva a Venta** (no hay carrito en las otras pantallas).
- **Teclado:** `Alt+1…6` van a Venta, Inicio, Proveedores, Separaciones, Historial y Encargues (cada botón muestra el atajo en su `title`).

### 4.3 Mega-menú (antigravity)
Se abre al pasar el mouse por Inicio/Proveedores/Separaciones/Historial/Encargues (con 70 ms de retardo de intención) o al enfocar con teclado. **Venta no tiene.**
- Panel de **ancho completo de la ventana**, fondo `paper`, **esquinas inferiores 48**, sombra de 3.3, `padding 96 120 44` (los 96 de arriba dejan lugar a la pastilla, que queda por encima). Grilla `420px | 1fr | 1fr`.
- Columna 1: título `h3` 36/450 (balance), párrafo `mute` 16 y botón `sm` tonal "Ver {sección}".
- Columnas 2 y 3 (separadas por una línea `hair`): encabezado 14/600 `soft` ("Pantallas", "Acciones"); ítems de 18/450 con ícono 22 (`mute`), `padding 11×14`, radio 20, hover `s`, y a la derecha un dato chico (13 `soft`: "Alt+N", "IA", "Conteo físico").
- **Animación**: panel `opacity 0→1` `.2s` + `translateY(-14→0)` `.24s` con `quart`; **los ítems entran en cascada** (`translateY(10)→0`, `.4s`, retraso `30ms + 25ms*i`).
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

### 4.5 Asistente universal (Ctrl+K, Ctrl+F fuera de Venta o el botón ✦ Asistente) — ver 14.3
**Un solo lugar** para buscar, hacer y preguntar. Panel central (ancho 900, `top 110`, radio 40, sombra, velo detrás; entra `translateY(18→0)` `.24s`). Campo en pastilla `s` con ícono ✦ azul y `kbd` Esc. Ignora acentos y mayúsculas; flechas + Enter; Esc cierra; lista con scroll propio (máx. 760).
- **Vacío (apenas se abre), ya con sugerencias a la vista:** *Preguntale a la IA* (5 frases listas: "¿Qué me conviene pedir esta semana?", "¿Cómo vengo hoy contra el lunes pasado?", "Subir 10 % los precios de Quilmes", "¿A quién le debo y cuánto?", "Armá promos con lo que se vende junto"), *Acciones frecuentes* (**Pagar a proveedor · Alt+P** primero, Nueva venta, Hacer arqueo, Cambiar de turno, Cerrar caja, Gasto…) e *Ir a* (las secciones con su `Alt+n`).
- **Escribiendo:** *Productos* (hasta 4; **Enter agrega a la venta** y muestra "Agregado a la venta: …"; sin stock = atenuado y no se puede), *acciones y pantallas* que coinciden (con su atajo a la derecha) y, **siempre al final, "✦ Preguntar: «lo escrito»"**.
- **Respuesta de la IA** (dentro del mismo panel, sin cambiar de pantalla): etiqueta IA + la pregunta + botón **Volver**, título, filas de datos, nota si corresponde, **botones de acción** (el primero azul) y el pie "La IA solo sugiere: vos confirmás". Ejemplos del mock (con datos de ejemplo): *pedir* (qué pedir a cada proveedor y "Armar el pedido…"/"Pagar a Coca-Cola"), *cómo vengo* (comparación con el lunes pasado), *subir N %* (abre **Edición masiva ya cargada con N %**; no cambia nada hasta confirmar), *promos*, *deudas* (resumen + "Pagar a proveedor"), *factura* (pasos + "Leer una factura"). Una pregunta que no entiende responde con honestidad qué puede hacer.
- Corresponde a **Gemini** (la clave se carga en Configuración › Asistente IA). **Hoy la app solo usa IA para promos sugeridas y lectura de facturas**; la pregunta libre y las respuestas con datos del negocio son **funciones nuevas** (14.3).

### 4.6 Atajos de teclado (todos con Alt para no chocar con la escritura)
`Alt+E/Q/D/X` medio de pago · `Alt+M` cobro manual (con canal QR/débito elegido) · `Enter` con el campo vacío cobra / con dropdown agrega · `Esc` cancela la venta entera (con el campo lleno, lo vacía primero) · `Alt+P` **Pagar a proveedor** (desde cualquier pantalla) · `Alt+V` Varios · `Alt+I` ingreso rápido · `Alt+G` o `-` gasto rápido · `Alt+N` venta nueva · `Alt+S` siguiente venta · `Alt+C` caramelo del vuelto · `Alt+1…6` ir a una sección · `Ctrl+F` / `Ctrl+K` asistente · `Inicio` vuelve a Venta (salvo escribiendo en un campo). Diálogo de ayuda "Atajos de teclado" (botón "Atajos" del mock; en la app, entrada en Configuración o `?`). Guardas existentes que **se mantienen**: AltGr no dispara atajos; cerrar un diálogo secundario **no roba el foco** del campo de búsqueda; agregar al carrito y cobrar **devuelven** el foco a la búsqueda.

---

## 5. Movimiento (catálogo corto)

Se implementa en `lib/ui/tema/movimiento.dart` (extender `Entrada`/`Pulso`) y se **apaga** con "reducir animaciones" del sistema o con Movimiento = Reducido. Curvas: `ease` = `(.2,.7,.1,1)`; `quart` = `(.165,.84,.44,1)`; `back` = `(.34,1.85,.64,1)`; `easeOutCubic`.

### 5.1 Reglas de seguridad (obligatorias)
- Ninguna animación **retrasa** el foco, lo tipeado, el escaneo, el Enter ni el cobro. Los elementos aparecen ya clickeables aunque estén en fade.
- Lo que se reproduce al **entrar** a una pantalla no se vuelve a reproducir al actualizar datos (tiles, líneas y tarjetas que no cambian **no se re-animan**).
- Solo se escalonan las primeras ~4 piezas de un grupo; lo que aparece al scrollear una lista entra sin retraso.
- Una sola cosa "llamativa" por zona.

### 5.2 Qué se queda
| Elemento | Efecto |
|---|---|
| Cambio de pantalla | salida `opacity 1→0` + `translateY(0→-6)` en **140 ms**, luego monta la nueva; sin animación global de entrada; Reducido = instantáneo |
| Reveal de bloques | `opacity 0→1` + `translateY(10→0)`, **.4s ease**, retraso `min(índice,4)×40 ms` por hermano |
| Botón | hover `translateY(-2)` + sombra (`.3s ease`); `:active scale(.98)`; el azul con sombra azul |
| Tarjeta de acción | hover `translateY(-2)` (solo las clickeables, ej. "Falta separar") |
| Fila / tile | hover **solo de color** (a `s2`), sin desplazamiento; el tile entra `.3s` desde `translateY(8)` con retraso `12 ms×min(i,14)` **solo** al mostrar o cambiar la grilla |
| Chip / segmento / interruptor | fondo `.2s`; segmento activo se "levanta" `.25s ease`; interruptor: pista a azul `.3s`, perilla con resorte `back` `.35s` |
| Contador de un tile y línea nueva del carrito | `pop` (`scale 1→1.045→1`, `.45s`) y entrada `translateY(10) scale(.96)→1` `.4s` (solo la nueva); aro azul de 2 px en la última agregada |
| Total de Venta y cifras vivas | *tween* de **320 ms** (easeOutCubic) + pulso `.5s` |
| Botón de medio de pago | al elegirlo el color **llena** (`.3s`) y late |
| Cifras de Inicio ("Hoy vendiste") y Separaciones | cuentan de 0 al valor en **700 ms** easeOutCubic al verse; no se repiten |
| Barras (ventas por hora) | alto 0→valor en **.6s ease**, retraso `25 ms×índice`; barra de progreso `.7s` |
| Placeholder del buscador de Venta | **se escribe solo** (frases rotativas: "Escaneá un código o buscá un producto", "200 queso barra", "coca 2,25 l", "7790001000011"), 48 ms/carácter, pausa 1,7 s, se borra a 22 ms; se detiene con foco o texto |
| Pastilla de navegación | "se levanta" (fondo `.66→.9` + sombra, `.3s`) mientras el mega-menú está abierto |
| Mega-menú | panel `opacity .2s` + `translateY(-14→0) .24s quart`; ítems en cascada `translateY(10→0)` `.4s` con retraso `30ms + 25ms×i`; velo `.25s` |
| Búsqueda en la pastilla | pastillas y botones se desvanecen `.25s`; el campo ocupa la pastilla |
| Modal / velo | `translateY(22→0)+scale(.96→1)+fade` `.32s ease`; velo `.25s` con blur 6 |
| Toast | entra `translateY(20→0)` con `back` `.45s`; visible 2,6 s |
| Spinner / aro de espera | `spin 1s linear infinite`; aro `1.8s ease infinite` |
| Tilde dibujado (cobrada, aprobado, caja cerrada) | `stroke-dashoffset 60→0`, `.6s ease`, retraso `.15s` |
| Tilde "separado" | círculo vacío → lleno verde con tilde `.25s` |

### 5.3 Celebraciones (el único lugar con partículas)
**Venta cobrada** (modal) y **Caja cerrada** (paso 3 del cierre): campo de partículas `ok` (verde agua, azul, amarillo, rojo, violeta + gris) detrás del tilde. `CustomPainter` + `Ticker`; cantidad `clamp(ancho·alto/3600, 110, 380)`; órbita lenta (`±0,00022 rad/ms`, radio `0,55·diagonal·rand^0.7`, elipse ×0,72, ondulación `sin(t·.0006+fase)·6`), rayitas de 1,2–8 px, trazo 1,6 redondeado, opacidad .25–.95; huyen del mouse (radio 120, máx. 28 px, suavizado 0,12); máscara `linear-gradient(#000 40–55%, transparent)`; se pausa fuera de pantalla. Configuración › "Celebraciones con partículas" lo apaga.

### 5.4 Opcionales (apagados por defecto, interruptores en Configuración › Tema y movimiento)
- **Etiqueta que acompaña al mouse** (cursor-pastilla): pastilla `paper` con ícono 18 y texto 14,5/600 (alto 42, contorno 1 px, sombra `0 8px 30px rgba(13,16,23,.18)`), entra `scale 0→1 .3s back`, sigue al mouse con *lerp* 0,24 desplazada (+18, +20); el puntero real **no se oculta**. Solo sobre tiles, lupa, buscador y "Nueva venta". Sin tiles sin stock.
- **Desplazamiento suave** de las listas largas: *lerp* 0,12 por cuadro; no intercepta listas internas que aún pueden moverse, `Ctrl+rueda` ni trackpad con inercia propia.

### 5.5 Qué se sacó (queda para la web, en `ESTILO-EXPRESIVO-WEB.md`)
Título que se tipea y caret con gradiente · campo de partículas en cada pantalla, Inicio y Venta · tablero 3D que se endereza · titular que se enciende por palabras · cinta de avisos (marquee) · gradiente en el importe del saludo · scroll suave y cursor-pastilla **por defecto** · reveal largo (`.8s`, 28 px, 70 ms) · hover con desplazamiento en tarjetas, filas y tiles.

### 5.6 Reducción de movimiento
Con `MediaQuery.disableAnimations` o Movimiento = Reducido: sin reveal (todo visible), sin tipeo del placeholder, sin celebraciones animadas (el tilde aparece ya dibujado), cifras en su valor final, transiciones de ~1 ms. Los **cambios de estado** (selección, foco) siguen visibles pero instantáneos.

---

## 6. Componentes

Clases del mock entre paréntesis. Implementar como widgets reutilizables en `lib/ui/comun/` y `lib/ui/tema/`.

- **Botón (`btn`)**: alto 56 (`sm` 44, `xs` 36, `lg` 76), `padding 0 28`, 17/600, pastilla. Variantes: `prim`, `blue`, `dark`, `ton` (fondo `s`; **sobre tarjeta gris pasa a `paper`**, hover `s2`), `out`, `red`, `wide`. Con flecha: círculo 44 (lg 54) `rgba(255,255,255,.2)`. Desactivado `opacity .38`.
- **Chip (`chip`)**: alto 46 (`sm` 38), fondo `paper` + contorno `line`; `aria-pressed` = fondo `ink`.
- **Segmento (`seg`)**: pista `s`, padding 5; botones alto 46 16/600; activo `paper` + sombra. `fill` = ancho completo.
- **Etiqueta (`tag`)**: alto 30, radio 999, 13,5/600; tonos neutro, `g`, `b`, `w`, `i`, `dark`.
- **Tarjeta (`card`)**: fondo `s`, radio 32, `padding 22×28`; variantes `w/g/b/i`, `line`. **Hero (`hero`)**: fondo `hero`, texto blanco, subtítulo `rgba(255,255,255,.62)`, radio 34, `padding 24×30`; `hero.blue`.
- **Lista agrupada (`list`)**: radio 28–30, fondo `hair`, filas de 1 px de separación. **Fila clave-valor (`kv`)**: `padding 12×24`, min 52, 16 `mute` + valor `600 ink`. Contenedor scrolleable (`scrl`): `overflow-y:auto; min-height:0`; si es una tabla, el contenedor **se ajusta al contenido** (`flex:0 1 auto; max-height:100%`) para no dejar un bloque vacío.
- **Campo (`field`)**: fondo `s`, radio 28, `padding 14×24 12`; etiqueta 13/600 arriba; valor 21/500; foco = anillo 2,5 px `#3B6CFF`. **Grande (`field big`)**: 56/450 tabular.
- **Interruptor (`tg`)**: fila `padding 14×24`, min 64, título 18/600, detalle 14,5 `mute`, pista 56×32.
- **Nota (`note`)**: radio 24, `padding 16×22`, 15 `mute`; `w g b i`.
- **Fila maestra (`rowb`)**: radio 26, `padding 12×20`, círculo de ícono 46 + título 17/550 + detalle 14,5; seleccionada = `blue-l` + aro azul 2 px; hover `s2`.
- **Tile de producto (`tile`)**, **línea de carrito (`cl`)**, **stepper (`stp`)**, **barra (`bar`)**, **ticket (`ticket`, radio 36, `padding 26×30`)**, **estado vacío (`empty`)**, **toast**, **modal**: ver 7.1 y 8.
- **Ítem de navegación de Configuración (`csec`)**: alto 40, pastilla, 16/500; activo `ink`/`paper` 600; encabezado de grupo 12/700 mayúsculas `soft`.

---

## 7. Pantallas

Para cada una: **layout, contenido, interacciones, estados**. Todas usan la retícula de 3.3 y **no scrollean la ventana**. Datos de ejemplo en el apéndice y en el mock.

### 7.1 Venta (pantalla principal; arranca acá) — `venta/pantalla_venta.dart`, `columna_busqueda.dart`, `columna_carrito.dart`, `columna_cobro.dart`
Grilla `1fr | 620 px`, `gap 24`, `padding 106 32 26 56`. **Sin partículas ni título tipeado.**

**Columna izquierda**
1. Fila superior: `eyebrow` "Caja abierta · {usuario} · lunes 5 de octubre" + `h1` **"Vender"** (40); a la derecha, **acciones secundarias** apagadas (`chip sm`, texto `mute`): "Más:" **Varios · Alt+V**, **Gasto · -** e **Ingreso · Alt+I**. Son secundarias a propósito: lo principal de la caja es pagar proveedor.
2. **Buscador grande** (`sbig`): alto **72**, pastilla `s`, lupa 28, campo 22/450, `kbd` "Ctrl+F"; foco = anillo azul 3 px + fondo `paper`; placeholder que se escribe solo (5.2). A su derecha, **"Pagar proveedor · Alt+P"**: botón **oscuro** de alto 72 con ícono de camión, la **acción principal de caja** (abre el diálogo rápido de 8, `pagarRapido`). **Foco al arrancar.** Dropdown **anclado al campo** (radio 36, sombra, entra `translateY(18→0)` `.22s`): hasta **7** filas con círculo de categoría 40, nombre 21/450, stock y precio (21/600, ancho 110); flechas + Enter; una sola coincidencia viene preseleccionada. "Sin coincidencias" si no hay (nunca alta rápida).
3. **Categorías**: chips "Más vendidos" (entrada por defecto, calculada con historial real sin anuladas; sin historial, el catálogo entero), "Todos" y una por categoría.
4. **Grilla**: **5 columnas**, `gap 14`, scroll propio, tiles de min-alto **150**, radio 30, `padding 20×22`: círculo de categoría 44 (inicial); si está en el carrito, fondo `blue-l`, aro azul 2 px y **contador** arriba a la derecha (pesables en gramos, "250 g"); nombre 18/500 (máx. 2 líneas), precio 25/500 tabular (pesables "/kg"); **"Quedan N"** (ámbar) si stock < 15 u. y no es pesable; **"Sin stock"** (rojo), tile atenuado (`opacity .45`) y **no se puede agregar**. Clic agrega 1 (pesables 250 g).

**Columna derecha — el ticket** (aside `s`, radio **52**, `padding 22`, alto completo, `gap 14`)
- **Pestañas de ventas abiertas**: "Venta 1 ③ · Venta 2 ② · + Nueva Alt+N · … · Ver abiertas". Borradores persistentes (no descuentan stock ni tocan la caja hasta cobrar). **No se puede cerrar caja ni cambiar de turno con ventas abiertas con productos.**
- **Carrito** (único scroll de la columna, `gap 6`): línea `cl` (fondo `paper`, radio 28): nombre 17/500 (**2 líneas**) + "$ 2.100 c/u" (pesables "$ 14.600 el kilo"); **stepper** (− / cantidad o gramos / +; pesables ±50 g; restar en 1 unidad saca la línea); subtotal 19/600; tacho. Última agregada con aro azul. **Nombre en rojo** si el stock quedó ≤ 0 (se vende igual). Doble clic en la cantidad → "Cantidad exacta". Vacío: ícono scan con aro pulsante + "Escaneá un código o buscá un producto para empezar la venta".
- **Tira de IA** (entre el carrito y el total, `aistrip`: fondo `blue-l`, radio 26, `padding 10×10×10×16`, ocupa 54 px **solo cuando hay una sugerencia**): etiqueta ✦ **IA** + frase corta ("Con Cerveza suelen llevar Marlboro (2,1× más)") + botón azul **"+ Agregar"** (un toque suma el producto) + ✕ (no sugerir más ese par en esta sesión). Sale de los pares que "se llevan juntos" (los mismos de las promos sugeridas); nunca tapa el total ni los medios, aparece con `translateY(10)→0` `.35s` y se oculta si el producto ya está en el carrito o sin stock.
- **Total** (`tot`, hero, radio 44, `padding 20×30`): "Total a cobrar" + botón **Descuento**; importe **76/450** con *tween*+pulso; etiquetas **solo cuando corresponden**: "Descuento 10 % −$ 1.625", "Recargo cigarrillos +$ 300", "Redondeo +$ 50".
- **Medios de pago**: grilla **2×2**, `gap 10`, alto 72, radio 30, fondo `paper`: círculo de ícono + nombre 20/600 + atajo `ALT+E/Q/D/X`. Elegido = se llena con su color y texto blanco. **Efectivo viene preseleccionado** en toda venta nueva (es lo que más se cobra: Enter cobra de una); se puede cambiar a otro medio con un toque o su `Alt+`. *(Hoy la app exige elegir; este cambio saca un paso en cada venta, ver 14.3.)*
- **Cobrar**: pastilla azul alto 78, 24/600, `kbd` Enter, círculo con flecha. Debajo, **solo con QR o Tarjeta**: botón `sm out` "Cobrar a mano, sin terminal · Alt+M" (el espacio de 44 px se reserva siempre). **Cobro más rápido posible:** con Efectivo preseleccionado y el campo de búsqueda vacío, **`Enter` abre el cobro y `Enter` lo confirma como "justo"** (2 teclas); con vuelto, se tipea lo que paga o se toca un billete sugerido y `Enter`.
- Si el carrito es largo, **solo él scrollea**; total, medios y Cobrar quedan a la vista.

Cálculo: bruto → descuento (sobre el total) → recargo de cigarrillos (solo virtual) → redondeo (efectivo y mixto). Estados: vacía · con búsqueda · con pesable (`200 queso` filtra pesables y muestra "$ 1.960 por 200 g") · con cigarrillos y QR · caja cerrada (al entrar aparece "Abrir caja" sin poder cerrarse) · varias abiertas. Escáner: 8–14 dígitos + Enter agrega 1 (y suma si se repite); desconocido → "Sin coincidencias".

### 7.2 Inicio — `dashboard/pantalla_dashboard.dart` (+ `equilibrio/`)
**Una sola pantalla**, sin scroll. Encabezado: `eyebrow` "Lunes 5 de octubre · caja abierta desde las 8:02", `h1` **"Hola, {quien abrió la caja}"** (sin caja abierta: "Inicio"), a la derecha **segmento "Hoy · Este mes"** y botón azul **"Nueva venta →"**. El segmento **reemplaza al scroll**: cambia el cuerpo, no la pantalla.
- **Hoy**: fila 1 de **292 px** (`1.25fr | 1fr | 1fr`): **hero "Hoy vendiste"** (importe 60 que cuenta, "Ganancia" en verde con etiqueta **"+8 % vs lunes pasado"**, barra efectivo/Mercado Pago 48/52 y cifras de cada medio) · **indicadores 2×2** (Ganancia hoy, Tickets, Ticket promedio, **Falta separar** en tarjeta ámbar clickeable → Separaciones) · **Más vendidos hoy** (5 filas). **Fila de IA** (3 tarjetas `aistrip` en una línea, 54 px): "El **Fernet** se vende 4 por día y quedan 9: alcanza 2 días" [Pedir → Proveedores en Coca-Cola], "**Cerveza + Marlboro** se llevan 2,1× más: armá una promo" [Ver → Promos con sugerencias], "Entró un cobro de MP de **$ 6.400** sin venta" [Revisar → campana]. Fila 2 (`flex:1`, mismas columnas): **Ventas por hora** (13 barras 8–20 h, pico azul, barras que llenan la altura disponible) · **Stock bajo** (6 productos, cada uno con **cuánto alcanza**: "alcanza 2 días", "pedir hoy") · **Encargues y deudas** (5 filas + "Ver todos").
- **Este mes**: fila 1 de **150 px** con 4 tarjetas (*Ganancia bruta del mes* hero, *Fijos cubiertos* 78 % + barra, *Venta diaria de equilibrio*, *Fijos pendientes de pago* ámbar); fila 2 (`flex:1`, 3 columnas iguales): **Estado de resultados** (ventas, costo de la mercadería, ganancia bruta con %, fijos, variables, resultado, sueldo objetivo, queda para el negocio, ya retirado, **retirable hoy** + "Retirar ganancia") · **Margen necesario** (2 campos, margen necesario vs. actual, etiqueta "Tu margen alcanza"/"Te faltan N puntos", nota de que el precio sugerido no cambia nada solo) · **Fijos del mes** (concepto, importe, estado Pagado/Pendiente/Falta cargar, "Pagar"/"Cargar", "+ Nuevo"). Si falta cargar un fijo, la tarjeta que depende de él muestra un aviso en vez de un número (regla 12). El acceso "Este mes" del mega-menú abre este segmento.

### 7.3 Proveedores — `proveedores/*`
Encabezado: `eyebrow` "Lista, cuenta corriente y precios" + `h1`; acciones, en este orden: **✦ Leer factura** y **✦ Promos sugeridas** (botones de IA: fondo `blue-l`, texto azul, ícono destello), **Importar CSV** (tonal) y **Nuevo proveedor** (oscuro). La IA está **en la barra de acciones**, no escondida en un diálogo. Cuerpo en grilla **`470 | 1fr`**:
- **Izquierda**: buscador (alto 54), chips Todos/Con deuda, **lista scrolleable** de filas (círculo-camión, nombre, "N productos · pedido martes", etiqueta **"Le debés $ X"** roja o **"Al día"** verde, más una etiqueta ámbar **"Pedir hoy"** cuando su día de pedido es hoy). Seleccionada = azul claro.
- **Derecha**: fila fija de 2 bloques — ficha (nombre `h2` 28, "Editar", "Pedido {día} · entrega {día} · colchón N %", botones tonales **Edición masiva, Comparar precios, Leer una factura, Contar stock, Avanzado**) y **hero de cuenta corriente** (importe 42, **Pagar a proveedor** azul, "Ver movimientos"); fila "Productos de {proveedor}" + "Nuevo producto"; una **tira de IA** cuando hay productos de ganancia baja ("**Cerveza rubia 1 L** tienen ganancia baja (29 %). Subir 5 % suma ~$ 2.600 por mes." [Revisar → Edición masiva]) y la **tabla** (contenedor scrolleable que se ajusta al contenido, encabezado fijo): Producto (+ "pesable") · **Código** · Costo · Precio · **Ganancia** (etiqueta "N % gan.": verde ≥ 30, neutra 22–29, ámbar < 22; **sobre el precio**) · **Vendido 30 d** · Stock (ámbar < 15; "Sin stock" rojo) con **"alcanza N d"** debajo (ámbar si < 5 días) · Editar.
- Cambiar de proveedor re-renderiza solo el detalle. "Contar stock" → 7.9.

### 7.4 Separaciones — `separaciones/pantalla_separaciones.dart`
`eyebrow` "Solo lo de hoy · lunes 5 de octubre". Acciones **Ganancia** (tonal), **Retirar plata** (oscuro). Fila de 4 tarjetas (cifras de 42 que cuentan): **A separar del cajón** (hero) · **A separar de Mercado Pago** (hero azul) · **Reserva diaria de fijos** (ámbar) · **Te queda** (verde). Una línea: `sec` "A separar por proveedor" + chip ámbar "⚠ 3 productos sin costo" (abre el diálogo) + a la derecha "Separaste $ X de $ 295.000". **Lista** (scrolleable, se ajusta al contenido) de filas (min 58): tilde circular (lleno verde al marcar y el nombre se **tacha** y atenúa), nombre 17,5/550 + "Pedido martes · entrega jueves · 21 % del total · le debés $ X", etiqueta de caja (**Cajón** verde / **Mercado Pago** azul), importe 19/600 y el botón oscuro **"Pagar"** (camión) que abre el pago rápido **con ese proveedor ya elegido**: separar y pagar en la misma fila. Solo lo de hoy.

### 7.5 Historial — `historial/*`
Acciones: **"Cargar día histórico"** y segmento **Ventas · Movimientos · Cierres**. Debajo, chips **Hoy / Ayer / Últimos 7 días / Este mes** (no en Cierres) y buscador (420).
- **Ventas · Hoy**: grilla `540 | 1fr`. Izquierda: hero chico fijo ("5 ventas · hoy" + total 30) y **lista scrolleable** de filas (círculo con ícono del medio, "Venta #1181", "12:48 · Efectivo", importe). Derecha: **ticket** (scrolleable por si es largo; título 30, fecha · hora · cajero, etiqueta del medio, líneas, subtotal, redondeo, **Total 28/450**, ganancia verde) con **Reimprimir**, **Editar** (→ 7.8) y **Anular venta** (rojo → diálogo con motivo obligatorio).
- **Otros períodos** y **Cierres**: lista de días (fecha, N ventas, importe, etiqueta **Cuadró / Faltaron $ X / Sobraron $ X**) → **Detalle del día** (7.7).
- **Movimientos**: tabla Hora · Tipo · Motivo · Caja · Monto (rojo −, verde +), contenedor ajustado al contenido.
- Anular **solo con la sesión de caja abierta**; revierte stock y caja, **nunca borra**; si se cobró por MP, devuelve por MP.

### 7.6 Encargues — `encargues/pantalla_encargues.dart`
Acción **Nuevo encargue** (oscuro). Fila de 3 tarjetas (cifras 40): **Apartados** (hero), **Deudas por cobrar** (ámbar), **Para hoy**. Debajo, **dos columnas** (`1.25fr | 1fr`) con lista scrolleable cada una: **Apartados** (inicial, cliente 17/600, detalle, importe, **Entregar** azul, **Cancelar** rojo — devuelve el stock) y **Deudas** (inicial, detalle, importe, **Cobrar**). Apartar **descuenta el stock en el momento**; "Entregar" ofrece **"Cobrar ahora (abre la venta con eso cargado)"** o **"Entregar y anotar deuda"**.

### 7.7 Detalle de un día cerrado — `historial/pantalla_detalle_dia.dart`
Desde Historial › Cierres. `eyebrow` "Historial · Cierres", `h1` con el día; etiqueta del resultado, **Generar PDF**, **Volver a Cierres**. Fila de 4 cifras (36–44): **Vendido** (hero, "72 ventas"), **Efectivo**, **Mercado Pago**, **Ganancia** (verde). Debajo (`1fr | 440`): tabla de ventas (# · hora · medio · total · reimprimir/editar) con scroll propio; a la derecha **"Vendido por proveedor"** (scrolleable) y **"Anuladas"** (con motivo).

### 7.8 Editor de una venta cobrada — `historial/pantalla_editor_venta.dart`
`eyebrow` "Venta #1181 · 12:48", `h1` "Editar venta", "Volver al historial". Cuerpo `1fr | 480`: izquierda tarjeta **Productos** (scrolleable: stepper, tacho, "Agregar producto") y tarjeta **Medio de pago** (segmento); derecha hero **Total corregido** (56, con *tween*) + "Original $ 16.300 · diferencia ±$ X", nota ámbar ("Al guardar se revierten el stock y la caja de la venta original y se vuelven a aplicar… Queda registrado quién y cuándo"), **Guardar cambios** (azul → Historial con toast) y **Descartar cambios**.

### 7.9 Contar stock por proveedor — `stock_proveedor/*`
Desde Proveedores › "Contar stock" y el mega-menú. `h1` "Contar stock · {proveedor}" + Volver. Fila de 4 tarjetas (cifras 36): **Contados** (n/n), **Con diferencia**, **Falta, a costo**, **Tilde "está igual"** ("Marcar todo igual"). Chips **Todos / Con diferencia / Agotados primero**. Tabla (scroll propio, contenedor ajustado al contenido): Producto (+código) · Dice el sistema · **Contado** (stepper o tipeado) · **Diferencia** (etiqueta verde "igual", ámbar +N, roja −N). **Nada toca la base hasta "Aplicar ajustes"** (azul, abajo a la derecha); cada ajuste deja rastro en `movimientos_stock`.

### 7.10 Cargar un día histórico — `carga_historica/*`
Desde Historial. Producto por producto. Cuerpo `1fr | 560`: izquierda tarjeta **Fecha del día** (chips + nota "el costo se estima con el de hoy; después se corrige") y tarjeta de **búsqueda** con chips de productos; derecha **ticket** "Venta del 2 de octubre" (líneas con scroll propio, stepper, tacho), **Total**, segmento de medio y **Guardar venta**. Más simple que Venta (sin atajos).

### 7.11 Cierre de caja — `cierre/*`
Pantalla de **foco**: **sin pastilla de navegación**; arriba logo + "Paso N de 2" + "Volver a Venta" (hasta el paso 3). Contenido centrado de hasta **1240 px**, **todo en una pantalla** (dos columnas). **No se puede cerrar sin contar.**
1. **Paso 1 — Contar (a ciegas):** izquierda (440): `eyebrow` "Cierre obligatorio · conteo a ciegas", `h1` 46 "¿Cuánta plata hay en cada caja?", lead y nota con candado. Derecha: nota ámbar con **"Descartar"** si hay ventas abiertas con productos (y **Confirmar** queda desactivado); campo grande **Efectivo contado (cajón)** con chips "Cuadra justo", "$ 250.000", "$ 255.500"; fila de dos campos **Mercado Pago contado (según la app)** con **"Traer saldo"** (llena el saldo real y queda editable) y **Lata de cigarrillos contada**; **Confirmar conteo** (azul).
2. **Paso 2 — Resultado:** columna izquierda: `eyebrow` "Resultado del conteo", `h1` 40 dinámico ("Cuadró el cajón" / "Faltan $ X en el cajón" / "Sobran $ X…"), hero **Diferencia del cajón** (60 + etiqueta de tono), tres tarjetas chicas (**Mercado Pago**: la diferencia suele ser la comisión; **Lata de cigarrillos**; **Redondeo de hoy**: informativo, no es descuadre) y lista (debería haber / contaste / fondo para el vuelto de mañana / separación de cigarrillos / reserva de fijos del día). Columna derecha: tarjeta **"Mercado Pago según Mercado Pago"** (cobrado en la app, comisiones, neto, cobros sin venta, ventas sin cobro; **nunca frena el cierre**), **Cerrar caja** (azul) y "Volver a contar".
3. **Paso 3 — "Caja cerrada":** celebración (5.3): círculo verde 130 con tilde dibujado, `h1` 56 "Caja cerrada", resumen del día y de la copia, botones **Cerrar el sistema** y **Volver a Venta** (reabre y fuerza **Abrir caja**).
Reglas: caja esperada = inicial + efectivo de ventas − gastos en efectivo (**el redondeo no se suma aparte**); MP esperado = inicial + pagos por MP − gastos con MP; la lata se arquea igual; un día cerrado se puede reabrir con confirmación; si se termina tarde el día queda abierto.

### 7.12 Configuración — `configuracion/*`
`eyebrow` "5 grupos, 16 secciones", `h1`, buscador "Buscar un ajuste…" (filtra por palabras clave, ignora acentos). **Dos paneles** `320 | 1fr` (`gap 40`): **navegación vertical** con scroll propio (grupos 12/700 mayúsculas; 16 filas de 40 de alto) y **contenido de la sección** con scroll propio (`eyebrow` del grupo, `h2` 34, descripción 17 y controles, ancho máx. 1000). Grupos y secciones:
- **Negocio:** Comercio (nombre, rubro, encabezado del ticket, logo, imprimir logo) · Usuarios (lista con rol; renombrar; agregar).
- **Caja y cobros:** Caja y redondeo (redondear efectivo; paso $ 50/100/200; fondo fijo; reserva diaria de fijos; día del retiro) · Cigarrillos (primer atado 300, adicional 100, suelto 50; ganancia fija por atado ~1.000; "Distribuidora cobra solo en efectivo") · Vuelto (producto del botón: Caramelo; Alt+C) · Medios de pago (Efectivo, Mercado Pago [QR+débito+crédito], Mixto; renombrar).
- **Productos:** Ganancia por categoría (stepper % por categoría).
- **Equipos y cuenta:** Cuenta de Nodo Sur · Impresión y posnet (impresora, carpeta de PDF, "Cobrar e imprimir por Nodo Sur", terminal Point, token local avanzado, **vista previa del ticket** monoespaciada, probar impresión/terminal) · Celular (código de 6 dígitos grande en hero, vinculados, descargar APK) · Asistente IA (clave Gemini, "Probar y guardar") · Respaldo (carpeta, última copia, copia automática, hacer copia, restaurar con confirmación, últimas copias) · Versión (instalada, canal Estable/Beta, actualizar en 3 pasos).
- **Apariencia:** **Tema y movimiento** (Claro/Oscuro/Automático **en vivo**; Completo/Reducido; interruptores de **celebraciones con partículas** [encendido], **etiqueta que acompaña al mouse** [apagado] y **desplazamiento suave** [apagado]) · Menú (orden ↑↓ y mostrar/ocultar; Venta no se oculta) · Módulos (turnos y arqueo cada 2 h, encargues, fiado, Point).

---

## 8. Diálogos (modales al centro) — `lib/ui/comun/modal.dart` (reescribir estilo)

**Contenedor:** velo `scrim` + blur 6 (`.25s`); modal centrado, ancho **760** (`n`: 620; `w`: 1060), radio 48, `max-height = alto−100`, sombra; entra `translateY(22→0) + scale(.96→1) + fade`, `.32s ease`; encabezado `padding 36×40` con `h2` 38 + subtítulo 17 `mute` y **✕** (46, rota al hover); cuerpo scrolleable `padding 14×40`, `gap 14`; pie `padding 16×40×36` con botones **apilados** a ancho completo: primario `lg` (azul; rojo para destructivo) y secundario `out` "Cancelar" (o fila de 2 en el editor de producto). **El velo cierra**, salvo diálogos marcados `nodismiss` (terminal Point y "Abrir caja"). **Esc cierra** (mismas excepciones). Enter confirma el primario (con guarda: no confirma en los primeros 350 ms ni con tecla repetida, para no auto-confirmar el Enter que lo abrió). Al abrir, foco al primer campo.

Catálogo (nombre en el mock → contenido):

**Caja / Venta**
- `efectivo` **Cobrar en efectivo**: hero con el total (72); campo grande **"Con cuánto paga"**; chips *Justo* y los siguientes billetes ≥ total (hasta 4, entre múltiplos de 1.000/5.000/10.000 y 20.000/50.000); tarjeta **vuelto** (verde "Dale el vuelto $ X" / roja "Faltan $ X"); si el vuelto es **exactamente $ 100**: nota ámbar + botón **"Dar caramelo · Alt+C"** (agrega la línea y actualiza). Confirmar cobro.
- `canal` **QR/Tarjeta**: hero azul con el total; segmento **QR · Débito · Crédito**; nota ("el crédito va siempre en 1 pago y sin recargo…"; "QR, débito y crédito son un solo medio en la caja: Mercado Pago"); botones **Cobrar con la terminal**, **Cobrar a mano (Alt+M)**, Cancelar.
- `terminal` **Terminal Point** (sin ✕, no se cierra con el velo): estados **esperando** (anillo pulsante + spinner, "Mandamos la orden de $ X (QR). La orden vence a los 2 minutos."), **confirma** ("Confirmá en la terminal"), **aprobado** (círculo verde + tilde dibujado; cierra solo a los 0,9 s y abre *Venta cobrada*), **rechazado**, **venció** (2 min) y **sin conexión**, estos tres con **Reintentar** / **Cobrar a mano** / **Cancelar**. En el mock avanza solo (2,8 s → 2,6 s → aprobado) y hay una **barra "Solo del mock · simular"** (ver E-3).
- `mixto` **Pago mixto**: hero con total; campo grande **"Parte en efectivo"**; chips *Mitad / $ 10.000 / $ 20.000*; lista "En efectivo" (verde) / "Con Mercado Pago (el resto)" (azul); el recargo de cigarrillos se aplica **completo**. Al cobrar pasa al diálogo de canal para la parte virtual.
- `cobrada` **Venta cobrada** (**se cierra sola**): partículas `ok`, círculo verde 132 + tilde dibujado, importe 80, "Venta #N · {medio}{ · cobrada a mano}{ · vuelto $ X}"; botones **"Siguiente venta · cualquier tecla"** (azul) e **Imprimir ticket**, y debajo una **barra de cuenta regresiva** de 4 px (2,4 s). A los **2,4 s** o con **cualquier tecla o clic** (después de 300 ms, para no confundir el Enter del cobro) se cierra, la venta cobrada sale de las abiertas y el foco vuelve al buscador con la venta nueva (medio Efectivo): **cero toques entre una venta y la siguiente**. "Imprimir ticket" detiene la cuenta. Configuración › Impresión puede imprimir **automático**.
- `descuento`: segmento **Porcentaje % / Monto $**; campo grande; chips 5/10/15/20/30 %; lista Subtotal / Descuento / **Total con descuento**; **Aplicar** y **Quitar descuento**.
- `abiertas` **Ventas abiertas**: lista (nombre, "N productos · medio", total, **Abrir**, **Descartar**), nota sobre cierre/turno, **Nueva venta · Alt+N**.
- `cantidad` **Cantidad / Peso en gramos**: campo grande con selección; chips 100/200/250/500/1000 g; subtotal en vivo.
- `varios` **Varios**: monto suelto; chips $ 500/1.000/2.000/5.000; "No descuenta stock y queda marcado para revisar al cierre".
- `movimiento` **Gasto o ingreso** (**secundario**; se abre con `Alt+G`/`-` o `Alt+I`, desde los chips "Más:" de Venta o el asistente): segmento Gasto/Ingreso, segmento **Cajón normal / Lata de cigarrillos / Mercado Pago**, monto, **motivo obligatorio** con chips sugeridos (gasto: Proveedor, Limpieza, Fletes, Retiro, Otro; ingreso: Cambio, Aporte del dueño, Cobro de deuda, Otro). *Un gasto a proveedor se paga con **Pagar proveedor**, no con este diálogo.*
- `arqueo` **Arqueo intermedio** (a ciegas → resultado con diferencia y tono).
- `apertura` **Abrir caja** (sin ✕): tres campos precargados con lo último contado (caja normal $ 30.000, lata $ 41.500, Mercado Pago $ 250.800), nota; **Abrir caja**.
- `turno` **Cambiar de turno** (3 pasos): elegir quién entra (+ nota ámbar si hay ventas abiertas con productos → bloquea) → **contar el cajón** a ciegas → resultado (esperado/contado/fondo) → "Abrir el turno de {nombre}".
- `atajos` **Atajos de teclado** (lista de 4.6, incluidos `Alt+P`, `Alt+G`, `Alt+1…6` y `Ctrl+K`).
- `pagarRapido` **Pagar a proveedor** (**la acción principal de caja**; `Alt+P` desde cualquier pantalla, botón oscuro en Venta, "Pagar" en cada fila de Separaciones, "Pagar a proveedor" en el detalle de Proveedores y entrada de primer lugar del asistente). Ancho 1060, **una sola pantalla, sin pasos**: izquierda, campo **Proveedor** con foco (escribir filtra; la lista va **ordenada por deuda**: primero los que se le debe, cada fila con su deuda en rojo o "Al día" y el día de pedido; ↑/↓ cambian la selección); derecha, hero con **"Le debés a {proveedor}" y la deuda**, campo grande **Monto a pagar ya cargado con la deuda total**, chips **Todo · $ X** y **Mitad · $ Y**, segmento **"De dónde sale la plata"** (Cajón · Mercado Pago · Lata · Fuera) que **recuerda la última elección**, y "Después de pagar le debés $ Z" en vivo. **Teclado: `Alt+P`, escribir 3–4 letras, `Enter` (pasa al monto), `Enter` (paga).** Pagar más de lo que se debe pide tocar **Pagar** una segunda vez. Al pagar: cierra, descuenta la deuda y muestra el aviso **"Pagaste $ X a {proveedor} · del cajón" con botón Deshacer** (5 s) en lugar de pedir confirmación; las pantallas de Inicio, Proveedores y Separaciones se actualizan. Reemplaza al viejo `pagarProv` (que ahora abre este mismo diálogo con el proveedor ya elegido).

**Proveedores:** `nuevoProv` · `editarProv` · `avanzadoProv` (solo cobra en efectivo; excluir de reposición) · `pagarProv` (abre `pagarRapido` con el proveedor elegido, ver arriba) · `ctaCte` (movimientos: compras restan, pagos suman) · `edMasiva` (segmento: Subir precio % · Subir costo % · Cambiar proveedor · Cambiar categoría; **previsualiza cada precio nuevo** `ceil`; aviso ámbar si ≥ 50 %) · `csv` (zona de arrastre + resumen nuevos/actualizados/errores) · `promos` (lista + **"Sugerir promos con IA"**: "se llevan juntos (90 días)" con "Crear"; la IA solo sugiere) · `comparar` (costo por proveedor, "Más barato", % extra, nota de margen) · `factura` (**lectura de prueba**: renglones vinculados/a revisar; no actualiza costos sola) · `editarProd` (1060 px: nombre, código, costo, **ganancia sobre el precio** con chips 20–40 % que recalculan el precio con `ceil(costo/(1−g))`, precio editable, aviso "Ganás $ X por unidad" verde/ámbar < 20 %, stock actual/mínimo, interruptor **Pesable**, **historial de precios**).

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
| Movimiento | `ui/tema/movimiento.dart` (+ nuevos) | `Reveal` (corto), `CifraQueCuenta` (solo Inicio/Separaciones), `CampoParticulas` (**solo** celebraciones), `CursorPastilla` y `ScrollSuave` (**opcionales, apagados por defecto**); flag global de reducción. **No se implementan:** título tipeado, tablero 3D, cinta de avisos, titular que se enciende |
| Kit | `ui/comun/*` | `Boton`, `Chip`, `Segmento`, `Etiqueta`, `Tarjeta/Hero`, `ListaAgrupada`, `Campo`, `Interruptor`, `Stepper`, `Modal` (nuevo estilo), `Toast`, `EstadoVacio` |
| Navegación | `ui/navegacion/*` | `NavbarSuperior` → pastilla flotante + `MegaMenu` (OverlayEntry) + búsqueda en la pastilla + `BuscadorFunciones` |
| Ventana | `ui/ventana/ventana_escritorio.dart` | barra de 40 px (estado de caja y copia) |
| Pantallas | `venta/*`, `dashboard/*`, `equilibrio/*`, `proveedores/*`, `separaciones/*`, `historial/*`, `encargues/*`, `cierre/*`, `configuracion/*`, `stock_proveedor/*`, `carga_historica/*`, `impresion/*`, `respaldo/*` | disposición y contenido de la sección 7; la **lógica** de cada controlador **no cambia** |
| Dominio/datos | `domain/*`, `data/*` | **sin cambios** |

Equivalentes en Flutter: reveal = `Entrada` + detector de visibilidad (puede usarse `visibility_detector`: ya no hay restricción de hardware); partículas (solo celebraciones) = `CustomPainter` + `Ticker`; cursor-pastilla = `Overlay` + `MouseRegion` + posición con *lerp*; mega-menú = `OverlayEntry` con `FadeTransition`/`SlideTransition`; vidrio = `BackdropFilter(ImageFilter.blur)`; scroll suave = `Listener(onPointerSignal)` + `animateTo`; *count-up* = `TweenAnimationBuilder<double>`.

---

## 13. Plan de implementación (una fase por vez, cada una se prueba)

1. **Tema y kit**: tokens, paleta, tipografía (escala de 3.2), retícula de página (`.page` + `phead` + cuerpo `Expanded` con listas internas), íconos, componentes de 6, `Modal`, `Toast`. Capturas de la vitrina (`test/capturas/pantalla_muestra_kit.dart`) en claro y oscuro.
2. **Movimiento**: `Reveal` corto, *tweens* de cifras, placeholder que se escribe, celebraciones, flag de reducción y los interruptores de Configuración. Pruebas de que **no retrasan** foco/teclado.
3. **Ventana y navegación**: barra de 40 px, pastilla flotante, mega-menús, búsqueda en la pastilla, notificaciones, Ctrl+K.
4. **Venta** completa + sus diálogos de caja (se prueba con escáner y teclado reales).
5. **Cierre de caja** y **Separaciones** (tocan plata; correr `conciliacion_caja_test`).
6. **Inicio** (Hoy / Este mes), **Proveedores** (+ conteo), **Historial** (+ detalle, editor, carga histórica), **Encargues**, **Configuración**.
7. Capturas `test/ui/capturas_escritorio_test.dart` contra el mock, `flutter analyze` ("No issues found!") y `flutter test --exclude-tags bench`. Corregir `DISENO.md`/`CLAUDE.md`/`ESTADO.md` en el mismo cambio de cada fase.

Criterios de aceptación transversales: (a) **ninguna pantalla scrollea la ventana** a 1920×1080 ni a 1366×768 (solo listas internas); (b) la regla dura de Venta se cumple en ambas resoluciones; (c) con Movimiento = Reducido y con "reducir animaciones" de Windows no hay ninguna animación; (d) escaneo + Enter + cobro no se demoran; (e) claro y oscuro con contraste legible; (f) ningún importe ni botón de cobro lleva gradiente o partículas; (g) los textos del mock se usan **tal cual** (voz rioplatense, sin jerga).

---

## 14. Excepciones, límites del mock y pendientes

### 14.1 Excepciones explícitas (en la app real va distinto del mock)
- **E-1 Peso 450 / fuente.** El mock usa Figtree variable. Si la app mantiene fuentes estáticas (400/500/600/700), los títulos van en **500** (desvío ya aceptado por el dueño para el celular). Alternativa fiel: sumar Figtree variable (~100 KB) con `FontVariation('wght', 450)`.
- **E-2 Montos.** El mock usa pesos enteros; la app usa `int` en centavos con `formatearARS`.
- **E-3 Solo del mock (no se implementa):** la barra de herramientas de arriba (selector "Ir a un estado…", Tema, Movimiento, "Atajos", chips de pantalla), la barra **"Solo del mock · simular"** del diálogo de terminal, la simulación automática de la terminal, los datos de ejemplo, la escala 1920×1080 y la ventana dibujada en HTML (la real es `ventana_escritorio.dart`).
- **E-4 Recargo de cigarrillos:** el mock modela solo atados (300 + 100 por adicional); la app suma además 50 por cigarro suelto.
- **E-5 Terminal real:** el mock usa tiempos fijos; la app usa la Orders API real (la orden vence a los 2 minutos; cancelar por API solo en `created`).
- **E-6 Factura:** el mock muestra el resultado de leer una factura; en la app solo hay **lectura de prueba**.
- **E-7 Cursor-pastilla:** opcional y apagado; si se enciende, el puntero real **no se oculta**.
- **E-8 Reglas de `CLAUDE.md`:** "animaciones menores a un quinto de segundo" sigue **casi** vigente: el reveal (.4 s), el *tween* del total (.32 s) y los cifras que cuentan (.7 s) son más largos pero **no bloqueantes** (5.1). Actualizar `CLAUDE.md` con esa precisión.
- **E-9 Pastilla "levantada":** como la ventana no scrollea, la pastilla pasa al estado `navbg2` con sombra **solo mientras el mega-menú está abierto** (en el sitio se levanta al scrollear). Es una adaptación deliberada.

### 14.2 Responsive de escritorio (diseño, **no verificado en el mock**)
Diseñado a 1920×1080 (alto útil 1040). En **1366×768** (alto útil ~728) se mantiene "sin scroll de ventana" así: **Venta**: grilla de 4 columnas, tiles de 120 de alto, ticket de 560, total a 56, medios de 60, Cobrar de 64, buscador de 60 (el carrito scrollea); **Inicio**: filas de 260/110 en vez de 330/150; **páginas con encabezado**: `h1` baja a 40 y `padding-top` a 96; **pastilla**: oculta la marca y "Cambiar de turno" pasa a ícono. Las listas y tablas internas absorben el resto. No hay diseño para menos de 1280 px de ancho.

### 14.3 Funciones o decisiones **nuevas** del mock a confirmar con el dueño antes de construirlas
1. **Mega-menú** que agrupa accesos (no agrega funciones, cambia cómo se llega a Edición masiva, Comparar precios, Conteo, etc.).
2. **Asistente universal (Ctrl+K)**: unifica búsqueda de productos, acciones y atajos (viene del "Buscador de funciones" del celular; no existe hoy en la PC). **La pregunta libre a la IA y las respuestas con datos del negocio son funciones nuevas** (hoy la IA solo hace promos sugeridas y lee facturas); hay que definir qué datos ve la IA y qué botones de acción puede ofrecer (siempre confirmando).
3. **IA contextual**: tira de sugerencia en el ticket de Venta (pares "se llevan juntos"), tiras de IA en Inicio (stock que alcanza N días, promos, cobros sin venta) y en Proveedores (ganancia baja); botones **✦ Leer factura** y **✦ Promos sugeridas** en la barra de Proveedores. Requieren la clave de Gemini cargada; sin clave, esas tiras no aparecen.
4. **Pagar proveedor como acción principal** (botón fijo en Venta, `Alt+P` global, "Pagar" en Separaciones) con el diálogo rápido; **Gasto, Ingreso y Varios pasan a secundarios**. Decisión del dueño de esta ronda; falta confirmar el tamaño de cada acceso.
5. **Medio de pago inicial = Efectivo** en toda venta nueva (hoy hay que elegir uno). Saca un paso por venta; si el cajero cobra por QR/tarjeta, un toque o `Alt+Q/D`.
6. **"Venta cobrada" que se cierra sola** (2,4 s o cualquier tecla) y **Deshacer** en lugar de confirmaciones (quitar línea, cancelar la venta con Esc, registrar un pago). Cambia dos costumbres: hoy "Venta cobrada" espera un clic y cancelar no se puede revertir.
7. **Navegación**: sin logo ni nombre del local ni lupa; tuerca de Configuración; `Alt+1…6` para ir a cada sección.
8. **Inicio con interruptor "Hoy / Este mes"** en una sola pantalla, **Contar stock** y **Comparar precios** accesibles desde el menú.
9. **Ver movimientos** de la cuenta corriente, **aviso de ≥ 50 %** en edición masiva y **"Marcar todo igual"** en Contar stock (propuestos antes, nunca confirmados).
10. **Colores de medio** del celular (Efectivo verde, MP azul, Tarjeta gris, Mixto ámbar): cambian el color al que el cajero está acostumbrado (naranja/violeta).
11. **Columnas nuevas en la tabla de productos** (Código, **Vendido 30 d**, **alcanza N días**) y datos nuevos en Inicio/Separaciones ("+8 % vs lunes pasado", "% del total", "le debés $ X"): salen de ventas y stock existentes, pero son consultas nuevas.

### 14.4 Lo que no se verificó
El mock se probó en Chromium (flujos con mouse y teclado, claro/oscuro, reducido, y un chequeo automático de que ninguna pantalla recorta contenido fuera de listas internas), sin errores de consola. **No se probó en Windows real, ni con escáner/impresora/terminal reales, ni en 1366×768** (14.2 es diseño, no verificación). El costo del `BackdropFilter` (vidrio de la pastilla y velos) hay que medirlo en la PC del local.

---

## Apéndice A — Qué hay en el mock, por estado (para recorrerlo)
Selector "Ir a un estado…" (42): Venta vacía · buscando "coca" · pesable "200 queso" · cigarrillos con QR (recargo) · Cobro efectivo · QR/tarjeta · Terminal esperando · Terminal rechazada · Cobro mixto · Venta cobrada · Descuento · Ventas abiertas · Cambiar de turno · Abrir caja · Gasto o ingreso · Arqueo intermedio · Notificaciones · Mega-menú de Proveedores · Búsqueda global · Asistente (sugerencias, producto, pregunta a la IA) · Pagar a proveedor · Inicio "Este mes" · Editar producto · Pagar a proveedor · Edición masiva · Leer factura · Conteo de stock · Ganancia del día · Historial movimientos · Historial cierres · Anular venta · Detalle de un día · Editar una venta · Cargar día histórico · Cierre resultado · Caja cerrada · Config tema · Config impresión · Config celular · Atajos.
Datos: productos (25 + "Varios"), proveedores (7), ventas del día (5), movimientos (6), días cerrados (6), encargues (3), deudas (2). Cifras ancla: venta inicial 2×Cerveza $ 2.100 + 250 g Jamón ($ 14.600/kg) + 3×Pan $ 2.800 = $ 16.250 → efectivo redondea a **$ 16.300**; día $ 482.300 / ganancia $ 168.900 / 61 tickets / falta separar $ 295.000; cierre esperado cajón $ 253.000, MP $ 481.300, lata $ 58.400.

## Apéndice B — Correspondencia de clases del mock con piezas del kit
`btn`→Boton · `chip`→ChipPlz · `seg`→Segmento · `tag`→Etiqueta · `card/hero`→Tarjeta/TarjetaHero · `list/kv`→ListaAgrupada/FilaClaveValor · `scrl`→ContenedorScroll · `field`→CampoPlz · `tg`→FilaInterruptor · `note`→Nota · `rowb`→FilaMaestro · `tile`→TileProducto · `cl`→LineaCarrito · `stp`→Stepper · `bar`→BarraProgreso · `ticket`→TicketPlz · `empty`→EstadoVacio · `.page/.phead/.pbody`→PaginaGestion · `.rv`→Reveal · `data-count`→CifraQueCuenta · `canvas.particles`→CampoParticulas (celebraciones) · `.mega`→MegaMenu · `.nav`→NavPastilla · `.modal`→Modal · `.toast`→Toast · `.popn`→PopoverNotificaciones · `.cp`→Asistente · `.aibtn`→BotonAsistente · `.aistrip`→TiraIA · `.aitag`→EtiquetaIA · `.btn.ai`→BotonIA.

---

## 15. Rapidez inmediata, fricción cero, IA a mano y densidad (ronda 3)

### 15.1 Rapidez y fricción — reglas y lo que cambió
Regla: **lo frecuente se hace sin mouse, en la menor cantidad de pasos, y lo que el sistema ya sabe viene cargado.** Medido en el mock (flujos probados):

| Tarea | Antes (v3 sobria) | Ahora |
|---|---|---|
| Cobrar una venta en efectivo "justo" | elegir medio, `Enter`, `Enter`, cerrar el aviso | `Enter`, `Enter` (**Efectivo ya viene elegido**) y la siguiente venta arranca sola |
| Pasar a la venta siguiente | tocar "Nueva venta" | **automático** a los 2,4 s o con cualquier tecla |
| **Pagar a un proveedor** | abrir Proveedores, elegirlo, "Pagar", llenar monto y origen, confirmar | **`Alt+P`, 3–4 letras, `Enter`, `Enter`** (monto = deuda total ya cargado, origen = el último usado) desde cualquier pantalla |
| Pagar desde Separaciones | ir a Proveedores | botón **Pagar** en la misma fila |
| Quitar una línea / cancelar la venta / registrar un pago por error | confirmación o no se podía revertir | **sin confirmar, con "Deshacer"** (5 s) |
| Ir a otra sección | mouse | `Alt+1…6` (y `Alt+P`, `Ctrl+K`) |
| Buscar un producto fuera de Venta | lupa | `Ctrl+F`/`Ctrl+K`: escribir y `Enter` lo agrega a la venta |
| Agregar lo que suele llevarse con lo que ya está | buscarlo | **un toque** en la tira de IA del ticket |

Principios que se derivan (aplicar también a lo no listado): precargar con lo último usado (origen del pago, categoría, fechas); autofoco en el primer campo de cada diálogo; **`Enter` confirma, `Esc` cancela** siempre; sin diálogos de "¿estás seguro?" salvo lo irreversible de verdad (restaurar una copia, anular una venta: esos conservan su confirmación y su motivo obligatorio); ningún paso de "elegir tipo" si hay un valor casi siempre correcto; cero esperas decorativas (no hay animaciones que se interpongan, 5.1).

### 15.2 La IA, a la vista (siempre marcada ✦ + etiqueta "IA", siempre "solo sugiere")
| Dónde | Qué |
|---|---|
| **Navbar** | botón **✦ Asistente · Ctrl+K** en todas las pantallas |
| **Asistente (4.5)** | al abrirse ya muestra 5 preguntas sugeridas; escribir cualquier cosa ofrece "✦ Preguntar" |
| **Venta** | tira de sugerencia en el ticket: "Con Cerveza suelen llevar Marlboro" + **+ Agregar** |
| **Inicio** | fila de 3 tarjetas de IA con acción (pedir, promo, cobro sin venta) |
| **Proveedores** | botones **✦ Leer factura** y **✦ Promos sugeridas** en la barra de acciones; tira de IA sobre la tabla (ganancia baja) |
| **Configuración › Asistente IA** | solo la clave y el modelo; **ya no es el único lugar donde se descubre la IA** |
Contrato de la IA (no negociable): **nunca cambia nada sin confirmación**; muestra de dónde sale lo que dice (datos del negocio); cada acción que ofrece abre el diálogo normal ya cargado (Edición masiva con el %, Pagar con el proveedor, etc.); si no hay clave de Gemini, las tiras no aparecen y el asistente sigue funcionando para buscar y ejecutar acciones.

### 15.3 Mucha información, bien a la vista
- Escala tipográfica corta (3.2): **un** tamaño de cifra por nivel de importancia (hero 60–68, indicador 34–44, fila 15,5–19), **un** peso para etiquetas (600) y texto de apoyo siempre en `mute`.
- **Columnas alineadas y cifras tabulares**: importes a la derecha, texto a la izquierda, estados como etiquetas de ancho propio; encabezados de tabla fijos (13/600 `soft`).
- **Color solo para estado** (verde ganancia/OK, rojo deuda/falta, ámbar aviso, azul IA/selección): nunca decorativo; el azul de **acción** es solo Cobrar/Venta y el de **IA** es `blue-l` + texto azul.
- **Jerarquía por tamaño y bloque, no por adornos**: un hero oscuro por pantalla (lo más importante), tarjetas grises para el resto, listas agrupadas con separadores de 1 px; densidad de fila 52–62 px.
- Ejemplos de densidad en el mock: Inicio muestra ~40 datos sin scroll; Proveedores muestra 8 columnas por producto (código, costo, precio, ganancia, vendido en 30 días, stock y días que alcanza); Separaciones muestra por proveedor pedido, entrega, % del total, deuda, caja e importe.
- Si una pantalla se sobrecarga, **se parte por pestañas o interruptor** (como Hoy / Este mes), nunca bajando el tamaño de letra por debajo de 13 px ni agregando scroll de página.
