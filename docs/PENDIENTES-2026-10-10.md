# Pendientes para retomar (sesión del 2026-10-10)

Leer antes: `docs/PLAN-SERVICIOS.md` (etapas y decisiones), `REGLAS-NEGOCIO.md` §20 (servicios e insumos) y §21 (turnos y
seña), `DECISIONES.md` (últimas entradas). Principio del dueño (2026-10-10): **el cliente tipo emprende solo, pero todo
tiene que servir con empleados; lo que un rubro no usa se apaga para ese rubro (no se borra), con valores por defecto.**

## Publicado ese día (estable, Windows y APK juntos)

- PR #96: servicios en el celular (rubros, insumos, costos). Windows 2155, APK 2160.
- PR #97: el APK sale solo con el merge `release:`/`beta:`, en su propia fila, con el número calculado solo.
- PR #98: cerrar sesión y borrar el celular desde Más › Cuenta; un negocio de servicios ya no ve lo de almacén. Windows 2156,
  APK (número calculado: el último era 2160, debería ser 2161; no se verificó en el registro).
- PR #99: cobrar servicios (etapa 3), mergeado 01:05 UTC; **verificar que la publicación (Windows y APK) terminó bien**
- `botdemo` PR #7: rubros Peluquería y Estética; un salón con turnos no se vuelve comercio por Nodo Sur.

## 1. Agenda (etapa 4), EN CURSO

Hecho y probado (rama `ccr-a0284350-02fhfg`, sin PR todavía):
- `lib/domain/agenda.dart` + `test/domain/agenda_test.dart` (12 tests): `HorarioAtencion` (por defecto lunes a sábado
  9–19, JSON), `horariosLibres` (intervalo, sin pisar ocupados, sin horas pasadas), `seSuperponen`, `urlGoogleCalendar`
  (sin permisos de Google), `EstadoTurno` (esperando_seña, confirmado, llegó, cobrado, no vino, cancelado).
- Migración **v66** (`_sumarAgenda`): tabla `turnos` (`lib/data/tables/turnos.dart`) y en la configuración
  `horario_atencion` e `intervalo_turnos_minutos` (15). Sync: `turnos` en `tablasSincronizables`, en
  `tablasSincronizablesV61` (una PC vieja la saltea) y en `_referenciasCruzadas`.
- `lib/data/repositorio_turnos.dart` + `test/data/repositorio_turnos_test.dart` (8 tests): crear (con teléfono guarda al
  cliente), mover, marcar llegó/no vino, cancelar, cobrado con su venta, sobreturno, faltas del cliente, configuración.

Falta, en orden:
1. **Test de la migración v66** (copiar `test/data/migracion_v65_test.dart`).
2. Correr la suite entera: los tests que recorren `tablasSincronizables` (`sync_instalacion_nueva_test`,
   `sync_promos_test`, `sync_nube_test`) pueden necesitar ajuste por la tabla nueva.
3. **Pantalla Agenda** (`lib/companion/pantallas/pantalla_agenda_ns.dart`), como el mock (`docs/mock-servicios`,
   `vAgenda`): "Hoy" + tira de 7 días, cifras (turnos, cobrado, sin confirmar), chips de profesionales si hay más de un
   usuario, lista por hora con huecos "Libre hasta… + Turno". **Reemplaza a Inicio en servicios** (pestaña y
   `PantallaMenuCompanion`, como ya se hizo con Productos → Servicios; las cifras del día pasan a Caja › Resumen).
4. **Nuevo turno** (hoja): cliente (nombre + teléfono opcional), servicio, día, hora (de `horariosLibres`), profesional;
   si `esSobreturno`, avisa y deja guardar.
5. **Tocar un turno** (hoja): Llegó, **Cobrar** (pone la línea del servicio en el carrito, va a Vender y al cobrar llama a
   `marcarTurnoCobrado` con la venta), No vino, Mover, Cancelar, **Agregar a Google Calendar** (`urlGoogleCalendar` con
   `url_launcher`), WhatsApp al cliente.
6. Horario de atención e intervalo en Configuración (solo servicios).
7. Permisos (§21): dueño/encargado ven todas las agendas; empleado la suya.
8. Docs (`ESTADO.md`, `PLAN-SERVICIOS.md` etapa 4) y PR `release:`.

**Seña del turno: quedó afuera de la app a propósito.** Cobrarla en el celular obliga a que el cobro aplique una seña (hoy el
celular no cobra ni la de un encargue: 8 archivos y la terminal). La tabla ya tiene `sena_centavos`/`sena_es_efectivo`. Se
resuelve con el **link de pago** (punto 2): la seña entra sola como ingreso al pagarse.

## 2. Medios de pago para emprendedores (pedido del dueño, 2026-10-10, sin empezar)

"Ya que el cliente tiene su celular para cobrar": **efectivo, QR, transferencia y link de pago**. El link se manda solo
por el bot (por ejemplo, la seña); el QR aparece en la pantalla de la app del emprendedor. Orden recomendado (falta el OK):
1. **QR dinámico en pantalla** (sitio + app): Orders API `type: "qr"` con el Mercado Pago conectado del negocio
   (`mp_conexion.js` del sitio ya tiene el OAuth y crea órdenes Point); hace falta crear sucursal y caja de MP (se puede al
   conectar). La app muestra el QR (`qr` ya está en `pubspec`) y la venta se cierra con el aviso `payment` del webhook.
2. **Link de seña por el bot** (sitio + bot + app): Checkout Pro con el turno en `external_reference`; el bot manda el link;
   el webhook confirma el turno y la seña entra como ingreso en la próxima caja abierta (§21).
3. **Transferencia:** alias/CVU en la app y "recibida" a mano; confirmación sola solo si cae en la cuenta de MP (sin
   verificar si `/api/mp/cobros` la lista).
- **Tarjeta (Point)** pasa a ser módulo apagado por defecto en servicios.
- Cada negocio tiene que conectar su Mercado Pago; QR y link cobran comisión de MP.

## 3. Después de la agenda (orden acordado)

Más › Módulos como el mock (interruptores: agenda, insumos, bloquear si falta insumo, ajustar insumos, mano de obra, varios
profesionales, reventa apagada por defecto) → turnos del bot en la agenda (`docs/PLAN-SERVICIOS.md`, etapa 5).

## 4. Pendientes técnicos encontrados

- **Stock contado dos veces en un equipo que se sincroniza por primera vez** (`ESTADO.md`, pendientes técnicos): sin
  arreglar; ver primero si en la práctica un equipo nuevo arranca de una copia.
- Probar en un celular real: alta de peluquería, servicios e insumos, cobrar un servicio, propina, cerrar sesión.
- `flutter` no viene en el contenedor: se baja a `/tmp/fl` (3.47.5, ver `.github/workflows/publicar-*.yml`).
