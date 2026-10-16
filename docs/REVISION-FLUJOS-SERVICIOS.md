# Revisión de flujos: el arranque de Nodo Sur Servicios

Relevado el 2026-10-16 leyendo el código (no probado en un celular real). Sirve de punto de partida para la sesión que
revise **todos los flujos de las dos apps y de la página**. Las referencias `archivo:línea` son de ese día: verificarlas
antes de tocar.

## Qué busca el dueño

- Que la app sea **súper práctica**: que den ganas de **elegirla, usarla y no irse**.
- Que las funciones estrella (el bot que da turnos y cobra la seña) **encandilen al principio**, no que aparezcan después
  de configurar mucho.
- **Que no sea "una agenda" ni "un turnero".** Del brainstorming quedó: la app **trabaja mientras ella atiende**.
  - No se mete en la atención: nada de pantallas con la clienta en la silla, porque se pierde lo humano y se hace más lento.
  - Con la clienta delante, solo se usa para cobrar y dar el próximo turno, en un toque.
  - Todo lo demás lo hace sola: contestar, recordar, cobrar señas, llenar huecos y recuperar clientas.
- Ideas anotadas sin aprobar: `docs/IDEA-SOCIO-DE-NEGOCIO.md`.

## Decidido por el dueño

- **Descarga gratis y libre** (2026-10-16). Hoy hay que pagar antes de bajar el APK, y eso hay que sacarlo.
- **El segundo número de WhatsApp queda como opción**, porque mucha gente no usa su celular personal para el
  emprendimiento.
- Si usa su número personal, hay que resolver lo de abajo.

## A resolver: bot en el número personal

1. **Riesgo de baneo.** El dueño quiere que sea **nulo**. El bot usa WhatsApp Web no oficial (Baileys, botdemo), así que el
   riesgo no es cero por diseño. Hay que estudiar dos caminos:
   - Prácticas que lo minimicen: no escribir primero a desconocidos, poner límites de envío, no mandar masivos.
   - Pasar a la API oficial (Cloud API), que tiene costo y trámite.
   - Pros y contras de cada uno, y una recomendación.
2. **Lista negra.** Con un número personal, todos sus contactos (familia, amigos) recibirían respuestas del bot.
   - Hace falta una lista de números a los que el bot no responde nunca. Hoy no existe: busqué en botdemo y no hay nada.
   - A evaluar como alternativa: que el bot solo responda a quien no está en sus contactos, o a quien escribe con
     intención de turno.

## El flujo hoy (de bajar la app al primer turno con seña)

En total, más de 50 toques. Pasos:

1. **Web** (NodoSurPage): servicios → Google → plan Emprendedor ($18.000/mes, 7 días de prueba, pago con
   suscripción de Mercado Pago) → /descargar → instalar el APK a mano.
   - Sin suscripción no puede descargar (`functions/_lib/access.js:19-36`) ni sincronizar (`sync.js:59`).
2. **App**: logo → "Entrá con tu cuenta" → Google → espera de hasta 25 s de sincronización (`configurar/negocio_nuevo.dart:45`)
   → "Listo" → asistente de 4 pasos (`configurar/asistente_negocio.dart`):
   - nombre y rubro;
   - primer servicio;
   - horarios;
   - Mercado Pago (se conecta en la web).
3. **Cae en la Agenda vacía.** No hay nada del bot (`pantallas/pantalla_agenda_ns.dart:376-445`).
4. **Bot**: hay que encontrarlo en Más › Bot de WhatsApp. Ahí:
   - la fila solo aparece si el plan lo incluye;
   - pide **dos números** (`domain/bot_whatsapp.dart:396-399`);
   - permiso de batería y código de vinculación en WhatsApp.
5. **Seña**: viene **apagada** (`domain/turnos.dart:170`, modo "algunos") y el primer servicio se crea sin seña
   (`data/repositorio_servicios.dart:328`).

## Fallas y sobras del almacén encontradas

- **Si elige rubro "Otro"**, el asistente le pide cargar un **producto con código de barras** y desaparecen los horarios.
  - Ver `plantillas_rubro.dart:163-167` y `asistente_negocio.dart:143,199-211`. Probable bug.
- "Listo" dice **"Este celular ya está listo para vender"** (`bienvenida/pantalla_listo.dart:69`).
- **"Terminar" marca Mercado Pago como hecho aunque no lo conectó** (`asistente_negocio.dart:218`).
- **Si la primera sincronización falla, el asistente no aparece** y queda una base sin semilla
  (`pantalla_entrar_con_cuenta.dart:310-353`).
- **El asistente de IA pide pegar una clave de Gemini propia.**
- En Más aparecen textos y opciones del almacén:
  - "Usuario de este turno · Cambiar";
  - "Redondeo, medios de pago, categorías y usuarios";
  - "Ganancia por categoría";
  - Proveedores.
- El estado del bot solo se ve en la ventana ancha, no en el celular (`pantalla_agenda_ns.dart:933`).
- **No hay fichas de clientas**: el nombre y el teléfono viven solo en el turno (`data/tables/turnos.dart`).
- No hay lista de espera en la app.
- La **demo con datos de ejemplo** solo está en la web (horsepos.com/demo/, con barbería, peluquería, uñas y estética).
  - En la app de Android hay una semilla escondida: 7 toques en "Más", solo barbería, y hay que reiniciar.

## Propuesta para que encandile (sin aprobar todavía)

1. **El bot dentro del arranque.** "Conectá tu WhatsApp" pasa a ser el paso principal del asistente, y la seña
   viene prendida.
2. **Demo en la app desde el minuto uno**, con datos del rubro elegido: ve al bot dar un turno y cobrar la seña antes
   de configurar nada.
3. **Al entrar, lo que hizo el bot**: su estado y "esta semana te di X turnos", en vez de la agenda vacía.
4. **Limpiar las sobras del almacén** y corregir las fallas de arriba.

## Qué revisar en la sesión de flujos

- **Las dos apps**: almacén (PC y celular) y Servicios (celular).
- **La página**: alta, planes, pago, descarga, demo y conexión de Mercado Pago.
- **Por cada flujo**: cuántos pasos tiene, dónde se traba, qué texto o concepto es del rubro equivocado y qué falla si no
  hay internet.
