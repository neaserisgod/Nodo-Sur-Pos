# Especificación PC v4 — delta sobre la v3

**Qué es:** la v3 sobria ([`ESPECIFICACION-PC-V3.md`](./ESPECIFICACION-PC-V3.md)) con **menos redundancias, todo simétrico y los avisos arriba**.
**Regla de lectura:** se aplica la v3 y encima esto. **Si algo choca, gana la v4.** Lo que acá no se menciona queda igual que en la v3.
**Mock vivo:** https://claude.ai/artifact/XumwdGBG2BR9FcbLShoSqh · archivo `docs/mock-pc/NodoSurPC-v4.html`.
La v3 sigue publicada como base (https://claude.ai/artifact/Kq4qCixuDtGpRKS1sjKxxj) por si el dueño prefiere volver.

> Estado: **solo mock y documento**. No se tocó código de Flutter. Cada función nueva o movida está marcada "a confirmar" en 6.

---

## 1. Redundancias eliminadas (una sola forma de hacer cada cosa)

| Antes (v3) | Ahora (v4) | Dónde queda lo que se sacó |
|---|---|---|
| Gasto, Ingreso, Retirar y Pagar proveedor como botones sueltos en Venta | Solo **Pagar proveedor** (Alt+P) visible en Venta | Gasto/Ingreso/Retirar en el menú **Caja ▾**; teclas `-`, Alt+G, Alt+I siguen |
| Chip "Gasto/Ingreso" en la fila de categorías de Venta | Solo el chip **Varios · Alt+V** | Menú Caja ▾ |
| Título "Vender" + subtítulo sobre el buscador | Nada: el buscador va arriba de todo | — |
| Hint "Ctrl+F" dentro del buscador | Se quita (el foco ya está ahí) | Ctrl+F sigue andando |
| Botón "Ver abiertas" + diálogo de ventas abiertas | Cada pestaña **Venta N** tiene su ✕ (descartar con Deshacer) | Las pestañas ya las listan |
| Total repetido en los diálogos de cobro (ya está enorme en el panel) | Los diálogos muestran solo lo nuevo (vuelto, redondeo, recargo) | — |
| "Cancelar" / "Cambiar medio" en cada diálogo de cobro | Solo el botón principal; **✕, Esc y clic afuera** cierran | — |
| "Siguiente venta" en la venta cobrada | Se cierra sola a los 2,4 s o con cualquier tecla; queda **Imprimir ticket** | — |
| "Nueva venta" en Inicio | Se saca | Venta está en la navbar y es la pantalla de arranque |
| Fila de 3 tarjetas de IA en Inicio | Se saca | IA a mano en el **Asistente** (Ctrl+K), tiras de IA dentro de Venta/Proveedores y la campanita |
| Ganancia de hoy dos veces en Inicio (héroe y tarjeta) | Solo en el héroe | — |
| "Fijos pendientes de pago" como tarjeta aparte | Etiqueta "Faltan $ …" en el panel **Fijos del mes** | — |
| "Leer factura" arriba y también en la ficha del proveedor | Solo arriba (botón de IA de la pantalla) | — |
| Eyebrows / subtítulos sobre los títulos (Inicio, Cierre, Config…) | Se sacan en todas las pantallas | — |
| "Falta separar" dentro de las notificaciones | Se saca (ya está en Inicio y en Separaciones) | — |
| Caja abierta/cerrada en la barra de la ventana | Pasa al botón **Caja ▾** de la navbar | — |
| Historial: chips Hoy / Ayer / Últimos 7 días / Este mes | Solo **Hoy / Ayer** + buscador | Días anteriores: Cierres y Detalle del día |
| Asistente vacío con grupo "Ir a" | Solo preguntas sugeridas y acciones frecuentes | Navegar sigue con la navbar y Alt+1…6 |
| Mega-menú en casi todas las secciones | Mega-menú solo en **Proveedores** y **Historial** | — |

## 2. Navbar simétrica de tres zonas

Grilla `1fr auto 1fr` (la zona del medio queda siempre en el centro de la ventana, sin importar cuánto ocupen los lados).

- **Izquierda:** botón **Caja ▾** (pastilla con punto verde `● Caja · Ana`, o `Caja cerrada`). Abre el menú de caja.
- **Centro:** pastilla flotante con Venta (azul, destacada), Inicio, Proveedores ▾, Separaciones, Historial ▾, Encargues.
- **Derecha:** Asistente (Ctrl+K), campanita con contador, tuerca de Configuración.
- **Barra de la ventana (40 px):** logo + nombre del local a la izquierda, "Copia de hoy 8:00 ✓" al centro, minimizar/maximizar/cerrar a la derecha. Misma grilla de tres zonas.
- **Cierre de caja** ya no es un botón de la navbar: se llega desde Caja ▾ → Cerrar caja (o Ctrl+K).

### Menú Caja ▾ (popover anclado al botón, 380 px, radio 32)
Cabecera de estado: `● Caja abierta · Ana · desde 8:02` (o `Caja cerrada`).
Ítems: **Hacer arqueo** (etiqueta "pendiente" cuando toca) · **Cambiar de turno** · **Gasto** (`-`) · **Ingreso** (Alt+I) · **Retirar ganancia** · separador · **Cerrar caja** (rojo).
Con la caja cerrada, el único ítem es **Abrir caja**. Cierra con Esc, clic afuera o al elegir.

## 3. Avisos (toast) arriba

- Posición: **centrado, `top: 58px`** (justo sobre la pastilla de navegación, debajo de la barra de la ventana). Antes iba abajo.
- Entra **deslizando hacia abajo** 26 px con fade (≈ .4 s, `cubic-bezier(.2,.7,.1,1)`); sale subiendo.
- Duración: 2,6 s; **5 s si trae Deshacer**. Un aviso nuevo reemplaza al anterior.
- Pastilla oscura de 60 px de alto, ícono ✓, texto, y botón **Deshacer** a la derecha cuando la acción es reversible (pagar proveedor, descartar venta, etc.).
- No bloquea: no tapa los botones de cobro ni el buscador; el clic atraviesa todo salvo el botón Deshacer.

## 4. Reglas de simetría

1. **Columnas iguales.** Inicio-Hoy: 3 × `1fr` arriba y 3 × `1fr` abajo. Inicio-Mes: 3 tarjetas iguales y 3 paneles iguales. Ficha de proveedor: héroe y datos en mitades iguales. Detalle del día: 4 tarjetas iguales. Encargues: Apartados y Deudas `1fr 1fr`.
2. **Márgenes laterales iguales:** 56 px a cada lado, `100px 56px 26px 56px` (arriba/abajo según la barra y la navbar).
3. **Separación única** entre bloques: 14 px.
4. **Sin cabeceras pesadas:** título a la izquierda y acciones a la derecha, nada más.
5. **Asimetrías que quedan por necesidad:** en **Venta**, la grilla de productos (ancha) contra el ticket (alto, a la derecha) y en las pantallas lista/detalle (Proveedores, Historial). Ahí el orden es siempre el mismo: lista a la izquierda, detalle a la derecha.

## 5. Cambios por pantalla (resumen)

- **Venta:** buscador gigante + **Pagar proveedor** arriba; categorías en una sola fila con **Varios** al final; pestañas de ventas con ✕; diálogos de cobro sin total ni "Cancelar".
- **Inicio:** saludo + selector Hoy / Este mes. Hoy: héroe de ventas, 4 cifras (Tickets, Ticket promedio, Unidades vendidas, Falta separar), Más vendidos; abajo Ventas por hora, Stock bajo, Encargues y deudas. Mes: Ganancia bruta, Fijos cubiertos, Venta diaria de equilibrio; abajo Estado de resultados, Margen necesario, Fijos del mes.
- **Proveedores / Historial:** sin subtítulo; Historial con chips Hoy/Ayer.
- **Cierre / Configuración:** sin eyebrow.
- **Asistente (Ctrl+K):** vacío muestra preguntas a la IA y acciones frecuentes; sin grupo "Ir a".

## 6. Funciones nuevas o movidas — a confirmar con el dueño

1. Menú **Caja ▾** como único lugar de Gasto, Ingreso, Retirar, Arqueo, Turno y Cierre (en el código actual son botones sueltos).
2. ✕ en cada pestaña de venta (descartar con Deshacer) en lugar de la lista de ventas abiertas.
3. Venta cobrada sin botón de "siguiente": se cierra sola.
4. Diálogos sin "Cancelar": se cierra con ✕/Esc/clic afuera.
5. Aviso arriba en toda la app (hoy abajo).

## 7. Qué se probó y qué no

**Probado (Chromium, 1920×1080, claro y oscuro):** los 43 estados del selector sin errores de consola; ninguna pantalla fija se desborda (verificación de alto/ancho por script); cobro efectivo / QR / débito / mixto con recargo de cigarrillos; Alt+P → pagar proveedor → Deshacer; venta cobrada que se cierra sola; Alt+1…6; aviso arriba y menú Caja ▾.
**No probado:** en Windows real, a 1366×768, con la fuente estática de la app (el mock usa Figtree variable; ver excepción E-1 de la v3), ni con impresora/terminal.
