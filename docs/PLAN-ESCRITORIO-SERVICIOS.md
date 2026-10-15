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
3. **El bot en la PC** — pendiente. Node y `bot.zip` junto a la app, que arranque con Windows y se vuelva a levantar si se cae;
   mismo camino que el Android (`lib/servicios/bot_en_celular.dart`), con su pantalla de estado y el código de vinculación.

## Cómo está armado

### Diseño ancho (`lib/companion/kit/escritorio_ns.dart`)

- Desde **1000 px de ancho de ventana** y con un negocio de servicios, `PantallaMenuCompanion` arma `MenuLateralNs` + las mismas
  pestañas (Agenda, Cobrar, Servicios, Caja, Más), con atajos **Alt+1…Alt+5**. Debajo de 1000 px, la del celular.
- Las pestañas pasan de una disposición a la otra (al agrandar o achicar la ventana) sin perder lo que tenían (llave global).
- **Agenda**: lista a la izquierda (hasta 820 px) y panel de 380 px con el turno elegido y sus botones (los mismos de la hoja del
  celular, `_botonesTurno`). **Cobrar**: grilla de servicios a la izquierda (más columnas) y el cobro a la derecha; el paso de
  elegir el medio también va en el panel. Servicios, Caja y Más se centran a 760 px.
- Lo que se abre **encima** del menú (Configuración, Cuenta, Proveedores…) se sigue viendo del ancho de un celular, centrado:
  `companion_app.dart` achica la app salvo mientras el menú está arriba (`anchoLibreNs`, que maneja el menú con
  `observadorRutasNs`). Las hojas y diálogos no cambian la disposición de atrás. El envoltorio de ancho tiene **siempre los
  mismos widgets**: si cambiara de estructura, Flutter rearmaría el navegador y se perderían las pantallas abiertas.
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

## Sin probar

- **En una PC con Windows real**: compilar (lo va a hacer CI), instalar al lado de la de almacén, entrar con Google, que la
  base quede en `%APPDATA%` y no en Documentos, actualizar con WinSparkle. Nada de esto se pudo correr en la nube (Linux).
- El navegador ancho de verdad (horsepos.com/app/ en una compu): solo capturas de test a 1440×900
  (`test/companion/capturas_escritorio_servicios_test.dart`).
- Mezclar el sitio **antes** de publicar: sin `windows-servicios` en el sitio, el workflow no puede registrar el instalador.
