# Nodo Sur Servicios en la compu (Windows y navegador)

Pedido del dueño (2026-10-15): *"la versión de escritorio de Nodo Sur Servicios, tanto web como ejecutable"*. Mock aprobado
ese mismo día ("me gusta, go"): `docs/mock-servicios/NodoSurServicios-escritorio.html` (vivo:
https://claude.ai/artifact/A6kFEry17u9gNCgDx4SfEG).

## Lo que decidió el dueño (2026-10-15)

1. **La misma app adaptada**, no pantallas nuevas: con la ventana ancha, la barra inferior pasa a ser un **menú lateral** y la
   agenda muestra el turno elegido al costado. Un solo código para celular, web y PC.
2. **El bot de WhatsApp también corre en la PC** (no solo en el Android). Etapa aparte, después de lo demás.
3. **Instalador aparte**, con su ícono (ciruela) y sus actualizaciones (`windows-servicios`): convive con la de almacén.

## Etapas

1. **Diseño ancho** (web y Windows) — hecha (2026-10-15).
2. **Edición Servicios en Windows** (arranque, datos aparte, instalador, publicación, sitio) — hecha (2026-10-15), **sin probar
   en una PC real** (ver "Sin probar").
3. **El bot en la PC** — hecho (2026-10-15), **sin probar en una PC real**. Ver "El bot en la PC" abajo.

## Cómo está armado

### Diseño ancho (`lib/companion/kit/escritorio_ns.dart`)

- Desde **1000 px de ancho de ventana** y con un negocio de servicios, `PantallaMenuCompanion` arma `MenuLateralNs` + las mismas
  pestañas (Agenda, Cobrar, Servicios, Caja, Más), con atajos **Alt+1…Alt+5**. Debajo de 1000 px, la del celular.
- Las pestañas pasan de una disposición a la otra (al agrandar o achicar la ventana) sin perder lo que tenían (llave global).
- **Agenda**: lista a la izquierda (hasta 820 px) y panel de 380 px con el turno elegido y sus botones (los mismos de la hoja del
  celular, `_botonesTurno`). **Cobrar**: grilla de servicios a la izquierda (más columnas) y el cobro a la derecha; el paso de
  elegir el medio también va en el panel. Servicios, Caja y Más se centran a 760 px.
- Lo que se abre desde una pestaña (Configuración, Cuenta, Bot, Proveedores…) **queda al lado del menú**, en un navegador
  propio del contenido (`ContenidoConMenuNs`), a ancho de lectura. Escape vuelve atrás; cambiar de pestaña lo cierra
  (El dueño, 2026-10-15: "se ven partes de móvil").
- Las **hojas que suben de abajo** son, en la compu, **ventanas al centro** (`mostrarHojaNs` → diálogo de 560 px, sin asa).
- Lo que va antes del menú (bienvenida, entrar) muestra la app a la derecha y un **panel de marca** a la izquierda
  (`PanelMarcaEscritorioNs`). El envoltorio de ancho (`companion_app.dart`) tiene **siempre los mismos widgets**: si
  cambiara de estructura, Flutter rearmaría el navegador y se perderían las pantallas abiertas.
- **Entrar con QR** (como una tele): la compu muestra un QR al entrar; con el celular ya vinculado, Más › Cuenta › "Entrar
  en una compu" lo escanea y confirma. La compu queda en el negocio y la sucursal del celular. Sitio:
  `functions/api/device/qr.js` (pedido de 5 min, un solo uso, PKCE: el código sin el verificador de la compu no sirve).
  El navegador queda como alternativa.
- Al volver de entrar se hace **una sola vuelta de sincronización** con el texto "Bajando los datos de tu negocio…" (antes
  podían ser hasta tres seguidas).
- Clientas (que aparecía en el mock) no existe todavía en la app: no se agregó.

### Edición Servicios en Windows

| Pieza | Cómo |
|---|---|
| Elegir la edición | `--dart-define=EDICION=servicios` (Dart) + `NODOSUR_EDICION=servicios` en el entorno (CMake). Lo hace `tool/crear_instalador.ps1 -Edicion servicios`, que borra `build\windows` antes: CMake no se reconfigura por una variable de entorno |
| Arranque | `main.dart`: como Android (`RaizCompanion`), ventana nativa de Windows de mínimo 1100×700, siempre "Solo celular" (sincroniza por internet) |
| `.exe`, nombre, ícono, mutex | `nodo_sur_servicios.exe`, "Nodo Sur Servicios", `app_icon_servicios.ico`, `NodoSurServiciosAppMutex` (`windows/runner/`) |
| Carpeta de datos | La da `ProductName` de `Runner.rc`: `%APPDATA%\com.laplazoleta\Nodo Sur Servicios`, distinta de la de almacén |
| **Base** | `lib/data/carpeta_base.dart`: en esa carpeta, en `base\`. **No en Documentos**, donde está la base de la app de almacén (sería el mismo archivo) |
| Entrar | Directo al navegador (no hay cuenta de Google del teléfono), con el servidor local como la PC |
| Actualizaciones | El aviso, como el celular (`latest.json` con `windows-servicios`); instalar, con WinSparkle como la PC (`appcast.xml?platform=windows-servicios`) |
| Instalador | `installer/nodo_sur_servicios.iss`: otro `AppId`, `C:\NodoSurServicios\app`, copia de la base antes de actualizar |
| Publicación | `publicar-beta.yml` publica las dos con el mismo número (`publicar_release.ps1 -Edicion servicios -SinSubirBuild`), la de servicios después de guardar el número |
| CI | `tests.yml`, job `windows-servicios`: compila en Windows y revisa nombre del `.exe` y `ProductName` cuando se toca lo que la arma |
| Sitio | `windows-servicios` en `PLATFORMS`, appcast con `sparkle:os="windows"`, `/descargar/` la ofrece al lado de la de almacén en Windows (repo `NodoSurPage`) |

### El bot en la PC

Lo mismo que en Android (`BotEnCelular`: descomprimir por versión, la cuenta del bot, el estado, la misma pantalla "Bot de
WhatsApp" con la sección "En esta compu"), con otro motor (`MotorBot`):

| Pieza | Android | Windows |
|---|---|---|
| Node | Termux en el APK (`libns_node.so`) | Node oficial de Windows, versión fija y verificada (`tool/preparar_bot_windows.ps1`), en `<app>\bot\node.exe` |
| El bot | `assets/bot/bot.zip` | el mismo zip (JavaScript puro, SQLite de Node), en `<app>\bot\bot.zip` |
| Lo mantiene vivo | `ServicioBot.kt` | `windows/bot/supervisor.js`: lo levanta, lo reinicia si se cae (5 s, 10 s… hasta 5 min), corta al apagar o al pasar a otra versión, uno solo por carpeta (`supervisor.pid`) |
| Encender / apagar | canal `nodosur/bot` | `bot-datos\arranque.json` (el supervisor lo mira cada 3 s) |
| Al prender el equipo | `ArranqueBot` | clave `HKCU\…\Run\NodoSurServiciosBot` → `nodo_sur_servicios.exe --bot <node> <supervisor> <datos>`: la app lanza el supervisor **oculto** y termina sin abrir ventana (`main.cpp`) |

- Node y el supervisor se **copian a la carpeta de cada versión del bot** (`%APPDATA%\…\bot\<huella>`), junto al código: nada
  corre desde la carpeta de la app, así el instalador la puede pisar con el bot andando. La huella incluye tamaño y fecha de
  Node, así que una app con otro Node pasa a otra carpeta y el bot viejo termina solo.
- Desinstalar apaga el bot (escribe `arranque.json` apagado y borra la clave Run).
- En la compu, el estado del bot queda a la vista al pie del menú lateral (como en el mock).
- `publicar-beta.yml` baja el bot (repo botdemo) y Node antes de armar el instalador de Servicios; sin ellos
  `crear_instalador.ps1 -Edicion servicios` no lo arma.

## Sin probar

- El QR entre un celular y una compu reales (cámara, permisos, tiempos).

- **En una PC con Windows real**: compilar (lo va a hacer CI), instalar al lado de la de almacén, entrar con Google, que la
  base quede en `%APPDATA%` y no en Documentos, actualizar con WinSparkle. Nada de esto se pudo correr en la nube (Linux).
- El navegador ancho de verdad (horsepos.com/app/ en una compu): solo capturas de test a 1440×900
  (`test/companion/capturas_escritorio_servicios_test.dart`).
- El bot en Windows real: que arranque oculto al iniciar sesión, que siga con la app cerrada, que se reinicie si se cae y que
  pase a la versión nueva al actualizar. El supervisor se probó en Linux con un bot de mentira (reinicio, apagado, cambio de
  versión); la parte de la app, con pruebas (`test/servicios/bot_en_pc_test.dart`).
- La compu tiene que quedar prendida y sin suspenderse para que el bot conteste: Windows no lo garantiza solo.
