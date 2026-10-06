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

---

## 8. Ronda 5 (06/10/2026): funciones de la app real que faltaban en el mock — ya agregadas

Pedido del dueño: *"lo que sí está [en la app real], implementalo; lo que no está [en la real, pero sí en el mock], que se quede igual porque son funciones útiles"*.
Se agregó **todo lo de la auditoría (`AUDITORIA-MOCK-V4.md`, sección 2)** al mock y **no se sacó nada** de lo inventado (sección 3 de la auditoría: Rubro/Logo, Sucursal/Miembros, WhatsApp, "Excluir de la reposición", Seña, comparar costos entre proveedores, Caja ▾, Alt+P, asistente).

| Zona | Agregado (comportamiento) |
|---|---|
| **Venta / caja** | Diálogo **Imprimir ticket** (terminal Point · PDF en la carpeta · impresora del mostrador), también desde Reimprimir. **Abrir caja** pide *quién abre* (usuarios cargados + "Agregar otra persona"). **Caja de ayer sin cerrar**: punto ámbar y texto en el botón Caja ▾, aviso en la barra de la ventana y en el menú (lleva a Cierre). La **X de la ventana** pregunta *¿Cerrar La Plazoleta?* (Ir a cerrar la caja / Seguir trabajando / Cerrar igual) si la caja está abierta. **Reabrir caja** (confirmación) en el paso "Caja cerrada". Gasto rápido con motivos Flete, Limpieza, Bolsas, Impuestos, Otro. Diálogo **Datos de tu comercio** (nombre + encabezado, "Más tarde"). |
| **Proveedores** | Entradas **Todos los productos** y **Sin proveedor** en la lista. Cifras **Vendido · Ganancia · Stock a costo · Stock a precio · Separado · Le debés** con período **Hoy / Semana / Mes / Desde el último pago**. Tabla con **casillas** (selección masiva) y filtro **Todos (n) / Stock bajo (n)**; "Editar N seleccionados" aparece al marcar. **Edición masiva completa**: precio o costo × (sumar/restar % o monto, valor nuevo), categoría, proveedor, activar/desactivar; avisos (deja en $0, más del doble) y paso de confirmación; aplica de verdad sobre la lista. **Cuenta corriente**: Cargar deuda, Pagar, Anular pago/deuda (con aviso de caja abierta). **Ver lata** (proveedor de caja aparte). **Avanzado**: caja aparte, excluir, **Activo** y **Ganancia sobre el precio → Aplicar a los precios** con vista previa. **Promos**: lista con Editar/Activar/Desactivar, formulario Nueva/Editar con tope y avisos, sugeridas por IA que abren el formulario. **Comparar con los súper** (tu precio contra los de SEPA y Todo a tu Casa, "Actualizar ahora"; *se conserva además "Comparar costos" entre proveedores*). **Editar producto** completo: proveedor, categoría (+ Nueva categoría), cigarrillo atado/suelto, precio fijo vs automático, stock mínimo, motivo del ajuste de stock, pesable, activo, historial. Conteo: **Bajar planilla**. |
| **Separaciones** | Período **Hoy / Semana / Mes**. Retirar ganancia con el aviso **"Estás retirando más de lo que el negocio ganó… Retirar igual"**. |
| **Historial** | Períodos **Hoy / Ayer / Este mes**; filtro por medio en Ventas (Todos/Efectivo/QR/Débito/Crédito/Mixto) y por tipo en Movimientos (Todos/Gasto/Ingreso/Pago a proveedor/Retiro). Anular una venta cobrada con la terminal ofrece **devolver por Mercado Pago**. Detalle del día con **Ocultar/Ver** el vendido por proveedor y etiqueta **Editada**. **Editor de venta**: renglón libre, parte en efectivo del mixto, "Qué se va a ajustar" (stock / a separar / ganancia), aviso de diferencia, **motivo obligatorio al guardar**, Anular desde el editor. **Carga histórica**: calendario del mes (cargado / falta cargar / ya tiene caja), hora, **varias ventas por día** ("Agregar venta" → "Guardar día (n)"). |
| **Cierre de caja** | Paso 1: lista de **arqueos del turno**. Paso 2 (con scroll interno, sin scroll de página): **Nota**, **Vendido sin costo**, Mercado Pago **por canal** (QR/débito/crédito) con devoluciones y comisiones, **Cargar como gasto/ingreso por MP** para la diferencia, **A separar por proveedor** y ganancia sin revisar. |
| **Inicio · Este mes** | **Corregir monto** / Cargar monto de un fijo (diálogo propio), resumen **Presupuestado / Pagado / Pendiente**, **Cambiar sueldo del dueño**. |
| **Configuración** | Usuarios **Activar/Desactivar**. Respaldo: **Copias a conservar (7/14/30)**, **Elegir carpeta**, **Importar una base** (.sqlite/.gz). Cuenta: **Guardar una copia ahora**, **Copias en tu cuenta + Restaurar**, **Volver a bajar todo**, Desvincular. Impresión: **estado de Mercado Pago** (conectado/terminal), **Access Token**, **Terminal que imprime / cobra**, imprimir en la terminal al cobrar, **Reimprimir una venta por N°**. Celular: **QR para instalar la app**, IP de la PC, **Desconectar los celulares**. IA: **Quitar clave** y aviso de privacidad. |

**Todavía sin llevar al mock (prioridad C de la auditoría):** modelo de la IA en Configuración, algunos textos de error de red, y el detalle de cómo el cierre trata las ventas abiertas al reabrir. No cambian la forma de ninguna pantalla.


## 9. Ajustes por las decisiones del dueño (06/10/2026)
- **Sacado del mock:** "Rubro" en Configuración › Comercio y "Excluir de la reposición" en Proveedor › Avanzado.
- **Venta cobrada:** en la app real **no se cierra sola ni se imprime sola**: el acuse queda en el panel del carrito con "Imprimir ticket". El modal de "Venta cobrada" del mock queda solo como referencia visual.
- **Seña de encargues:** entra en la caja con la que se pagó; es ingreso de caja (no venta) y, al pagar completo, pasa a venta del día en que se completó; si se cancela, se devuelve. **Asistente Ctrl+K:** buscador de acciones, sin pregunta libre a la IA. **Logo del ticket:** sí. **WhatsApp del proveedor:** número + botón para mandar el pedido. **Sucursal y Miembros:** se muestran (informativos).
Detalle y orden de implementación en `docs/PLAN-APLICAR-V4.md`.
