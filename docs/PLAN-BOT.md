# Plan · Bot de WhatsApp desde el celular, configurable desde Nodo Sur

**Estado al 2026-10-09: etapas 1 (rubro guardado, migración v63), 2 (sitio) y 3 (bot) hechas y mezcladas en los tres repos (en esta app, release #94); el resto, plan.** En `neaserisgod/botdemo` ya están las plantillas de uñas,
barbería y otro servicio. Revisado contra el código de los tres repos el mismo día. El resto del bot (turnos,
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

1. ✅ **Rubro guardado** (hecho el 2026-10-09; la etapa 1 de `PLAN-SERVICIOS.md`, achicada a lo que el bot necesita): `rubro` en
   `configuracion_negocio` (migración v63, sincronizado) y elegirlo en Configuración › Tu negocio del celular. La cuenta del
   almacén queda `almacen` cuando el dueño lo elige ahí (un negocio viejo arranca sin elegir: no se adivina).
2. ✅ **Sitio** (hecho el 2026-10-09, detalle en el README del sitio): `tieneBot`, equipo tipo `bot`, `/api/bot/config`, catálogo (`/api/bot/catalogo`) y pedidos
   (`/api/bot/pedido`, aceptar y rechazar), con el aviso al bot y a los equipos. Con tests, como el resto del sitio.
3. ✅ **Bot** (hecho el 2026-10-09, detalle en el README de `botdemo`): plantilla y flujo de almacén (precio y si hay, horarios y ubicación, pedidos); pausa de 1 hora configurable,
   también cuando el dueño contesta a mano; vincularse desde Termux; bajar configuración y catálogo y recargarlos sin
   reiniciarse; `instalar.sh` de un comando. Tests como los de barbería.
4. ✅ **App del celular** (hecha el 2026-10-09, salvo publicar): cliente del sitio para el bot y avisos en vivo de pedidos;
   publicar el catálogo (el equipo que sube la sync lo publica solo si hay plan con bot y si cambió); **pedidos por
   confirmar en Encargues** (`pedidos_bot.dart`: cualquiera de la app acepta o rechaza; Aceptar aparta como un encargue más
   a nombre de "Cliente (WhatsApp)" y recién después avisa; sin stock no acepta y dice qué falta; un pesable se pide por kilo,
   como lo ofrece el bot); pantalla **Más › Bot de WhatsApp** (`pantalla_bot_whatsapp.dart`: estado para todos;
   configuración e instalación para dueño/encargado; nombre y rubro salen de Configuración). La PC ahora manda `globalId`
   en `/productos` y `nombreComercio` en `/configuracion`: con una PC vieja, aceptar pide actualizarla.
   **Para publicar hacen falta los dos:** release nuevo de **Windows** (la PC también publica el catálogo, y el celular con
   PC necesita el `globalId`) y **APK beta**.

**Etapa 4, qué no se probó:** nada en un celular real. Con tests: aceptar contra una base real (stock, reintento sin
duplicar, ya resuelto, PC vieja), la sección de Encargues, la pantalla del bot y la fila de Más. El nombre del comercio
ahora también se carga en el celular (Configuración › Tu negocio, El dueño, 2026-10-09), así un negocio **solo celular**
puede configurar el bot. Quedan abiertos: (b) en **"PC y celular"**, los pedidos se ven solo si el celular está vinculado a la cuenta (el
token sale de ahí); (c) `numeroWhatsApp` no saca el 15 ("2944 15 123456" no se entiende; es la misma regla que el bot).
5. **Notificaciones con la app cerrada** (Firebase): registrar el token, mandar el aviso del pedido, pasos para crear el
   proyecto desde el celular.
6. Después: editar desde `/negocio` para "Solo el bot"; turnos de servicios (`PLAN-SERVICIOS.md`).

**Confirmado por el dueño antes de la etapa 3 (2026-10-09):** el pedido es para **retirar en el local** (sin envío); un producto
**sin stock no se agrega** al pedido; y el bot aclara que el precio es **el de hoy y puede cambiar** (vale el del día que se
retira, Regla 4, como cualquier encargue).

**Etapa 3, qué no se probó:** nada en un celular real ni con WhatsApp real. Sin probar: que Baileys reciba los mensajes que el
dueño manda a mano desde el celular principal (la pausa cuando contestás vos), los avisos en vivo por el WebSocket (necesitan
el Durable Object de Cloudflare; sin él el bot revisa cada 10 minutos), `termux-open-url` y el instalador en Termux. Sí se probó
el bot contra el worker real del sitio corriendo local (configuración, catálogo, pedido aceptado y aviso al cliente).

## Primera instalación real (2026-10-09, El dueño, en el local)

Publicado ese día: app (Windows 1.0.0.2155 y APK 2156, estable), sitio (`NodoSurPage` PR #55) y bot (`botdemo` PR #1 y #2).
Lo que apareció al instalarlo en un celular de verdad, en orden (el detalle técnico de cada uno está en `TRAMPAS.md`):

1. **Termux recién instalado no trae `curl`**: el comando de un paso falla con "curl: command not found". Hay que correr antes
   `pkg install -y curl`. *Pendiente:* que el comando que copia la app sea `pkg install -y curl && curl -fsSL … | bash`.
2. **Pegar con el portapapeles del teclado mete basura** (`^[[200~ … ~`, sale "bash~"). Se pega manteniendo apretado en la
   pantalla de Termux › Paste, o se escribe a mano. *Pendiente:* decirlo en el paso 2 de la pantalla del bot.
3. **Ningún mensaje se descifraba ("Bad MAC")**, ni con sesión nueva. Baileys 6.7.24 había quedado "legacy": se pasó a
   7.0.0-rc14 (fijada), con las claves en caché, y el modo de vincular ya no corta a los 2 s (espera 1 minuto). Arreglado en
   `botdemo` PR #2. Para actualizar un bot ya instalado: `cd ~/bot-turnos && git pull && npm install --omit=optional` y
   `bash bot.sh vincular`.
4. **Al vincular, el WhatsApp del celular puede mostrar un error aunque haya quedado vinculado**: en Termux aparece
   "código 515" (WhatsApp pide reconectar, es normal) y después "WhatsApp conectado". Se confirma en Dispositivos vinculados.
5. **"código 401 / Sesión cerrada desde el teléfono"** al cerrar la sesión vieja desde el celular: esperado.
6. **"Closing session: SessionEntry {…}"** en los registros no es un error: la librería reemplaza una clave vieja.
7. **El bot no le contesta a su propio número de soporte ni trata como cliente al número de avisos.** Probarlo desde el
   número del dueño (que en esta cuenta es el de soporte de Nodo Sur, 5492944796044) no da respuesta, a propósito
   (`botdemo/src/core/motor.js`). Para probar como cliente hay que escribir desde un tercer número.
8. **Ver si llegan los mensajes**: `DEPURAR=1 pm2 restart bot-turnos --update-env && pm2 logs bot-turnos` muestra
   `[msj] de=… texto="…"` por cada mensaje recibido. Para apagarlo: `pm2 restart bot-turnos --update-env` sin la variable.

9. **Los pedidos tardaban hasta 10 minutos en llegar a Encargues**: el bot los mandaba recién en la vuelta del sincronizador.
   Ahora salen después de cada mensaje (`botdemo` PR #3); el sitio no los duplica.

Estado al cierre del día: el bot vinculado, con la configuración de Nodo Sur, contesta, y **los pedidos llegan a Encargues**
(probado por el dueño desde un tercer número). Falta terminar la prueba completa de abajo.

## Prueba completa en el local

Desde un **tercer número** (ni el del bot, ni el de avisos, ni el de soporte), salvo donde se dice otra cosa. Cada paso dice
qué tiene que pasar.

**Consultas**
1. "hola" → saludo con el nombre del negocio y el menú (1 precios, 2 pedido, 3 ubicación y horarios, 4 persona).
2. "1" y después el nombre de un producto con stock (ej. "coca") → nombre, precio y ✅, con "precios de hoy, pueden cambiar".
3. "¿cuánto sale la yerba?" directo, sin menú → lo mismo.
4. Un producto con stock 0 → aparece con "❌ sin stock".
5. Algo que no existe ("¿tienen helicóptero?") → "No encontré ese producto".
6. Cambiar un precio en la PC o el celular, esperar que suba la sync (unos minutos) y volver a preguntar → precio nuevo.
7. "3", o "¿dónde están?" / "¿a qué hora abren?" → dirección y horarios, como se cargaron en Más › Bot de WhatsApp.

**Pedido**
8. "2" (o "quiero hacer un pedido") → pide productos de a uno.
9. "2 coca" → "Anotado: 2 × …" con el subtotal. Uno con varias coincidencias → lista para elegir con número.
10. Un producto sin stock → no lo agrega y lo dice.
11. "listo" → pide el nombre (solo la primera vez) → resumen con el total: *1* confirma, *2* agrega algo, *0* cancela.
    Con *1* → "Le pasé tu pedido al local".
12. En el celular con la app: **Encargues › Por confirmar · WhatsApp** muestra el pedido (con la app abierta aparece solo;
    si no, entrar de nuevo a Encargues).
13. **Aceptar y apartar** → queda como encargue "Nombre (WhatsApp)", baja el stock, y **al cliente le llega** que pase a
    retirarlo.
14. Otro pedido → **Rechazar** → al cliente le llega que no se puede; el stock no cambia.
15. Un pedido de algo que tiene poco stock, vender eso en la caja antes de aceptar, y aceptar → la app dice qué falta y no
    acepta; desde ahí se puede rechazar.
16. "cancelar" en medio de un pedido → "no anoté nada".
17. Entregar el encargue aceptado desde Encargues y cobrarlo → sale como cualquier encargue.

**Persona y pausa**
18. "4" (o "quiero hablar con alguien") → al cliente le dice que le van a responder; **al número de avisos le llega** el aviso
    con lo que escribió. Desde ahí el bot se calla en ese chat durante la pausa (hacer este paso al final, o desde otro
    número).
19. Contestarle a mano a ese cliente desde el WhatsApp del local → el bot se calla en ese chat durante la pausa configurada
    (60 min por defecto): un "hola" del cliente en ese rato no tiene respuesta del bot.
20. Pasada la pausa (o probar con la pausa en 15 min) → el bot vuelve a contestar.

**Dueño (desde el número de avisos)**
21. "ayuda" → la lista de lo que puede pedir el dueño.
22. "pasame los contactos" → manda el archivo de contactos.
23. "aviso …" → solo si de verdad se quiere mandar a todos los clientes (se manda en serio).

**Configuración desde la app**
24. Más › Bot de WhatsApp muestra "Andando" con la última señal (se actualiza cada hora).
25. Cambiar un horario o la dirección y Guardar → en unos segundos (o hasta 10 min sin avisos en vivo) el bot contesta con lo
    nuevo en el paso 7.
26. Un día marcado cerrado: en "3" figura "cerrado". El bot contesta igual a cualquier hora (no corta fuera de horario).

**Robustez**
27. Apagar el WiFi del celular del bot 5 minutos y prenderlo → vuelve a contestar solo (si no, `bash bot.sh revisar`).
28. Reiniciar el celular del bot → arranca solo (Termux:Boot) y contesta sin tocar nada.
29. Dejarlo un día entero: Más › Bot de WhatsApp no tiene que pasar a "Sin señal".

Si algo falla: captura de `pm2 logs bot-turnos --lines 60 --nostream` y del chat.

## Qué no se probó

Ver "Prueba completa en el local": al 2026-10-09 solo se probó que el bot se vincula, baja la configuración y recibe y descifra
los mensajes.
