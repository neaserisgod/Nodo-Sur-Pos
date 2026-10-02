# Anotaciones de los mocks (para revisar más adelante)

Los mocks de la versión PC y celular (rediseño "antigravity") incluyen cosas
que **no existen en las apps reales**. Por ahora las apps solo llevan el
estilo nuevo y lo que ya existe; esto queda anotado para decidir caso por
caso si alguna merece implementarse.

## No existen en la app real

- **PC · Dashboard:** botón "Pedir a proveedores" en "Por reponer". La app real
  muestra "Stock bajo" pero no arma pedidos.
- **PC · Proveedores:** botón "Hacer pedido" (armar un pedido con lo que falta).
- **PC · Configuración (mock):** "Celular" con un código de 6 dígitos para
  vincular. La app real vincula con QR, o con IP, puerto y token.
- **PC · Configuración (mock):** "Copia de seguridad" en la nube cifrada. La app
  real tiene "Respaldo" en una carpeta local.
- **PC · Configuración (mock):** roles de usuario (Administradora / Cajero).
- **Celular · Inicio:** tocar "Conectado a la PC" para simular la falta de
  conexión (en la app real el aviso aparece solo).
- **Celular · Vender / Precio:** el botón de escanear solo simula una lectura.
- **Celular · Gestión:** tarjeta "Actualización" para buscar una versión nueva a
  mano (hoy la app avisa sola).
- **Celular · Cobro mixto:** elegir cuánto se paga en efectivo con atajos
  ("Mitad", "$ 10.000", "$ 20.000").

## Existen, pero en otro lugar o con otro nombre (revisar la ubicación)

- **Celular · Gestión:** "Cierres anteriores" y "Separaciones" como tarjetas. Las
  pantallas existen; falta confirmar desde dónde se llega hoy.
- **PC · Vender:** botones "Movimiento", "Arqueo" y "Varios" en la barra
  superior. Los diálogos existen; hoy se abren desde otros lugares.
- **PC · Dashboard:** "Efectivo en caja" con "Retirar o ingresar dinero". El
  movimiento rápido existe; la tarjeta no.

## Diferencias que quedan entre los mocks y las apps (por funciones reales)

- **PC · Cierre de caja:** el mock pide efectivo, Mercado Pago y lata en un solo
  paso; la app pide primero solo el efectivo (a ciegas) y recién después muestra
  lo esperado y pide Mercado Pago y lata. Se mantuvo el flujo real.
- **PC · Vender:** el mock cobra en dos pasos (ticket y después medio de pago);
  la app deja los cuatro medios siempre a la vista, con sus atajos Alt+tecla.
- **PC · Configuración, Equilibrio, Respaldo e Impresión:** llevan el estilo y los
  componentes nuevos; sus secciones y campos son los de la app real.
