# Estándares de diseño y funcionamiento (2026-10-03)

Pedido del dueño: *"la app debe ser en esencia como si la hubiese creado Google bajo sus estándares de diseño y funcionamiento"*,
con la estética de **horsepos.com** y **antigravity.google**. Este documento fija qué significa eso, medido contra el código de hoy.
`DISENO.md` sigue siendo el dueño de los tokens; acá se agrega lo que falta. **Nada de esto está hecho todavía.**

## 1. Estética: lo que ya está y lo que sobra

Ya está (la base de la PC ya es horsepos): fondo blanco, bloques `#F3F4F7` sin sombra, tinta `#121317` como único acento,
botones en píldora, Figtree, títulos grandes y livianos, `Modal` de radio 40.

Se corrige para ser un solo lenguaje:
- **Un solo sistema de diseño.** Hoy hay dos: `lib/ui/tema/*` (PC) y `lib/companion/tema/*` (celular: `presionable`, `superficie`,
  `chip_icono`, `esqueleto_companion`, `piezas_companion`, `hoja_vidrio`, `tarjeta_accion`, `campo_particulas`, `resplandor`).
  Pasa todo a `lib/ui/tema/` y el celular lo importa. Una pieza, un lugar (Regla 3 del proyecto, aplicada a UI).
- **Un solo acento.** Hoy hay además ámbar (efectivo), azul (QR), verde-azulado (débito), violeta (mixto) y un degradé azul noche en
  las piezas destacadas. Propuesta: la pieza destacada es un bloque de **tinta sólida** (sin degradé); el medio de pago se distingue
  con un **punto de color chico + texto**, nunca con rellenos de color; el color fuera de la tinta queda solo para estados
  (ganancia = verde, atención = ámbar, error = rojo).
- **Cero colores sueltos.** 78 `Color(0xFF…)` en la PC y 86 en el celular fuera del tema (verde `0xFF1B873F`, blancos del hero,
  rojo del botón cerrar). Todo pasa a tokens.
- **Tema oscuro:** negro puro `#000` de fondo; `CLAUDE.md` pide no usar blanco puro sobre negro puro. Bajar a `#0E0F12`.
  El tema automático por horario (oscuro antes de las 10 y después de las 22) se reemplaza por "seguir al sistema".
- **Tokens legados** `ColoresPlazoleta.claro/oscuro` (ámbar) y `Bloque`: borrar.
- Nota de método: leí `antigravity.google` con una herramienta de resumen que devolvió poco (fondo oscuro, titulares grandes,
  botones sólidos, mucho aire). No me alcanza para copiar valores; lo que se toma es el criterio —mucho aire, titulares livianos,
  un solo botón protagonista por pantalla, sin adornos—, y los valores concretos siguen saliendo de `DISENO.md`.

## 2. Estándares Google (Material 3 + accesibilidad) contra el código

| Estándar | Hoy | Meta |
|---|---|---|
| Objetivos táctiles ≥ 48 dp | `−`/`+` del carrito ~28 px, tacho y cerrar pestaña chicos, flechas de reordenar menú 16 px, íconos de "Cambiar de turno"/"Cerrar caja" 36 px | 48 dp en celular y táctil; en mouse ≥ 40 con área de clic de 48 |
| Texto en botones de acción | "Cambiar de turno", "Cerrar caja" y campanita son solo ícono con tooltip | ícono + texto cuando hay ancho |
| Deshacer en vez de preguntar | 0 `SnackBarAction`; quitar línea, cerrar pestaña, Esc (cancela la venta entera) sin confirmar ni deshacer | quitar/cancelar → snackbar "Deshacer" 5 s; confirmar solo lo irreversible |
| Estados de carga | casi todo `SizedBox.shrink()` (pantalla en blanco) aunque existe `EsqueletoLista` | esqueleto en toda carga > 150 ms |
| Estados de error | existe `EstadoError`, casi nadie lo usa; 37 `catch (_) {}` mudos en la PC | error visible con "Reintentar" y registro a archivo |
| Estados vacíos | bien resueltos en varias pantallas | mantener; sumar acción ("Cargar el primero") |
| Idioma del sistema | sin `localizationsDelegates`/`es_AR`: selector de fecha, menús contextuales y "Cut/Copy/Paste" salen en inglés | `flutter_localizations` + `es_AR` |
| Accesibilidad (lector de pantalla) | 6 `Semantics` en toda la PC | `Semantics`/`tooltip` en todo control sin texto; orden de foco lógico |
| Foco y teclado | Venta tiene atajos; el resto de la PC no muestra el foco | anillo de foco visible, Tab/Enter/Esc consistentes en cada modal |
| Contraste (WCAG AA 4.5:1) | medido solo en tokens principales | test automático de contraste sobre cada par de tokens (claro y oscuro) |
| Movimiento con propósito | `disableAnimations` solo en bienvenida | respetar "reducir animaciones" en todo; solo transiciones que orientan |
| Una forma de hacer cada cosa | botones fuera del kit: `AlertDialog`/`ElevatedButton` crudos en imprimir ticket, nuevo encargue (PC y celular), estado bloqueado de Venta, restaurar | todo por `Modal`/`BotonPrimario`/`BotonSecundario` |
| Guardado | Configuración guarda solo con Enter, sin aviso, y descarta montos inválidos en silencio | guardar al salir del campo + "Guardado" + error en el campo |
| Formularios | PC sin aviso de "salir sin guardar" (el celular sí lo tiene) | mismo `confirmarSalirSinGuardar` en ambos |
| Fechas | texto `DD/MM/AAAA` que acepta 31/02 | selector de fecha del sistema |
| Vocabulario | "Anular" (PC) vs "Eliminar" (celular); "Precios" (pestaña) vs "Productos" (título); jerga "fase 12", "colchón", "retener" sin explicación | un glosario único y textos revisados |
| Rendimiento | Separaciones recarga todo cada 15 s; consultas leen todo el historial | índices/consultas acotadas por fecha (ver Plan, Fase 1) |
| Errores y registro | `main.dart` solo `debugPrint`; sin archivo de log en la PC | log a archivo rotado + pantalla "Algo salió mal" con copiar detalle |

## 3. Reglas de pantalla que valen para todo

1. Un solo protagonista por pantalla (un botón primario). El resto en secundario.
2. Título grande y liviano arriba, una línea de ayuda debajo, contenido en bloques.
3. Cada lista: buscar, filtrar, estado vacío, esqueleto, error con reintento.
4. Cada acción destructiva: deshacer si se puede; si no, confirmación que dice qué pasa.
5. Cada monto: `tabular`, alineado a la derecha, `formatearARS`; nunca texto armado a mano.
6. Cada pantalla se prueba en 1366×768, 1920×1080, escala 125 % y 150 % (PC) y en 360 dp de ancho (celular).
