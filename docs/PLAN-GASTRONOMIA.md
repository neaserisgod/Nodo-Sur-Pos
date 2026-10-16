# Plan · Nodo Sur para locales gastronómicos

**Estado al 2026-10-16: etapas 1 y 2 hechas, y la base de la 3** (forma de trabajar `gastronomia`, rubro `rotiseria`, módulo
`pedidos`). Falta la pantalla.

## Por qué

El dueño, 2026-10-16: "hagamos una versión de servicios pero orientada a locales gastronómicos. En eso me defiendo más".
Conoce rotiserías, take away y mesas. Las rotiserías que conoce **no tienen WhatsApp o contestan tarde**: pierden pedidos.
La frase de venta: *"Tu WhatsApp contesta solo, al toque, y te deja el pedido listo para cocinar."*

## Lo que decidió el dueño

1. **Primero rotisería y take away; las mesas después.**
2. **Canales: arrancar por mostrador y WhatsApp.** Después teléfono (carga rápida) y el link propio. PedidosYa y Rappi
   los revisa el dueño.
3. **Tiene que andar en PC y en celular** ("depende del local"): se arma como Nodo Sur Servicios, la app del celular que
   ya corre en Android, en el navegador y en Windows.
4. **El local confirma** lo que llega de afuera, con la opción de que entre solo. Por eso, el **estado de la cocina**
   (normal, con demora, pausada) que el bot respeta.
5. **Entrega opcional:** retiro, cadete propio y **servicio de reparto** (no PedidosYa: una cadetería de afuera).
6. **Pago, lo elige cada local:** al entregar, adelantado, o que elija el cliente.

## Qué se reusa

- **Un plato es un servicio:** algo con receta de insumos y sin stock propio (`domain/servicios.dart`, §20). El costo de
  cada plato y para cuántos alcanza lo que hay ya salen solos.
- **El bot de almacén ya toma pedidos para retirar** (`botdemo/src/core/comercio.js`, `docs/PLAN-BOT.md`): catálogo
  publicado por la app, pedido "por confirmar" en el sitio, aviso al cliente al aceptar o rechazar.
- Caja, cierre del día, Mercado Pago (QR, link de pago), notificaciones, sincronización.

## Etapas (una por vez, cada una probada antes de la siguiente)

1. **Reglas de los pedidos** (`domain/pedido_gastronomico.dart`): canal, estados, cocina, entrega, zonas, pago, aviso al
   cliente. ✅
2. **Datos:** tabla de pedidos sincronizada (canal, estado, entrega, zona, dirección, hora estimada, líneas, venta con
   que se cobró) y la configuración de pedidos en la del negocio. Migración versionada. ✅ (v68)
3. **Edición gastronomía:** ✅ app aparte (2026-10-16, `DECISIONES.md`): flavor `gastronomia`, `esEdicionAparte`, plataformas
   del sitio, el alta ofrece solo "Rotisería". rubro "Rotisería / comida para llevar" con su forma de trabajar; la carta (platos con receta)
   en vez del catálogo de almacén. Base hecha ✅: `FormaDeTrabajo.gastronomia`, rubro `rotiseria` (todavía no aparece en
   ningún alta: no hay pantalla), módulo `pedidos`, y recetas, pesables y promos que valen para gastronomía. **Un plato es un
   producto con `esServicio` (receta, sin stock, sin duración)**: reusa el costo por receta de `repositorio_servicios.dart`
   en vez de duplicarlo.
4. **Lista de pedidos** (por confirmar, por hacer, listo, en camino) con el botón de estado de la cocina; el pedido de
   mostrador se carga desde la caja; cobrar un pedido es una venta de siempre. **Hecho ✅ (2026-10-16), salvo cobrar:**
   `companion/pantallas/pantalla_pedidos_ns.dart` abre en lugar del Inicio cuando el rubro es de gastronomía (pestañas
   "Pedidos" y "Carta"); cocina con un toque, lista por estado con el paso que sigue, detalle con cancelar y escribirle
   por WhatsApp, "+" para tomar un pedido del mostrador o del teléfono (platos por unidad; lo que se pesa, después). Al
   avanzar un pedido cargado por el local, ofrece avisarle al cliente por WhatsApp (los de WhatsApp los avisa el bot).
   **Falta:** cobrar el pedido (pasa a venta), la pantalla para configurar entregas, zonas y pago, y que el rubro se pueda
   elegir en un alta.
5. **Bot:** ofrece la carta, pregunta retiro o envío (dirección y zona), dice la hora según la cocina, no toma pedidos con
   la cocina pausada, pide el pago adelantado si el local lo quiere; el aviso "está listo" / "salió".
   **Con el catálogo de WhatsApp Business** (El dueño, 2026-10-16: "¿me pasás el catálogo? ¡Pum! link al catálogo…
   agrega el carrito, envía el carrito y toma los datos"). Revisado en Baileys 7.0.0-rc14 (`lib/Socket/business.js`):
   - "¿Me pasás el catálogo?" → el bot manda `wa.me/c/<número>` con cómo usarlo.
   - El cliente manda el carrito (`orderMessage`, con `orderId` y `token`) → `getOrderDetails` da cada producto (id de
     WhatsApp, cantidad, precio) → el bot sigue la charla (retiro/envío, nombre) y sube el pedido.
   - Coincidencia exacta: cada producto del catálogo lleva `retailerId` = `global_id` del plato. El id de WhatsApp se
     traduce con `getCatalog` (trae los dos). **El precio que vale es el de Nodo Sur.**
   - **Importar:** un local con catálogo ya armado lo trae a la carta con un toque (`getCatalog`).
   - **Espejo:** después, el bot deja el catálogo igual a la carta (`productCreate` / `productUpdate` / `productDelete`,
     `isHidden` para lo que se acabó).
   - Límites: solo números de **WhatsApp Business**; WhatsApp revisa cada producto nuevo y pide foto (si no hay, el logo
     del local); es la API no oficial, así que si deja de andar el bot vuelve al pedido por texto, que ya existe. A
     verificar en un celular real: en qué unidad viene el precio (parece ×1000) y cuánto tarda la revisión.
6. **Después:** teléfono, link propio, mesas (comandas, cocina, mozos, propinas).
