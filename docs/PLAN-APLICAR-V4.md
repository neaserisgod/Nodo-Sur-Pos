# Plan para aplicar el diseño v4 al código de Flutter

**Fecha:** 06/10/2026 · **Estado (06/10):** etapas 0, 1, 2 (parcial), 3 y 7 hechas y probadas (`flutter analyze` limpio y 1.700+ tests verdes); 4, 5 y 6 casi no necesitan cambios (la app real ya tiene lo del mock); quedan la campanita en todas las pantallas y las decisiones pendientes · Pedido del dueño: "empezá a aplicarlo al código de Flutter".
Reglas que se respetan (`CLAUDE.md`): una etapa por vez y se prueba antes de la siguiente · plan primero y ambigüedades de negocio marcadas, no
resueltas solas · tests primero en `domain/` · una fórmula vive en un solo lugar · montos en centavos enteros · migraciones versionadas si se toca la base.

**Referencia visual y de comportamiento:** `docs/mock-pc/NodoSurPC-v4.html` (vivo: https://claude.ai/artifact/XumwdGBG2BR9FcbLShoSqh) y
`docs/ESPECIFICACION-PC-V4.md`. **Dónde manda el código:** si el mock inventó algo, ver "Decisiones pendientes" abajo.

## Qué ya existe en la app real (no hay que construirlo, solo rediseñarlo)
La auditoría del mock marcó como "falta en el mock" varias cosas que la app real **ya tiene** (caja de ayer sin cerrar, confirmación al cerrar con caja abierta,
reabrir caja, imprimir ticket, quién abre, devolución por Mercado Pago, edición masiva, cuenta corriente, carga histórica, etc.). Entonces el trabajo de
estas etapas es **sobre todo de forma** (disposición, componentes, avisos), no de funciones nuevas.

## Etapas (una por vez, cada una con `flutter analyze` limpio y sus tests)
| # | Etapa | Qué cambia en el código | Riesgo |
|---|---|---|---|
| 0 | **Entorno** | SDK de Flutter 3.47, `flutter pub get`, línea de base de `analyze` y tests. | Ninguno |
| 1 | **Carcasa** | Barra de la ventana en 3 zonas · navbar simétrica en 3 zonas con **Caja ▾** (arqueo, turno, gasto, ingreso, retirar, cerrar) y campanita en todas las pantallas · **avisos arriba** (reemplazo único de los `SnackBar`) · sin título/lupa repetidos. | Medio: toca todas las pantallas |
| 2 | **Venta** (en curso: título, Pagar proveedor, Varios hechos; falta "Venta cobrada" y diálogos sin total/Cancelar, esperan la decisión 7) | Buscador gigante + "Pagar proveedor" · una sola fila de categorías + Varios · pestañas de venta con ✕ · diálogos de cobro sin total repetido ni "Cancelar" · "Venta cobrada" que se cierra sola. | Alto: es el 80 % del uso |
| 3 | **Inicio** (hecha: sin "Nueva venta", columnas iguales; la vista "Este mes" queda para la etapa 3b) | Tres columnas iguales, sin tarjetas de IA ni "Nueva venta", fijos con resumen. | Bajo |
| 4 | **Proveedores** | Ficha en mitades iguales, cifras por período, selección masiva, "Todos / Sin proveedor". | Medio |
| 5 | **Separaciones e Historial** | Períodos Hoy/Semana/Mes y Hoy/Ayer/Este mes, filtros, editor de venta. | Medio |
| 6 | **Cierre de caja** | Paso 2 con scroll interno, arqueos del turno, nota, MP por canal. | Medio |
| 7 | **Configuración** (HECHA: lista plana de 16 secciones) | Orden y contenido de las 16 secciones del mock. | Bajo |
| 8 | **Funciones nuevas del mock** | Asistente (Ctrl+K), Pagar proveedor rápido (Alt+P), ver "Decisiones pendientes". | Alto: negocio |

Después de **cada** etapa: se actualizan `ESTADO.md` y `DISENO.md` en el mismo cambio, y se prueba a mano en Windows (esto último no se puede hacer desde acá).

## Decisiones pendientes (negocio — **no se resuelven solas**)
Cosas que están en el mock pero **no existen en la app real**. Cada una necesita una respuesta del dueño antes de la etapa 8 porque cambia la base o la plata:
1. **Seña en encargues** — ¿en qué caja entra la seña (cajón / Mercado Pago)? ¿Cuenta como venta del día? ¿Qué pasa con la seña si se cancela?
2. **Excluir un proveedor de la reposición** — hoy el "a separar" de cada día es una fórmula única (`domain/reposicion.dart`); excluir un proveedor cambia el total a separar y el cierre.
3. **Rubro y logo del ticket** — el rubro ya existe como plantillas (`plantillas_rubro.dart`); el logo necesita guardarse y entrar al PDF y al ticket de la terminal.
4. **WhatsApp del proveedor** — es un campo nuevo; ¿para qué se usa (abrir chat, mandar el pedido)?
5. **Sucursal y Miembros** — la app no tiene sucursales ni miembros; ¿se saca del mock o es para la cuenta de Nodo Sur?
6. **Asistente con pregunta libre (Ctrl+K)** — hoy la IA solo sugiere promos y lee facturas. ¿Qué puede responder? (necesita definir qué datos ve y que nunca cambie nada sola.)
7. **"Venta cobrada" que se cierra sola** — ¿se imprime el ticket automáticamente? Hoy se imprime con el botón.

## Qué NO se puede probar desde acá
No hay Windows: se prueba `flutter analyze`, los tests y la lógica; **el aspecto en pantalla real, el rendimiento en la PC del local y la terminal Point hay que probarlos a mano** después de cada etapa.


## Estado al 06/10/2026 (lo hecho en el código, probado con `flutter analyze` + tests; **sin probar en Windows real**)
| Etapa | Estado | Notas |
|---|---|---|
| 0 Entorno | ✅ | Flutter 3.47.6 instalado en la sesión de trabajo; línea de base limpia. |
| 1 Carcasa | ✅ completa (la campanita ya está en todas las pantallas; fuera de Venta no ofrece el arqueo) | `mostrarAviso` (arriba, con Deshacer) reemplaza a todos los `SnackBar`; botón **Caja ▾** (Venta y resto de pantallas); navbar y barra de la ventana en tres zonas. |
| 2 Venta | ✅ parcial | Sin título, **Pagar proveedor (Alt+P)** con diálogo rápido (usa `pagarDeuda`, con Deshacer), pastilla **Varios**, buscador grande. **Falta** "Venta cobrada" que se cierra sola y diálogos de cobro sin total repetido ni "Cancelar" → decisión 7. |
| 3 Inicio | ✅ | Sin "Nueva venta", tres columnas iguales arriba y abajo. |
| 4 Proveedores · 5 Separaciones e Historial · 6 Cierre | ➖ ya coincide | Al comparar las capturas reales con el mock se vio que la app ya tiene las cifras por período, la selección masiva, los filtros por medio y el cierre con ✕. Las diferencias que quedan son de detalle visual y solo se pueden juzgar en Windows real. |
| 7 Configuración | ✅ | Lista plana de 16 secciones (grupo arriba, título y descripción a la derecha). |
| 8 Funciones nuevas | ⏸ espera decisiones | Ver abajo. |

**Dos cambios de comportamiento que conviene mirar en Windows:** (1) ninguna pantalla muestra subtítulo (antes "Hoy · martes 6 de octubre" en Inicio, "Las ventas, una por una" en Historial…); (2) en Venta, los íconos "Cambiar de turno" y "Cerrar caja" ya no están: se llega por **Caja ▾**.


## Decisiones del dueño (06/10/2026) — resuelven la sección "Decisiones pendientes"
| # | Tema | Decisión | Qué implica |
|---|---|---|---|
| 1 | "Venta cobrada" y el ticket | **Queda el botón Imprimir** (no se imprime solo). | La "Venta cobrada" que se cierra sola **no se hace**: el acuse sigue en el panel del carrito. El mock v4 difiere en esto y se corrige. |
| 2 | Seña · en qué caja entra | **En la caja con la que pagó** (efectivo → cajón, Mercado Pago → saldo de MP). | Se elige al cargar la seña. |
| 3 | Seña · cómo cuenta | **Ingreso de caja, no venta; cuando se paga completo pasa a ser venta del día en que se completó.** Si se cancela el encargue, la seña se devuelve (por la misma caja). | Hace falta modelo + dominio + tests antes de tocar la pantalla (ver "Plan de la etapa 8"). |
| 4 | Excluir proveedor de la reposición | **No.** | Se saca del mock y de la especificación. |
| 5 | Asistente Ctrl+K | **Buscador de acciones, sin pregunta libre a la IA.** | Sin IA ni internet: salta a pantallas, acciones (pagar proveedor, arqueo…) y productos. |
| 6 | Rubro y logo | **Solo el logo del ticket** (sin "Rubro"). | Imagen guardada en la base; sale en el PDF y en el ticket de la terminal. Se saca "Rubro" del mock. |
| 7 | WhatsApp del proveedor | **Guardar el número + botón para mandarle el pedido.** | Campo nuevo (migración), botón "Pedir por WhatsApp" con el pedido armado. |
| 8 | Sucursal y Miembros | **Mostrarlos** en Configuración › Cuenta de Nodo Sur (solo informativos). | Hay que pedirlos al servidor de Nodo Sur: falta confirmar el endpoint (repo `NodoSurPage`). |

### Plan de la etapa 8 (orden propuesto; cada punto con sus tests y `flutter analyze` limpio)
1. **Asistente Ctrl+K** (sin base ni red): paleta de acciones/pantallas/productos. Reemplaza a la lupa de las otras pantallas (que sigue hasta entonces).
2. **WhatsApp del proveedor**: migración de esquema (campo `whatsapp`), campo en nuevo/editar proveedor, botón "Pedir por WhatsApp".
3. **Logo del ticket**: migración (imagen en configuración del negocio), selector en Configuración › Comercio, uso en el PDF y el ticket de la terminal.
4. **Seña de encargues** (la más delicada, toca plata): primero `domain/` con tests (seña como ingreso de caja por medio; al completar el pago, la venta se registra con la fecha de ese día y se descuenta lo ya cobrado; cancelar devuelve por el mismo medio), después base y pantalla. **Antes de codificar se muestra el plan al dueño.**
5. **Sucursal y Miembros**: solo después de confirmar de dónde salen los datos.
