# Pendiente: cliente Android de Google para el almacén ("ya en uso")

Estado al **2026-10-14**. Para retomarlo en otra sesión. Contexto del cambio en `DECISIONES.md`, "El celular entra con Google
desde la app, sin navegador".

## Qué se quiere

Que el celular entre con el selector de cuentas de Google de Android, sin abrir el navegador. Para eso Google exige, **en el
mismo proyecto de Google Cloud que el cliente Web del sitio** (el `GOOGLE_CLIENT_ID` del Worker, que la app pide en
`GET /api/device/google` y usa como `serverClientId`), un cliente OAuth **tipo Android** por cada app:

| App | Paquete | Estado |
|---|---|---|
| Nodo Sur Servicios | `com.laplazoleta.servicios` | **Creado** por el dueño (2026-10-14) |
| Almacén (companion) | `com.laplazoleta.companion` | **Falla al crearlo** |

Huella SHA-1 de la clave que firma los dos APK (sale en el resumen de cada corrida de `publicar-apk`, paso "Huella de la clave
de firma"): `33:F3:C5:4A:5F:C7:EF:28:ED:F8:77:1E:C8:D1:FE:BA:88:8F:50:3C`. Es el `debug.keystore` de la PC del dueño, el mismo
del secreto `ANDROID_KEYSTORE_BASE64`.

## El error

Al crear el cliente Android con `com.laplazoleta.companion` + esa SHA-1, Google Cloud contesta:

> No se pudo crear. La solicitud falló porque el nombre del paquete de Android y la huella digital ya están en uso.
> (Número de seguimiento: c5287550741202893)

Google deja registrar **cada pareja paquete + SHA-1 una sola vez en todo Google Cloud** (todos los proyectos). La misma SHA-1
con otro paquete sí se puede (por eso servicios anduvo). O sea: esa pareja ya existe en algún proyecto.

## Sospecha principal

El proyecto de **Firebase de las notificaciones**, `nodo-sur-eb45a` (número `831126263942`; `lib/servicios/push.dart`). Las
dos apps están registradas ahí (`appId` `1:831126263942:android:909951cf…` el almacén). Si alguna vez se cargó la SHA-1 en
la configuración de Firebase de la app del almacén, Firebase creó solo un cliente OAuth Android ("auto created by Google
Service") con esa pareja.

**Confirmado (2026-10-14)**: el cliente Web del sitio es `433741777622-tpf55b90v345tdfv15o0r059f3oigknn.apps.googleusercontent.com`,
o sea el proyecto número **`433741777622`**, distinto de Firebase (`831126263942`). Vale el segundo camino de abajo: los dos
clientes Android tienen que vivir en `433741777622`.

Los dos caminos posibles:

- **Si el cliente Web está en `nodo-sur-eb45a`**: no hay que crear nada. El cliente Android ya existe en el mismo proyecto que
  el Web; solo hay que confirmar en Credenciales que está y que tiene esa SHA-1. Ojo: entonces el cliente de **servicios** que
  se creó el 14/10 tiene que estar también en ese proyecto.
- **Si el cliente Web está en otro proyecto**: el Android del almacén tiene que vivir en ese otro proyecto (Credential Manager
  exige que el cliente Android y el `serverClientId` sean del mismo proyecto). Hay que sacar la pareja de donde está (Firebase
  → Configuración del proyecto → Tus apps → `com.laplazoleta.companion` → Huellas digitales SHA → borrar; a FCM no le hace
  falta) y crearla en el proyecto del Web.

## Pasos para investigar

1. Abrir `https://horsepos.com/api/device/google`: el `clientId` es `NUMERO-xxxx.apps.googleusercontent.com`; `NUMERO` es el
   número del proyecto del cliente Web. Compararlo con `831126263942`.
2. En Google Cloud, en ese proyecto → APIs y servicios → Credenciales → "IDs de clientes de OAuth 2.0": ver si ya hay un
   cliente Android para `com.laplazoleta.companion`, y en qué proyecto quedó el de `com.laplazoleta.servicios`.
3. Según el punto 1, seguir uno de los dos caminos de arriba.
4. Revisar que la pantalla de consentimiento de OAuth esté **publicada** (no "en prueba"), o solo entran los mails de prueba.
5. Probar en un celular con la beta 1.0.0+2179 (o posterior): Cuenta y sincronización → "Entrar con Google" tiene que mostrar
   el selector de cuentas sin abrir el navegador. Si sale "Entrar con el navegador", Google sigue sin reconocer la app.

## Cómo se ve en la app cuando falla

`pedirCuentaGoogleDelTelefono` (`lib/companion/google_en_celular.dart`) recibe `clientConfigurationError` o un "cancelado"
inmediato (Credential Manager no distingue una mala configuración de que la persona cierre el selector) y la pantalla ofrece
"Entrar con el navegador". Nada se rompe: es el camino de siempre.
