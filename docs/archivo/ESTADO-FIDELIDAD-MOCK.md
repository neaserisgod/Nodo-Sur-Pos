# Fidelidad 1:1 con el mock v4 de la PC — dónde quedó (2026-10-06)

**Esta rama (y `claude/clever-keller-ial7l6`, de la que sale) es lo más nuevo.** El trabajo es rehacer cada pantalla
**desde cero** igual al mock, con el kit `lib/ui/kit/`. Lo que diga otra documentación sobre "continuar lo de `main`" o
sobre la rama `claude/jolly-dijkstra-8yhofh` quedó viejo: no se sigue.

Material de referencia: el zip `mock-v4-fidelidad-1a1` (mock HTML, 100 capturas, `01-ANIMACIONES.md`,
`02-TOKENS-Y-MEDIDAS.md`, `03-PANTALLAS.md`). Las capturas propias salen de `test/ui/capturas_mock_test.dart`.

## Hecho desde cero (commits de `claude/clever-keller-ial7l6`)

Kit (`lib/ui/kit/`: paleta claro/oscuro, íconos, Figtree variable, piezas, modal, animaciones) · barra con Caja ▾ y
mega-menús · Venta · Inicio (Hoy y Este mes) · Proveedores · Separaciones · Historial (ventas, movimientos, cierres) ·
detalle del día · editor de venta · carga histórica · conteo de stock · Encargues · **Cierre de caja** y
**Configuración** (estas dos en `claude/serene-mendel-rrmwui`, que sale de esta rama).

## Falta (en este orden)

1. ~~Cierre de caja~~ — hecho (ver "Cierre de caja — cómo quedó" abajo).
2. ~~Configuración~~ — hecha (ver "Configuración — cómo quedó" abajo).
3. Comparar precios (`M.comparar`, `M.compararSuper`).
4. Diálogos por familia con `ModalMock` (tabla de `03-PANTALLAS.md`), tema oscuro de todo, pasada de animaciones.
5. Pendiente del commit de Proveedores: el vacío de la tabla desborda en una ventana baja (un test).
6. Actualizar `ESTADO.md` cuando se cierre la tanda.

## Configuración — cómo quedó (2026-10-06)

- Cabecera con el buscador grande "Buscar un ajuste…" (`BuscadorPagina`, key `busqueda_configuracion`) en vez de la
  búsqueda de la barra, como las otras pantallas rehechas: ahí Ctrl+F abre el Asistente. Los tests de la búsqueda de la
  barra pasaron a usar Comparar precios, la única pantalla que todavía la tiene.
- Izquierda 320 con `.cgrp`/`.csec` (columna entera, no `ListView`: son 16 fijas); derecha h2 + lead + contenido ≤ 1000.
- Las 16 secciones con el kit, incluidas las de otros archivos (Cuenta de Nodo Sur, Impresión y posnet, Asistente IA,
  Respaldo). Pieza nueva del kit: `Stp` (`.stp`, la ganancia por categoría). Los campos de plata se guardan con Enter
  o al salir del campo (el mock no tiene "Guardar" en esas secciones). Usuarios y medios se renombran/agregan en un
  `ModalMock`; el producto del vuelto se elige en un modal con buscador.
- **No están, a propósito** (controles sin nada detrás, o que contradicen REGLAS-NEGOCIO): "Redondear el efectivo"
  (siempre redondea), "Día del retiro semanal" (eliminado, §13), roles de usuario, "Imprimir el logo", partículas /
  cursor / desplazamiento suave / Movimiento (la app sigue "reducir animaciones" de Windows), canal Beta/Estable,
  "Copia automática" (siempre al cerrar), "Usar el asistente en Proveedores", y los datos de demostración del mock
  (ganancia fija por atado, celulares conectados, "Mercado Pago: conectado · PAX A910").
- **Pregunta abierta para el dueño — "Reserva diaria de fijos"**: el mock la pone como campo en Caja y redondeo, pero
  `domain/equilibrio.dart` dice que esa columna quedó vestigial (el cierre la calcula de los fijos del mes) y
  Separaciones (rehecha) la lee igual de la columna. Son dos fuentes para el mismo número (Regla 3): hay que decidir
  cuál vale antes de agregar el campo.

## Cierre de caja — cómo quedó (2026-10-06)

Hecho según el plan de abajo, con estas decisiones:

- `abrirCierre(context, builder:)` en `pantalla_cierre.dart` empuja una ruta de pantalla completa con fundido; los 4
  llamadores la usan. `PantallaCierre` ganó `textoVolver` ("Volver a Venta" desde Venta, "Volver" desde otra
  pantalla: el botón sale sin cerrar y vuelve a donde se estaba). Esc también sale (pasos 1 y 2).
- **"Confirmar conteo" pide las tres cajas** (efectivo, Mercado Pago y, con `Modulo.cajaAparte`, la lata), no solo el
  efectivo como el mock: el paso 2 ya no tiene campos y `cerrar()` siempre exigió las tres, así que confirmar sin una
  dejaba un cierre imposible. `CierreControlador.conteoCompleto` lo dice.
- Sin chips de relleno rápido (ni "Cuadra justo" ni montos inventados); queda la precarga del último arqueo.
- Paso 2: además del mock, se conserva "de qué sale" cada esperado (fondo, ventas, gastos, ingresos; saldo al abrir y
  cobros de MP), la nota de separación parcial, los cobros Point sin resolver, los arqueos y "Vendido sin proveedor o
  costo". "N productos" abre `mostrarDialogoSinCosto` (se cargan costos ahí y el paso 2 se recalcula).
  "Separación de cigarrillos" se escribe "A separar a la lata" (bug real: "Separado" leía como ya hecho).
- La tarjeta del mock "QR / Débito / Crédito" no está: `ConciliacionMp` no trae lo cobrado por canal.
- Cerrada: "Vendiste $ X en N tickets y ganaste $ Y" sale de `detalleDelDia` (la misma cuenta que Historial); si hubo
  ventas sin costo, lo aclara. La hora del respaldo solo si se hizo en este cierre (`respaldoHechoA`). Debajo, una
  lista corta con las diferencias y lo separado a la lata. Botones: `textoBotonFinal` (dark) y "Reabrir caja"; no se
  repite un tercer "Volver a Venta" (el principal ya lo es en un cierre normal). Sin partículas.
- Capturas: `cierre-1`, `cierre-2`, `cierre-cerrada` en `test/ui/capturas_mock_test.dart`.

## Cierre de caja — plan relevado (ya aplicado)

Mock: `SCR.cierre` / `drawCierre` en `p7_more.js:184-262`; capturas `k_cierre.png` (paso 1), `j_cierre2.png` (paso 2),
`j_cerrada.png` (cerrada).

- **Es pantalla completa sin barra** (`nonav`), no un modal. Hoy se abre con `mostrarModal(... PantallaCierre)` desde 4
  lugares: `navegacion/acciones_caja.dart` (cerrar y turno), `venta/pantalla_venta.dart` (`_irACierre`,
  `_cambiarTurno`) y `ventana/ventana_escritorio.dart`. Hacer una función `abrirCierre(context, builder)` (ruta a
  pantalla completa con fundido) y cambiar los 4 llamadores; mantener `onFinalizado` / `textoBotonFinal`.
- Arriba a la derecha, ancho máximo 1240: etiqueta "Paso N de 2" + `Btn.ton sm` "Volver a Venta" (en paso 1 y 2).
- **Paso 1** (grilla 440 | resto, separación 56, centrado, margen arriba 90): izquierda h1 46 "¿Cuánta plata hay en cada
  caja?", lead 18, `Nota` con candado ("La diferencia y la separación de cigarrillos se ven al confirmar…"), tarjeta
  "Arqueos del turno" (hora · Efectivo · MP · Lata). Derecha: nota amarilla de ventas abiertas con `Btn.dark xs`
  "Descartar" (`descartarVentasAbiertasYRecargar`), `Campo` grande "Efectivo contado (cajón)", chips de relleno rápido,
  fila con "Mercado Pago contado (según la app)" + "Traer saldo" (`traerSaldo`) y "Lata de cigarrillos contada"
  (solo con `Modulo.cajaAparte`), y `Btn.blue lg ancho` "Confirmar conteo" deshabilitado sin efectivo o con ventas
  abiertas. **Cambio de flujo**: MP y lata se cuentan acá, a ciegas, junto con el efectivo (hoy se escriben en el paso
  2). El controlador ya lo soporta: los tres controladores existen y `_recalcular` los lee.
  - Los chips "Cuadra justo / $ 250.000" del mock son datos de demostración: **no** poner "Cuadra justo" (rompería
    la Regla 10, contar a ciegas). Dejar solo el precargado del último arqueo, que ya existe.
- **Paso 2** (dos columnas iguales, separación 20): izquierda h1 40 "Cuadró el cajón" / "Faltan $ X en el cajón" /
  "Sobran $ X…", `BloqueHero` "Diferencia del cajón" con cifra 60 y etiqueta de tono, tres tarjetas (Mercado Pago ·
  "Suele ser la comisión de MP", Lata · etiqueta, Redondeo de hoy · "Informativo, no es descuadre"), `Lista` de `Kv`
  (Debería haber, Contaste, Fondo, Separación de cigarrillos, Reserva de fijos, Vendido sin costo → botón "N
  productos" que abre la lista de `resumenDia.productosSinDatos`), campo Nota. Derecha (scrollea): tarjeta "Mercado
  Pago según Mercado Pago" (rehacer `seccion_mp_real.dart` con filas `.ln` 15 px y los botones "Cargar como gasto/ingreso
  por MP" y "Volver a consultar"; nota "Esto nunca frena el cierre…"), tarjeta "A separar por proveedor" con la
  etiqueta amarilla "Ganancia sin revisar $ X" y "Separado a la lata en este cierre"; abajo fijos `Btn.blue lg` "Cerrar
  caja" y `Btn.out` "Volver a contar".
  - Falta en el controlador: `volverAContar()` (fase = conteo sin borrar lo escrito).
  - No perder lo que la app ya tiene y el mock no: aviso de cobros Point sin resolver, `DiferenciasSaldoMpVista`,
    arqueos, separación parcial de la lata, errores de respaldo/planilla.
- **Cerrada**: tilde verde de 130 en círculo `gbg` (trazo que se dibuja), h1 56 "Caja cerrada", lead 19 "Vendiste $ X
  en N tickets y ganaste $ Y…" (de `resumenDia`; la hora de la copia solo si salió bien), botones `lg`: dark
  `textoBotonFinal`, ton "Reabrir caja" (si `puedeReabrir`), ton "Volver a Venta". Partículas arriba: opcional.
- Tests a actualizar: `test/ui/cierre/pantalla_cierre_test.dart` (busca "Efectivo del día", `$4.500` sin espacio,
  `Superficie`, "Reabrir"), `pantalla_cierre_saldo_mp_test.dart`, `seccion_mp_real_test.dart`, `main_test.dart`,
  `accesibilidad/pantallas_accesibilidad_test.dart`, `venta/pantalla_venta_arqueo_intermedio_test.dart`.

## Cómo probar en la nube

Bajar Flutter 3.47.5 (`flutter_linux_3.47.5-stable.tar.xz` de `storage.googleapis.com/flutter_infra_release`),
`flutter pub get`, `flutter analyze` ("No issues found!") y `flutter test --exclude-tags bench`.
