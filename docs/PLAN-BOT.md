# Plan · Bot de WhatsApp desde el celular, configurable desde Nodo Sur

**Estado al 2026-10-09: plan, sin código en Nodo Sur ni en el sitio.** En `neaserisgod/botdemo` ya están las plantillas de uñas
y barbería (rama `ccr-e5e5b532-aj3e0g`). Revisado contra el código de los tres repos el mismo día. El resto del bot (turnos,
seña, IA, API oficial) está en [`PLAN-SERVICIOS.md`](./PLAN-SERVICIOS.md), etapa 5.

## Lo que pidió el dueño (2026-10-09)

1. **Configurar el bot desde Nodo Sur**, solo si el negocio tiene un plan con bot.
2. **Todo desde el celular, con Termux.** El dueño no tiene la PC: instalar, vincular, configurar y cambiar el bot tiene que
   poder hacerse solo con el celular, y **lo más fácil posible**.
3. **Que cualquiera pueda hacerlo**, no solo él.
4. **Primero su cuenta, la del almacén**, con la plantilla de su rubro. Y él tiene que poder hacerlo y cambiarlo **desde la
   app Nodo Sur del celular**.

### Decisiones del dueño para el almacén (2026-10-09)

5. **Qué hace el bot del almacén:** contesta **precio y si hay**, **horarios y ubicación**, y **toma pedidos**.
6. **Número: el de siempre del almacén.** El bot se vincula como un dispositivo más de ese WhatsApp y el dueño sigue
   contestando desde su celular. **Riesgo aceptado:** con Baileys (no oficial), si WhatsApp bloquea el número se pierde el
   número que ya tienen los clientes.
7. **El bot corre en un celular aparte que queda en el local**, enchufado y con wifi.
8. **Un pedido entra "por confirmar"**: no aparta stock. El dueño lo ve en Encargues y con un toque lo acepta; recién ahí se
   aparta (como cualquier encargue) y el bot le confirma al cliente. Si no lo acepta, no toca nada.
9. **Notificación aunque la app esté cerrada** cuando entra un pedido (Firebase, ver abajo).
10. **Cuando no entiende o le piden una persona**, avisa y **se calla en ese chat**.
11. **Contesta a todos** los que escriben, proveedores y conocidos incluidos.
12. **Pausa de 1 hora** en un chat (antes eran 12): cuando el dueño contesta a mano desde su WhatsApp y cuando el bot no
    entiende o le piden una persona. Se cambia desde la app (el dueño dijo que 30 minutos o 1 hora alcanzan).

## Lo que encontró la revisión del código

1. **El rubro no está guardado en ningún lado.** Ni la app (`configuracion_negocio` no tiene la columna; `guardarNegocio` en
   `companion/configurar/negocio_nuevo.dart` solo usa la plantilla para sembrar categorías) ni el sitio (`orgs` no lo tiene).
   La cuenta del almacén no sabe que es un almacén. Es la etapa 1 de `PLAN-SERVICIOS.md` (`rubro` y `forma` en
   `configuracion_negocio`).
2. **No hay plantilla de bot para un almacén.** `botdemo` solo tiene uñas y barbería, y todo su flujo es de turnos. Un
   almacén no da turnos: lo que el sitio promete para un comercio es catálogo y pedidos, stock y horarios (pregunta 1).
3. **El sitio sabe qué plan pagó cada negocio, pero no lo usa.** `functions/_lib/mp.js` nombra cada suscripción ("Sistema
   POS", "Sistema + Bot", "Solo el bot"); `access.js` habilita todo con cualquier suscripción activa. Las cuentas de
   administrador y eximidas (la del dueño) entran siempre.
4. **El bot solo lee su configuración al arrancar**, de `config.json` en el celular (`src/config.js`).
5. **Vincular un equipo ya anda desde un celular.** `/vincular` abre el navegador, se entra con Google y el sitio devuelve el
   código a un servidor local en `127.0.0.1` (`api/device/authorize.js`, con PKCE). El bot en Termux puede hacer lo mismo y
   abrir el navegador con `termux-open-url` (Termux:API, que `setup.sh` ya instala). Hoy un equipo es `pc` o `celular`
   (`devices.kind`); el bot sería un tipo nuevo, `bot`.
6. **Nada de esto necesita PC.** El repo del bot es **público** (se baja sin contraseña). El APK se compila en GitHub
   (Actions → `publicar-apk`) y el sitio se publica solo al mezclar a `main`.
7. **El catálogo no le llega al bot.** Los productos viajan en lotes que el sitio guarda sin leer, y el stock no viaja como
   número: se arma sumando movimientos (`repositorio_sincronizacion.dart`). Lo más simple es que un equipo de Nodo Sur, que ya
   tiene el stock calculado, publique en el sitio una lista corta para el bot (nombre, precio, si hay) cada vez que cambia.
8. **La app no tiene notificaciones del sistema.** No hay ninguna librería de notificaciones ni Firebase en `pubspec.yaml`:
   se entera de los cambios solo con la app abierta (el aviso en vivo de la sync). La notificación con la app cerrada es
   trabajo nuevo.
9. **Un encargue "por apartado" descuenta stock al crearse** y lo devuelve si se cancela (`pendientes.lineasJson`, Regla 15).
   Por eso un pedido de WhatsApp no puede entrar directo como encargue (decisión 8).
10. **Hoy el bot ignora los mensajes que manda el propio número** (`adaptadores/baileys.js`, `msg.key.fromMe`). Para saber
    que el dueño contestó a mano hay que mirar justo esos. **Sin verificar** que Baileys los reciba cuando se mandan desde
    el celular principal; se prueba en la etapa 3.

## Cómo queda armado

- **Configuración del bot en el sitio**, por sucursal, como la clave de la IA y la conexión de Mercado Pago: tabla nueva en D1
  y `GET/POST /api/bot/config`. Guarda lo mismo que hoy está en `config.json`: rubro, textos, horarios, número del bot,
  pausa, y lo de cada rubro (servicios y seña en uñas y barbería). **Solo se usa con un plan con bot** (`tieneBot`: "Sistema
  + Bot" o "Solo el bot"; las cuentas eximidas y de administrador, como la del dueño, siempre).
- **En la app del celular**: Más › Negocio › **Bot de WhatsApp** (como en el mock de servicios). Solo aparece si el negocio
  tiene el bot. Muestra el estado (conectado, última señal), la configuración para editar y **"Instalar el bot en un
  celular"**, con los pasos y el comando para copiar.
- **El bot en Termux** se vincula como equipo `bot` y **baja su configuración del sitio** al arrancar y cada vez que el
  servidor le avisa que cambió (el mismo aviso en vivo de la sync). `config.json` queda solo como respaldo sin internet.
- **Catálogo para el bot**: el equipo de la sucursal que sube la sync a la nube (la PC si hay, si no el celular: es uno
  solo a la vez, `conmutador_sync.dart`) publica en el sitio una lista corta cada vez que cambia: `global_id`, nombre,
  precio y si hay stock. **Sin costo ni proveedor.** El bot contesta con eso.
- **Pedido de punta a punta:**
  1. El cliente pide por WhatsApp; el bot arma la lista con productos del catálogo y cantidades, y le pide un nombre.
  2. El bot lo manda al sitio (`POST /api/bot/pedido`) y le dice al cliente que el local lo confirma enseguida.
  3. El sitio guarda el pedido, **manda la notificación** a los celulares de la sucursal con la app y despierta a los
     equipos abiertos.
  4. En la app, Encargues muestra el pedido **por confirmar**. **Aceptar** crea el encargue apartado de siempre (con el
     cliente buscado o creado por su teléfono) y recién ahí descuenta stock; **Rechazar** no toca nada.
  5. El sitio le avisa al bot y el bot le escribe al cliente: confirmado o no.
- **Notificaciones (Firebase Cloud Messaging, gratis).** La app registra su token en el sitio; el sitio manda la
  notificación con una cuenta de servicio de Firebase (secreto nuevo del Worker). Una vez, el dueño crea el proyecto en
  Firebase desde el navegador del celular y carga dos archivos como secretos (uno en GitHub para el APK, otro en
  Cloudflare). Sirve también para otros avisos después.
- **Para "Solo el bot"** (sin la app): la misma configuración desde `/negocio` en la web. Va después.

### Instalar en un celular, lo más fácil posible

1. Instalar **Termux**, **Termux:Boot** y **Termux:API** desde F-Droid (la app de Nodo Sur deja los links). Abrir
   Termux:Boot una vez.
2. En Termux, pegar **un solo comando** (lo copia la app):
   `curl -fsSL https://raw.githubusercontent.com/neaserisgod/botdemo/main/instalar.sh | bash`
3. El instalador abre el navegador para **entrar con Google y elegir el negocio** (el mismo `/vincular` de siempre). La
   configuración baja sola: no hay que editar nada con `nano`.
4. Muestra el **código de WhatsApp**. En el celular que tiene el WhatsApp del almacén: Dispositivos vinculados › Vincular con
   el número de teléfono, y se escribe el código.
5. Queda andando y arranca solo al prender el celular. A mano queda solo: Ajustes › Apps › Termux › Batería › Sin
   restricciones (la app lo muestra paso a paso).

## Etapas (una por vez, cada una probada antes de la siguiente)

1. **Rubro guardado** (la etapa 1 de `PLAN-SERVICIOS.md`, achicada a lo que el bot necesita): `rubro` en
   `configuracion_negocio` (migración, sincronizado) y elegirlo en Configuración del celular. La cuenta del almacén queda
   `almacen`.
2. **Sitio**: `tieneBot`, equipo tipo `bot`, `/api/bot/config`, catálogo (`/api/bot/catalogo`) y pedidos
   (`/api/bot/pedido`, aceptar y rechazar), con el aviso al bot y a los equipos. Con tests, como el resto del sitio.
3. **Bot**: plantilla y flujo de almacén (precio y si hay, horarios y ubicación, pedidos); pausa de 1 hora configurable,
   también cuando el dueño contesta a mano; vincularse desde Termux; bajar configuración y catálogo y recargarlos sin
   reiniciarse; `instalar.sh` de un comando. Tests como los de barbería.
4. **App del celular**: pantalla Bot de WhatsApp (estado, configuración, instalar), publicar el catálogo, pedidos por
   confirmar en Encargues. APK beta.
5. **Notificaciones con la app cerrada** (Firebase): registrar el token, mandar el aviso del pedido, pasos para crear el
   proyecto desde el celular.
6. Después: editar desde `/negocio` para "Solo el bot"; turnos de servicios (`PLAN-SERVICIOS.md`).

**Supuesto a confirmar antes de la etapa 3:** el pedido es para **retirar en el local** (no hay envío), y el precio que
le dice el bot es el de ese momento: el que vale es el del día que se entrega (Regla 4, como cualquier encargue).

## Qué no se probó

Nada: es un plan. Lo de Termux (`termux-open-url`, `curl` en una instalación nueva, el vínculo por `127.0.0.1` en Android)
sale de cómo está hecho `setup.sh` y el sitio; no se probó en un celular.
