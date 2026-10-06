# Plan para aplicar el diseño v4 al código de Flutter

**Fecha:** 06/10/2026 · **Estado:** etapa 1 hecha a medias (avisos arriba, "Caja ▾" en toda la app, navbar y barra de ventana en tres zonas; falta la campanita en todas las pantallas) · Pedido del dueño: "empezá a aplicarlo al código de Flutter".
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
| 7 | **Configuración** | Orden y contenido de las 16 secciones del mock. | Bajo |
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
