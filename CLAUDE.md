# Nodo Sur POS (La Plazoleta) — guía corta para Claude

App de caja y gestión en **Flutter** (PC Windows, celular Android en `lib/companion/`, web en `lib/main_web.dart`) para
comercios chicos; nació para un almacén de Bariloche. Repos hermanos: `NodoSurPage` (sitio y nube) y `botdemo` (bot).

Este archivo se carga en **cada** turno: es corto a propósito. Lo largo vive aparte y se lee **solo la sección que toca**.

## Leer bajo demanda (nunca entero)

Los documentos son grandes (DECISIONES ~200 KB, DISEÑO ~70 KB, TRAMPAS ~50 KB, REGLAS ~45 KB, ESTADO ~45 KB).
Buscar el título con `grep -n '^## ' ARCHIVO.md` y leer solo esa sección con `sed -n 'desde,hastap'`.

| Para... | Ir a |
|---|---|
| Retomar desde cero: qué es el sistema, cómo trabaja el dueño, cómo se publica | `CONTEXTO.md` |
| Qué está hecho HOY y qué falta | `ESTADO.md` (lo último está arriba) |
| Reglas del negocio (si el código las contradice, el código está mal) | `REGLAS-NEGOCIO.md` |
| Por qué algo se hizo así | `DECISIONES.md` (tiene "Índice por tema" arriba) |
| Bugs que ya mordieron | `TRAMPAS.md` |
| Diseño visual (tokens, escalas) | `DISENO.md` |
| Pantalla de venta (especificación completa, atajos), hardware, fases, repo de referencia, qué es configurable | `docs/CLAUDE-DETALLE.md` |
| Historia vieja | `docs/archivo/` — no se lee para trabajar |

Si dos documentos se contradicen, vale lo más reciente (fecha escrita, o la del commit) y lo viejo se corrige en el
mismo cambio.

## Cómo se trabaja

0. **Claude es asesor, no alguien que le da la razón al dueño**: si algo que pide parece mal (código o negocio), se
   frena y se discute **antes**; con **"hacelo igual"** se hace sin discutir. Detalle en `CONTEXTO.md` §2.
1. Leer la regla de `REGLAS-NEGOCIO.md` que toca antes de escribir código de dominio. Si falta un dato, se pregunta.
2. Plan antes de código en una pantalla o módulo grande; las ambigüedades de negocio se marcan y se preguntan.
3. Tests primero en `domain/`.
4. Lo técnico (nombres, estructura, patrón) se decide sin preguntar; lo de negocio se pregunta.
5. Rama por tarea, PR. **Merge libre si CI pasa y el título no empieza con `release:`/`beta:`; publicar solo con
   "lanzá".** Detalle en `CONTEXTO.md` §2 y §5.
6. **Operar rápido le gana a arrancar rápido**: todo lo que la venta necesita se precarga en memoria; nada de disco durante la venta.

## Comandos

```bash
flutter analyze                                        # tiene que dar "No issues found!"
dart run tool/tests_afectados.dart --correr -- --reporter failures-only   # SOLO los tests afectados (sigue los imports)
dart run build_runner build                            # después de tocar lib/data/tables/* o database.dart
```

**No correr la suite entera** (5 a 12 min): la corre CI al mezclar a `main`. En un PR, CI corre solo los afectados.
En la nube, Flutter lo instala `.claude/hooks/session-start.sh` (la versión sale de `tests.yml`). No leer `*.g.dart` ni `build/`.

## Arquitectura

```
lib/domain/     funciones puras: sin Flutter, sin base, sin I/O. La capa con tests exhaustivos.
lib/data/       esquema drift con migraciones versionadas (nunca un parche manual), repositorios.
lib/ui/         pantallas de la PC.        lib/companion/  la app del celular.
lib/servicios/  nube, sync, Mercado Pago, IA, actualizaciones.   lib/servidor/  API HTTP de la PC para el celular.
```

Sin gestor de estado ceremonioso (`provider`/`setState`). Listas largas con `ListView.builder`.

## Convenciones que no se rompen

1. **Todos los montos son `int` en centavos.** Nunca `double` para plata.
2. **La línea de venta guarda precio y costo del momento** (costo-foto), no una referencia al producto.
3. **Cada fórmula vive en un solo lugar.** Si un cálculo aparece en dos archivos, está mal.
4. **El subtotal de pesables pasa siempre por su helper.** Nunca precio por kilo × cantidad a mano.
5. Redondeo hacia arriba al peso entero en todo precio o costo calculado.
6. Todo movimiento de stock deja rastro.
7. Comentarios que expliquen **por qué**, no qué.
8. **Total de una venta: recargo de cigarrillos primero, redondeo después**, sobre el total que ya incluye el recargo.

## Pantalla de venta — la regla dura

Búsqueda, total y los cuatro medios de pago **siempre visibles sin scrollear**; solo el carrito scrollea. Los avisos
salen arriba (`mostrarAviso`), nunca tapando el cobro. Todo lo demás (atajos Alt+, campo único, notificaciones,
carrito, cobro) está en `docs/CLAUDE-DETALLE.md`, "Pantalla de venta": leerlo antes de tocar `lib/ui/venta/`.
