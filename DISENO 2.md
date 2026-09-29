# Sistema de diseño — La Plazoleta

Estética: **Google / Material 3, versión plana y de mostrador.** Fondo celeste
grisáceo, tarjetas blancas, botones y chips en pastilla, azul de acento, y color
solo cuando significa algo (efectivo, Mercado Pago, ganancia, alerta, error).

Este documento reemplaza al anterior. La versión vieja describía dos sistemas a
la vez (el "remake" con vidrio, neón y degradés, y el "Lenguaje de diseño" en
Google) y se contradecía en tipografía, paleta, radios y navegación. Acá hay
**uno solo**.

## Cómo leer esto

- **Fuente de verdad de la estética: los mocks** de `Lenguaje de diseño/`
  (`.dc.html` de escritorio, celular y ventana) y este documento. Los valores de
  abajo salen de medir los mocks.
- **Fuente de verdad ejecutable: el código.** `lib/ui/tema/tokens.dart`
  (espaciado, tipografía, medidas), `colores_escritorio.dart` (paleta),
  `acentos.dart` (colores con significado), `tema.dart` (`ThemeData`),
  `superficie.dart` (`Superficie`) y `lib/ui/comun/tarjetas.dart` (el kit).
  Si el código y este documento difieren en un número, gana el código, y el
  documento se corrige en el mismo cambio.
- Qué pantalla ya está migrada: `ESTADO.md`. Ese dato no se duplica acá.
- **Regla para pantallas nuevas:** primero mirar un mock parecido y copiar su
  estructura. Si no hay mock, armar la pantalla solo con piezas del kit
  (sección "Kit") y valores de las escalas de abajo. Un valor que no sale de una
  escala está mal, aunque "quede bien".

---

## 1. Principios

### 1.1 Evitar fatiga visual

Bruno mira esta pantalla doce horas por día, seis días por semana. Cuando dos
criterios chocan, gana el que cansa menos la vista.

1. **Ninguna línea de texto cruza la pantalla entera.** Toda fila, formulario o
   tabla tiene ancho máximo (`Medidas.anchoMaximoContenido`, 760). "Plata a la
   derecha, tabular" vale contra el borde del contenido acotado, no de la pantalla.
2. **La escala tipográfica sube entera y proporcional.** Nunca un tamaño suelto
   para arreglar una pantalla puntual.
3. **Aire, no densidad.** A 1080 de alto sobra espacio; apretar sin necesidad cansa.
4. **Nada se mueve sin que Bruno lo haya pedido.** Ningún parpadeo, nada que
   cambie solo mientras cobra.
5. **La misma cosa en el mismo lugar en todas las pantallas** (título, lista,
   valor, botón de acción).
6. **Lo que ya está bien no se toca.** El contraste está medido: nunca negro puro
   sobre blanco puro para texto de lectura (texto `#1F1F1F`, no `#000000`).

Tema automático: claro de 10 a 22 (horario del local), oscuro fuera de ese
rango (`oscuroPorHorarioDelLocal`). Prendido por defecto; el switch manual de
Configuración lo apaga.

### 1.2 Tres niveles de información

Si al abrir una pantalla hay que leer para encontrar lo que importa, está mal.

1. **Al entrar a una sección: solo el resumen.** Una línea por elemento.
2. **Al entrar a un elemento: el detalle** que se consulta o edita seguido.
3. **Detrás de un botón "Avanzado": el resto** (lo que se toca una vez por año).
   Mismo lugar en todas las pantallas: un botón al pie del nivel 2 que abre un
   diálogo simple con un "Guardar". Nunca una pestaña ni un menú aparte.

Ejemplo aplicado, Proveedores: la lista es solo nombre (proveedores sin venta al
final, en texto tenue); el panel derecho tiene un resumen de cinco cifras (Stock,
Costo, Venta, Ganancia, Separado) y abajo la tabla de productos (nombre, costo,
venta, margen %); todo lo editable y las acciones de separar y pagar viven en
"Avanzado". Productos sigue el mismo esquema.

### 1.3 Una sola pieza destacada por pantalla

La cifra o acción que más importa (el total de la venta, el "a separar") va en
tarjeta oscura `#1F1F1F`. Si todo destaca, nada señala nada.

---

## 2. Estética en ocho reglas

1. **Plano.** Sin sombra, sin borde y sin brillo en las tarjetas. La jerarquía
   sale de la diferencia de color entre canvas (`#F0F4F9`) y tarjeta (`#FFFFFF`).
2. **Pastillas.** Botones, chips, campos de búsqueda y segmentos: radio pastilla.
3. **Tarjetas redondeadas** con las escalas de la sección 3.3.
4. **Color con significado, nunca decorativo.** Ver sección 3.2.
5. **Solo flotan las capas.** Menú, diálogo y hoja inferior llevan sombra suave y
   fondo opaco. Sin blur, sin vidrio.
6. **Sin degradés, sin resplandor, sin neón.** Ni en piezas "hero".
7. **Íconos de trazo**, 2 px, extremos redondos, 24 px (20 en filas). Nunca
   emoji. Los estados vacíos llevan el ícono dentro de un círculo con tinte.
8. **Tabulares.** Toda cifra con `font-variant-numeric: tabular-nums`
   (`FontFeature.tabularFigures`), plata a la derecha con ancho fijo.

---

## 3. Tokens

### 3.1 Tipografía

Familia: **Figtree**, empaquetada. Pesos: **400** (lectura), **600** (énfasis
suave: nombres, botones secundarios), **700** (títulos, cifras, botones
primarios). No se usa 500 ni 800 en la app. (800 aparece solo en piezas de
marketing como la landing.) Nunca sintetizar un peso que no esté empaquetado.

| Token | px | Rol |
|---|---|---|
| `pequeno` | 12 | Leyendas, insignias, etiquetas de barra inferior |
| `etiqueta` | 13 | Aclaraciones, subtítulos de fila, "c/u" |
| `secundario` | 14 | Texto de apoyo |
| `fila` | 15 | Nombre en filas de lista y de tarjeta |
| `cuerpo` | 16 | Texto estándar, etiqueta de botón |
| `subtitulo` | 18 | Título de bloque |
| `titulo` | 22 | Título de diálogo, hoja y barra móvil |
| `encabezado` | 26 | Nombre de pantalla en escritorio (píldora del menú) |
| `grande` | 32 | Cifra de tarjeta |
| `total` | 44 | La cifra grande: total de venta, resumen del día |

Interletrado: `-0.2` en 22–26, `-0.5` en 32, `-1` en 44. Nada en tamaños chicos.

Los mocks tienen valores sueltos que al pasar a código se ajustan al escalón
más cercano: 17 → 16, 19 → 18, 20 y 21 → 22, 24/28/30 → 26 o 32, 34/36 → 32.

### 3.2 Color

**Claro** (valores de los mocks):

| Rol | Valor |
|---|---|
| Canvas (fondo de pantalla) | `#F0F4F9` |
| Tarjeta | `#FFFFFF` |
| Superficie alterna (barra inferior, fondo de ítems) | `#F8FAFD` |
| Fila suave / separador interno | `#F0F2F5` |
| Divisor | `#E3E3E3` |
| Borde de control (outlined, volver, campos) | `#C4C7C5` |
| Texto principal | `#1F1F1F` |
| Texto secundario | `#444746` |
| Texto apagado | `#5E5E5E` |
| Texto tenue / placeholder | `#747775` |
| Acento / acción / foco | `#0B57D0` |
| Acento, estado presionado | `#0842A0` |
| Seleccionado (fondo / texto) | `#D3E3FD` / `#041E49` |
| Azul suave (fondo / texto) | `#E8F0FE` / `#0842A0` |

**Colores con significado** (única lista permitida):

| Significado | Fuerte | Fondo suave | Texto sobre suave |
|---|---|---|---|
| Efectivo | `#B45309` | `#FDF3E7` | `#7A3A04` |
| Mercado Pago (QR) | `#0B57D0` | `#E8F0FE` | `#0842A0` |
| Débito | `#00639B` | — | — |
| Ganancia / OK | `#146C2E` | `#E6F4EA` | `#0D652D` |
| Alerta (stock bajo, sobrante) | — | `#FEF1E0` | `#7A3A04` |
| Error / faltante / eliminar | `#B3261E` | `#FCE8E6` | `#8C1D18` |
| Mixto | violeta de `acentos.dart` (sin mock que fije el valor todavía) | | |

`error` es exclusivo de lo que está mal: stock agotado, **diferencia de caja
distinta de cero** (sobrante o faltante; solo el cero va sin color). Nunca
decorativo. Un dato incompleto no es un error: va en texto apagado.

**Sobre tarjeta oscura** (`#1F1F1F`): texto `#FFFFFF`, secundario `#E3E3E3`,
apagado `#C4C7C5`. Efectivo `#F2B872`, Mercado Pago `#8AB4F8`, ganancia
`#6DD58C`. Botón claro sobre oscuro: `#A8C7FA` con texto `#041E49`.

**Oscuro** (derivado con el mismo matiz, sin mock todavía, validar al migrar):
canvas `#131314`, tarjeta `#1E1F20`, texto `#E3E3E3`, secundario `#C4C7C5`,
tenue `#8E918F`, borde `#444746`, acento `#A8C7FA`, seleccionado
`#0842A0` / `#D3E3FD`. La pieza destacada pasa a azul `#0B57D0` con texto blanco.
Los colores con significado usan las variantes de la fila "sobre tarjeta oscura".

### 3.3 Forma

**Radios** (una escala, sin terceros valores):

| Radio | Uso |
|---|---|
| 4 | Barras de progreso, trazos finos |
| 8 | Campos internos, tiles chicos |
| 12 | Marca (`LP`), tiles dentro de una tarjeta, avatares |
| 16 | Bloque suave dentro de una tarjeta, cifra en caja |
| 20 | Tarjeta en celular, menú desplegable, fila destacada |
| 24 | Tarjeta en escritorio |
| 28 | Diálogo, hoja inferior (solo esquinas de arriba), píldora del encabezado |
| pastilla (mitad del alto) | Botones, chips, buscador, segmentos, insignias |

Ajuste de los mocks al pasar a código: 10 → 12, 14 → 16, 18 → 20, 22 → 24,
26 → 28, 30 → 28.

**Espaciado:** 4, 8, 12, 16, 24, 32, 48. Valores sueltos de los mocks se ajustan:
6 → 8, 10 → 8 o 12, 14 → 12 o 16, 18 y 20 → 16 o 24.

- Padding interno de tarjeta: 24 en escritorio, 20 en celular, igual en los cuatro lados.
- Hueco entre tarjetas: 16, igual en horizontal y vertical.
- Margen externo de pantalla: 20 en escritorio, 16 en celular.

**Alturas táctiles:**

| Alto | Uso |
|---|---|
| 44 | Mínimo de cualquier cosa tocable (volver, cerrar, stepper) |
| 36 escritorio / 40 celular | Chips de filtro (en celular el área táctil llega a 44 con el hueco) |
| 48 | Campo, botón secundario |
| 52 | Botón primario, buscador de escritorio, botones de diálogo |
| 56 | Botón de cobro, píldora del encabezado |

**Sombras** (solo capas flotantes; `rgba(15,23,42,…)`):
menú `0 12 32 .16 + 0 2 6 .08`, diálogo `0 16 48 .28`, hoja inferior
`0 -8 32 .25`. Velo detrás de diálogo u hoja: `rgba(31,31,31,.42)`.

**Bordes:** `#C4C7C5` de 1 px en controles (botón outlined, volver, campo) y
en la píldora del encabezado. Divisor `#E3E3E3` o `#F0F2F5` entre filas
dentro de una tarjeta. Nunca un borde para separar dos tarjetas: eso se
resuelve con el hueco de 16.

---

## 4. Kit de componentes

Cada pieza del mock tiene su widget. Pantalla nueva = combinar estos, sin
inventar variantes.

| Componente | Especificación |
|---|---|
| `Superficie` | Tarjeta blanca, radio 24 (20 en celular), plana. Modo `destacada`: `#1F1F1F` con texto blanco |
| Botón primario | Pastilla, alto 52 (56 cobro), azul `#0B57D0`, texto blanco 16/700 |
| Botón efectivo / MP | Igual que primario con `#B45309` / `#0B57D0`. Textos "Cobrar en Efectivo" y "Cobrar con Mercado Pago" |
| Botón tonal | `#D3E3FD` con texto `#041E49` |
| Botón outlined | Blanco, borde `#C4C7C5`, texto azul 15/700 (ej. "Volver", alto 44) |
| Botón de texto destructivo | Sin fondo, texto `#B3261E` |
| `GrupoPildoras` | Selector de 2–5 opciones; seleccionada `#D3E3FD`/`#041E49` 700, resto blanco `#444746` 600 |
| Chip de filtro | Igual que el segmento suelto: alto 36/40, padding 16 |
| `Insignia` | Pastilla 12–13/700, padding 4×10, colores suaves de la tabla de significado |
| `CajaCifra` | Fondo suave del color de significado, radio 16, etiqueta 13/700 y cifra 18–24/700 en una línea (sin partir) |
| Buscador | Pastilla, alto 52, fondo blanco (o `#F0F4F9` dentro de una tarjeta), placeholder `#5E5E5E` 16 |
| `FilaLista` | Alto 60–68, nombre 15/600 + apoyo 13 `#5E5E5E`, plata a la derecha con ancho fijo, divisor `#F0F2F5` |
| Stepper de cantidad | Pastilla `#F0F4F9`, alto 40, botones − / + de 38 de ancho |
| `BarraDividida` | Barra de 10 alto, riel `#E8F0FE`, relleno `#0B57D0` |
| `PuntoColor` | Círculo de 8–26 según contexto, con borde `#C4C7C5` si el color es muy claro |
| `AvatarIniciales` | Círculo 40, fondo suave del color, iniciales 16/700 |
| Estado vacío / error | Ícono en círculo con tinte (tenue al 12 % en vacío, error al 14 %); el error suma botón "Reintentar" |
| Diálogo | Blanco, radio 28, padding 24–32, ancho 480 (chico) o 620 (con campos), título 22/700, cerrar de 44, acciones a la derecha o apiladas de 52 |
| Menú desplegable | Blanco, radio 20, padding 8, ancho 340, ítems 8 de hueco, cabecera "La Plazoleta / Punto de venta" |
| Hoja inferior (celular) | Blanco, radio 28 arriba, asa 36×4 `#C4C7C5`, padding 10/20/22, título 22/700 |

### Marca e ícono

Marca de la app: **P41**. Cuadrado de radio ~22,5 % del lado, azul `#0B57D0`,
"P" en `#A8C7FA` peso 400 y "41" en blanco peso 700 (Figtree). Variantes:
azul (default), claro (`#D3E3FD` con `#0B57D0` / `#041E49`) y oscuro
(`#1F1F1F`). Versión circular para avatares. Fuente: canvas "Icono P41". El
`LP` que aparece en los mocks del encabezado es un marcador de lugar: se
reemplaza por el ícono P41 (40 px en el encabezado de escritorio, 34 en celular,
16 en la pestaña).

---

## 5. Estructura de pantallas

### 5.1 Escritorio

Resolución de diseño **1920×1080**; piso **1366×768** (tiene que verse digno);
960×1080 (mitad de pantalla) no debe romperse. Los mocks están a 1280–1440 de
ancho: en código el layout es fluido con anchos máximos, no fijo. Siempre dos
columnas en el patrón B, sin lógica responsive más allá de compactar.

**Ventana propia** (`window_manager`, barra nativa oculta). Barra de título de
**40 de alto**, mismo color que el canvas (`#F0F4F9`), borde de 1 px `#C4C7C5`
alrededor de la ventana.
- Izquierda: ícono P41 (20), "La Plazoleta" 14/600, insignia "Caja abierta"
  (verde suave) y "Respaldo hoy HH:mm" 12 `#5E5E5E`. Aviso "Caja de ayer sin
  cerrar" en insignia de alerta.
- Todo el espacio libre se arrastra (`DragToMoveArea`); doble clic maximiza.
- Derecha: minimizar, maximizar/restaurar, cerrar. Botones de **46×40**, glifos
  de 10 px con trazo de 1 px `#444746`. Hover: `#DDE3EA` (cerrar: `#C42B1C`
  con glifo blanco). Sin foco: textos `#747775`, glifos `#9AA0A6`, marca `#A8C7FA`.
- Cerrar con la caja abierta: diálogo "¿Cerrar La Plazoleta?" con tres acciones
  apiladas — "Ir a cerrar la caja" (primario), "Seguir trabajando" (tonal),
  "Cerrar igual" (texto destructivo). `setPreventClose(true)` + `onWindowClose`.

**Encabezado de pantalla** (sin barra lateral y sin navbar de vidrio): a la
izquierda una **píldora blanca** de 56 de alto, radio 28, borde 1 px `#C4C7C5`,
con el ícono P41 (40), el nombre de la pantalla en 26/600 y un chevron; al
tocarla abre el menú de secciones. A la derecha, las acciones de la pantalla
(botones pastilla). El nombre de pantalla **es** el botón del menú: no hay un
título grande aparte.

**Patrón A — Formulario.** Una acción, pocos campos. Columna centrada de ancho
máximo 760, una o más `Superficie`. Ej.: apertura de caja, conteo del cierre.

**Patrón B — Panel de datos.** Varias tarjetas que se leen juntas, dos columnas,
hueco 16. Las columnas terminan a alturas parecidas: si una queda mucho más
larga, se mueve una tarjeta entera a la otra (nunca un hueco muerto). Scrollea
la página entera, nunca cada columna por su lado. Izquierda lo que se mira
primero (resultado), derecha el detalle que lo sostiene. Las listas sin cota
adentro siguen siendo `ListView.builder`.

**Patrón lista + detalle** (Proveedores, Productos, Configuración, Historial):
dos `Superficie` separadas por 16 (nunca un divisor vertical). Lista de
**360** de ancho; detalle `Expanded` pero con contenido de ancho máximo 760. El
buscador va arriba dentro de la tarjeta de la lista. Sin selección: estado vacío
centrado.

**Inicio:** fila de 4 indicadores, gráfico por hora y medios, tres tarjetas abajo.
**Separaciones:** tarjetas por caja arriba y grilla de proveedores.
**Cierre de caja:** modal. Mientras se cuenta el efectivo, patrón A (nada más
en pantalla). Confirmado el conteo, pasa a panel: Arqueo a la izquierda,
Cigarrillos y Resumen del día a la derecha.

**Vender.** Excepción de layout, no de estética: la disposición sin scroll es
regla de negocio (mostrador con cliente esperando). Columna de búsqueda con
buscador de 52 + chips de categoría + grilla de productos (tiles de ~92 de alto,
radio 20, nombre 15/600 y precio 18/700), y a la derecha el carrito (tarjeta
blanca de 400–480): líneas, total `total` 44/700 y los dos botones de cobro
apilados de 56. El total y el cobro son la pieza destacada de la pantalla.
Las flechas, Enter y Alt+tecla siguen mandando (ver 6.2).

### 5.2 Celular

Diseño a **390×844**. Todo elemento tocable ≥ 44.

- **Barra superior** (mín. 60): a la izquierda marca P41 de 34 + nombre de la
  pantalla en 22/700 + chevron (abre el menú desplegable), o en pantallas de
  detalle un botón de volver de 44 y el título. Acciones a la derecha.
- **Barra inferior** de 4 destinos: Vender, Caja, Historial, Gestión. Fondo
  `#F8FAFD`, borde superior 1 px `#E3E3E3`. Ítem: indicador pastilla de 60×32
  (`#D3E3FD` si está activo), ícono de 22 y etiqueta 12 (600, activa 700).
- Cuerpo: márgenes de 16, hueco 12, tarjetas de radio 20 y padding 20.
- Confirmaciones, cobro y edición viven en **hojas inferiores**, no en pantallas
  nuevas. Diálogos solo para avisos cortos.
- Mismo kit que escritorio, mismas piezas y mismos colores.

---

## 6. Reglas de comportamiento (siguen vigentes)

### 6.1 Alineación y simetría

- Plata siempre a la derecha, tabular, con ancho fijo (`Medidas.anchoValorLista`,
  110). Etiqueta a la izquierda, valor a la derecha, en toda la app.
- **Baseline**, no centro, cuando una fila mezcla texto chico y una cifra grande.
- Íconos centrados ópticamente con su texto.
- Grupos de botones: mismo ancho, mismo alto, mismo hueco.
- Texto de botón centrado de verdad.
- Prueba para cualquier pantalla nueva: trazar una vertical por el borde derecho
  de una columna; todo lo de esa columna tiene que tocarla.
- Si dos tarjetas van lado a lado, sus contenidos arrancan y terminan a la misma altura.

### 6.2 Foco y teclado en Vender

El campo único de búsqueda tiene foco al arrancar. **Devuelven el foco:**
agregar un producto (tap, Alt+tecla o Enter), elegir medio de pago, cobrar,
volver de una pantalla de gestión, abrir caja. **No lo hacen** los diálogos
secundarios (Mixto, Varios, gasto o ingreso rápido, arqueo intermedio, editar un
acceso directo, imprimir el último ticket).

### 6.3 Búsqueda de venta

Fila de una línea con tres datos en este orden: **nombre · stock · precio**. El
nombre se trunca con elipsis. Stock en unidades ("12 un.") o gramos ("3200 g").
Precio como subtotal en 16/700; una tarifa de referencia ("$8.500/kg") en un
tamaño menor y **en un solo texto**, nunca partida en dos widgets. "Varios" va
con guion en stock y precio. El stock bajo se marca en el carrito, no acá. Sin
texto escrito, accesos directos; escribiendo, las filas o "Sin coincidencias".
Sin alta rápida: los productos nuevos se cargan desde Proveedores.

### 6.4 Acuse de cobro y reimpresión

"Imprimir" solo aparece junto al acuse ("Venta #N cobrada · $X") y se va en
cuanto entra la primera línea de la venta siguiente, sin timer. Para reimprimir un
ticket de un día anterior, el único camino es Historial → detalle de día →
"Imprimir".

### 6.5 Plata sin centavos

`formatearARS` no muestra centavos: `150050` centavos → `"$1.501"` (redondea al
peso más cercano). Es solo la capa de texto; en la base sigue el entero de
centavos. `parsearARS` acepta centavos al cargar a mano.
`formatearParaMercadoPago` es aparte y conserva los centavos.

### 6.6 Movimiento

Las transiciones son cortas y siempre responden a una acción del usuario.
Feedback de presión permitido: escala 0.96 al presionar. Ripple de Material
prendido. Nada decorativo y nada en Vender mientras se cobra.

### 6.7 Simulador de resolución (solo debug)

Chip flotante con 1920×1080, 1366×768 (piso) y 960×1080 (mitad). En release
no se arma nada.

---

## 7. Qué se retira del sistema anterior

Todo esto deja de ser válido; borrar del código a medida que se migra cada pantalla.

| Se retira | Reemplazo |
|---|---|
| Glacial Indifference / Questrial | Figtree |
| Acento verde-azulado `#22D3AA` / `#0E9E7E`, paleta oscura `#0B0E13` | Azul `#0B57D0`, canvas `#F0F4F9` |
| Ámbar como "dinero" (`#FFB020`, `gradienteDinero`) | Efectivo naranja `#B45309`; cifras de dinero en texto principal |
| Degradés (`gradienteAcento`, `Superficie.degrade`) | Tarjeta oscura plana |
| `resplandorNeon` / `Superficie.resplandor` | Nada |
| Vidrio, `BackdropFilter`, navbar superior flotante | Píldora de encabezado + menú desplegable; en modales, fondo opaco |
| Sección activa con tinte y neón | Seleccionado `#D3E3FD` / `#041E49` |
| `Bloque`, `Bento`, `Radios` | `Superficie` y la escala de radios |
| Radios 8/14/18/22 | Escala 4/8/12/16/20/24/28/pastilla |
| "Solo dos pesos (Regular y Medium)", "nunca w700" | 400 / 600 / 700 |
| Excepciones tipográficas y de radio propias de Venta (`TactoVenta`) | La escala general ya alcanza |
| "Bento con carácter" como excepción de Venta | Venta usa el mismo sistema que todo |
| `colores.borde` con un único uso | Borde de control `#C4C7C5` y divisores `#E3E3E3` (sección 3.3) |
| Colores de medio de pago: Efectivo verde, QR violeta, Débito azul, Mixto coral | Efectivo naranja, MP azul (ver 3.2) |
| `colores.acento` como color del medio elegido | Cada medio con su color |
| Ancho de lista maestra 460 | 360 |
| Tabla de `Medidas` de barra lateral | Se borra con `BarraLateral` |

## 8. Pendientes de decisión

- **Mixto:** falta fijar el valor final del violeta (el mock lo trata como
  combinación de efectivo y Mercado Pago). Proponer `#6750A4` sobre `#EADDFF`
  con texto `#21005D`.
- **Tema oscuro:** los valores de 3.2 son derivados; falta un mock para validar.
- **Pesos 800 en cifras hero:** los mocks de landing y de la ventana usan 800 en
  totales; en la app quedan en 700.
- **Vender en 3 columnas:** este documento conserva la regla de disposición sin
  scroll; los mocks nuevos usan 2 columnas (buscador+productos | carrito). Si la
  versión de 3 columnas sigue siendo la deseada, decirlo antes de migrar.
