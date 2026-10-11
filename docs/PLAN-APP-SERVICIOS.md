# Plan · Nodo Sur Servicios (la app de turnos con el bot adentro)

**Estado al 2026-10-10 (noche): las seis etapas hechas en la rama `ccr-d9ff719e-qd8uv7`** (este repo, `NodoSurPage` y `botdemo`),
con sus pruebas, sin mezclar. Falta probarlo en un celular real con un turno de verdad (ver "Abierto"). La prueba de que el bot corre adentro de la app sin Termux está en la
rama `ccr-d9ff719e-qd8uv7` (pantalla "Probar el bot acá", `lib/servicios/bot_en_celular.dart`, `ServicioBot.kt`,
`tool/preparar_bot_android.sh`). Node, SQLite, internet, Baileys y la conexión con WhatsApp anduvieron en el celular del dueño
(2026-10-10). **Falta la prueba larga** (una noche con la pantalla apagada) antes de construir sobre esto.

## Lo que decidió el dueño (2026-10-10)

1. **App aparte**, instalable al lado de la de almacén: el mismo código, otra edición (otro `applicationId`). Así el dueño tiene
   su almacén y el negocio de su amiga (iPhone, el bot lo corre él) en el mismo celular.
2. Nombre: **Nodo Sur Servicios**.
3. **Caja simple**: cobrar el turno, señas y cuánto entró hoy. Sin arqueo ni cierre con conteo.
4. **Todo con Mercado Pago**: el negocio vincula su cuenta (la conexión OAuth que ya existe, `NodoSurPage/functions/_lib/mp_conexion.js`).
   - **Seña por link de pago** que manda el bot; se confirma sola cuando Mercado Pago avisa el pago.
   - **QR en la pantalla del celular** para cobrar en el local, **interoperable** (lo lee cualquier billetera o banco). La "caja"
     de Mercado Pago que necesita ese QR se crea sola en la cuenta del negocio, una por sucursal.
5. Seña sin pagar: el turno se guarda **30 minutos**; después se libera solo y el bot le avisa a la clienta.
6. Devolver una seña (cancelación con tiempo): **la dueña confirma** ("¿Devolver $X a Fulana?") y se devuelve por Mercado Pago.
7. La **comisión** de Mercado Pago la paga la emprendedora: la clienta paga la seña justa.
8. Los negocios de servicios que hoy usan la app de almacén **pasan a la nueva**: la de almacén les ofrece instalarla con los
   mismos datos, y después se le saca el modo servicios a la de almacén.
9. **Solo Android por ahora** para el bot: el plan Emprendedor pide un Android (puede ser uno viejo). La amiga del dueño es la
   excepción, que corre él.
10. Al confirmarse la seña, el bot además: **le manda el recibo** a la clienta por WhatsApp, **avisa a la dueña** (notificación) y
    **recuerda el turno el día antes** con opción de confirmar o cancelar.

## Por qué así

- Sacar lo de almacén ahorra poco en peso (unos MB): lo que pesa es Node con el bot (~110 MB en el APK, ~120 MB de memoria
  andando). "Liviana" es más simple de usar, no más chica. La ganancia real de separarla es que el almacén no carga el bot.
- El bot sigue hablando con el sitio como hoy (`/api/bot/*`, reservas atómicas en D1): no hay un camino nuevo entre el bot y la
  app, y la agenda se sigue viendo desde la web (la amiga, con iPhone).

## Etapas (una por vez, cada una probada antes de la siguiente)

1. **Dos ediciones del mismo código.** Flavor de Gradle `servicios` (`applicationId` propio, nombre e ícono) + `--dart-define`
   con la edición. Node y `bot.zip` solo en esa edición. El workflow de publicación arma las dos y el sitio manda a cada una su
   actualización (plataforma `android-servicios`).
2. **Recortar la edición servicios**: fuera productos con stock, códigos de barras, proveedores y pagar proveedor, reposición,
   cigarrillos, conteo de stock, facturas, promos, carga histórica, emparejar con la PC. Queda: Agenda, Servicios, Clientes,
   caja simple, Configuración del negocio, Bot, Notificaciones, Cuenta.
3. **El bot de verdad adentro** (botdemo en `bot.zip`, con el SQLite de Node): la app le pide al sitio el acceso del bot con su
   propia cuenta vinculada (sin navegador ni Google) y muestra el código de vinculación de WhatsApp grande. Estado a la vista
   ("conectado · último mensaje hace 5 min").
4. **Que no se caiga**: arranca solo al prender el celular y se vuelve a levantar si Node se muere (lo hace Android, porque con el
   celular recién prendido Flutter no está abierto).
5. **Mercado Pago**: link de seña desde el bot con confirmación automática, vencimiento a los 30 minutos, recibo, aviso a la dueña,
   devolución con confirmación; QR interoperable en pantalla para cobrar en el local.
6. **Sitio**: descarga de Nodo Sur Servicios, plan Emprendedor apuntando a ella, y el paso de los negocios de servicios que hoy
   están en la app de almacén.

## Ajustes después de la primera prueba (El dueño, 2026-10-11)

- **Turnos duplicados**: un turno del bot tiene un `global_id` que sale de su id en el sitio (`globalIdDeTurnoRemoto`), así
  las dos apps del mismo negocio no crean cada una el suyo; los que ya estaban duplicados se muestran una vez.
- **Sin servicios cargados** el bot no ofrece los de ejemplo (`BOT_EN_APP` en botdemo): pasa la charla a una persona.
- **Agendar en el calendario** abre la app de calendario del celular (no Google Calendar en el navegador).
- **Agenda como el mock**: semana con puntitos, cifras de hoy, línea del día con los huecos libres (`filasDeAgenda`).
- **Que hable de turnos**: la pestaña del medio es "Cobrar"; la caja es "el día", que empieza sola al cobrar (sin fondo
  inicial ni Mercado Pago que contar) y se cierra con "Cerrar el día"; sin lata de cigarrillos en ningún lado; "cobros" en vez
  de "ventas"; el asistente solo ofrece rubros de servicios y no hay bienvenida de almacén.
- **Insumo nuevo con lo que ya hay** ("Lo que tenés ahora"), como movimiento "Stock inicial".

## Abierto

- **Firebase**: hecho (10/10), la app `com.laplazoleta.servicios` está registrada y su id cargado en `lib/servicios/push.dart`.
- Mezclar el sitio **antes** de publicar: sin `android-servicios` en el sitio, el workflow no puede subir el APK de servicios.
- Sacarle el modo servicios a la app de almacén cuando los negocios de servicios se hayan pasado.

- Precio del plan Emprendedor (recomendado $18.000) y el link del plan de suscripción de Mercado Pago: los tiene que crear el dueño.
- Que la prueba larga del bot adentro (una noche, pantalla apagada) salga bien. Si Android lo frena, se ve en el registro.
