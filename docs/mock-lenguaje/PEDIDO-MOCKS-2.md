# Pedido: segunda tanda de mocks — POS La Plazoleta

Mismo formato y mismo lenguaje que la primera tanda (`Main`, `Dashboard`,
`Proveedores`, `HistorialVentas`, `HistorialCierres` y los `Movil*`):
Figtree, fondo `#f0f4f9`, tarjetas blancas planas, acento `#0b57d0`,
tarjeta destacada casi negra, efectivo naranja `#b45309`, Mercado Pago azul
`#0b57d0`, ganancia verde `#146c2e`, botones pastilla y zonas táctiles de
44 px o más. Desktop a 1440×1024 y móvil a 390 px de ancho. Menú desplegable
desde el título, con las 6 secciones: Inicio, Venta, Proveedores,
Separaciones, Historial, Configuración. Los datos son de ejemplo.

Lo que cada pantalla tiene que tener sí o sí está abajo. La distribución la
propone el mock.

---

## Desktop

### 1. Cierre de caja (modal, en dos pasos)
- **Paso 1 — contar a ciegas**: un solo campo, "Efectivo contado", con los
  cigarrillos incluidos. **No se muestra ninguna cifra esperada antes de
  contar**: es una regla del negocio.
- **Paso 2 — revisado**:
  - **Efectivo**: fondo inicial + ventas en efectivo − gastos/pagos/retiros
    = debería haber; contra eso, lo contado y la diferencia. Cero va en
    verde, faltante en rojo y sobrante en marrón.
  - **Mercado Pago**: saldo esperado, campo "MP contado (según la app de
    MP)" y diferencia.
  - **Lata de cigarrillos**: "a separar a la lata" (precio de lista de los
    cigarrillos del día) y "lata contada".
  - **Resumen del día**: vendido total, redondeo acumulado, vendido sin
    costo cargado y reserva diaria de fijos.
  - Nota opcional y botón "Cerrar caja".

### 2. Detalle de un día cerrado (se entra desde Historial → Cierres)
- Encabezado con fecha, quién abrió, horario de apertura y cierre, y
  cuadró / diferencia.
- Botón "Generar PDF" (la planilla del día).
- Lista de las ventas del día: hora, N°, qué se llevó, medio de pago y
  total. Las anuladas se ven tachadas con la marca "Anulada" y las
  editadas con "Editada".
- Por venta: Reimprimir, Editar y Anular. Anular solo si la caja de ese día
  sigue abierta.

### 3. Editor de una venta ya cobrada
- Buscador para agregar productos y "+ Renglón libre" (algo sin producto,
  a mano).
- Líneas editables: cantidad o gramos, y quitar la línea.
- Medio de pago (Efectivo / Mercado Pago / Mixto) y total recalculado en
  vivo.
- **Motivo obligatorio** para guardar ("Guardar cambios"). Revierte stock y
  caja.

### 4. Conteo de stock (se abre desde Proveedores → Más acciones)
- Elegir un proveedor, o todos.
- Lista de productos: stock que dice el sistema, campo "contado" y la
  diferencia en el momento.
- Guardar todo junto. Cada ajuste deja rastro con motivo "conteo".

### 5. Carga histórica (cargar un día viejo desde la planilla de papel)
- **Paso 1**: fecha y hora del día a cargar.
- **Paso 2**: carrito como en Venta (buscar productos, cantidades), efectivo y
  MP contados, caja inicial normal y de cigarrillos, gastos del día, y
  cargar.
- Lista de días ya cargados, con opción de agregarles ventas o borrarlos.

### 6. Configuración → Impresión y posnet
- Terminal que imprime: access token de Mercado Pago (oculto) y terminal ID.
- Terminal que cobra (Point): terminal ID de cobro.
- Carpeta de tickets en PDF (elegir carpeta).
- Reimprimir una venta: N° de venta o "ver últimas".

### 7. Configuración → Respaldo
- Carpeta de respaldo (Drive/OneDrive), cuántas copias conservar,
  "Respaldar ahora" y la lista de respaldos existentes (fecha y tamaño),
  con restaurar.

### 8. Diálogos de Venta (chicos, con gente esperando: rápidos y con teclado)
- **Mixto**: total a cobrar, campo "parte en efectivo" y el resto que va a
  MP, calculado solo.
- **Varios**: monto de un producto sin código.
- **Gasto rápido** e **Ingreso rápido**: monto, motivo y de qué caja sale o
  a cuál entra (cajón normal, lata o Mercado Pago).
- **Editar cantidad**: cantidad o gramos exactos de una línea del carrito.

### 9. Diálogos de Proveedores y Separaciones
- **Avanzado del proveedor**: código, días de pedido y entrega, medio de
  pago, renombrar, lo separado dividido entre cajón y MP, y pagar. Para
  Serra Cigarros se ve la lata en lugar de separar y pagar.
- **Pagar a proveedor**: monto del cajón y monto de MP, prellenados con lo
  separado.
- **Nuevo proveedor**: nombre, código, días y medio de pago.
- **Edición masiva**: subir o bajar precio o costo (en % o $), cambiar
  categoría o proveedor, activar o desactivar los marcados.
- **Importar CSV**.
- **Ganancia del proveedor** (retener como colchón / retirar) y **Retirar
  ganancia** (cuánto del cajón y cuánto de MP).

---

## Móvil

### 10. Carrito de venta (la pantalla más usada del celular)
- Buscador y botón de escanear código.
- Líneas del carrito con +/− o gramos, y quitar.
- Descuento en $ o %.
- **Total grande siempre visible**.
- Cuatro medios: Efectivo, QR, Débito y Mixto. QR y Débito son el mismo
  Mercado Pago; cambia solo el canal.
- Cobrar, y "Cobrar a mano (sin terminal)" una vez elegido QR o Débito.
- Estado de la caja: si está cerrada, abrirla primero.

### 11. Historial de ventas (móvil)
- Filtros de período y medio.
- Lista agrupada por día.
- Tocar una venta muestra su detalle en una hoja de abajo, con anular
  (solo si su caja sigue abierta).

### 12. Cierres (móvil)
- Lista de cierres con el día, lo vendido y cuadró / diferencia.
- El detalle con la misma cuenta del efectivo que en la PC.

### 13. Gestión (menú de "Más")
- Accesos a Conteo de stock, Carga histórica, Cierres, Configuración,
  conectar/desconectar la PC y cerrar sesión.

### 14. Configuración (móvil)
- Recargo de cigarrillos, redondeo, producto del vuelto, markup por
  categoría, medios de pago y usuarios.

### 15. Movimiento de caja
- Gasto o ingreso, monto, motivo y caja (cajón / lata / MP).

### 16. Arqueo (el de cada 2 horas)
- Contar efectivo, MP y lata, y ver la diferencia de cada uno.

### 17. Consultar precio
- Escanear o buscar y ver precio, stock y proveedor, grande.

### 18. Conteo de stock (móvil)
- Igual que el de la PC, pensado para recorrer la góndola: un producto por
  fila y el teclado numérico directo.

### 19. Hojas de abajo y barra de navegación
- **Hojas**: estilo común para las hojas que suben desde abajo (cierre,
  arqueo, cobro con Point, edición masiva, "¿salir sin guardar?").
  Planas, sin vidrio.
- **Barra de navegación de abajo**: Inicio, Productos, Historial, Gestión y
  el botón central de escanear, en el lenguaje nuevo, sin vidrio.

### 20. Entrada (se usa poco, con que sea prolija alcanza)
- **Login**: Google, email, y "Entrar sin cuenta (por el wifi del local)".
- **Elegir usuario** del turno.
- **Emparejar con la PC** escaneando el QR.
