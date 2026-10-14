# Cliente Android de Google para el almacén ("ya en uso") — RESUELTO

**Resuelto el 2026-10-14.** Queda como registro. El mecanismo está en `TRAMPAS.md`, "Google Cloud: el nombre del paquete y la
huella digital ya están en uso". El porqué del cambio está en `DECISIONES.md`, "El celular entra con Google desde la app, sin
navegador".

## Cómo quedó

- **Cliente Web del sitio** (`GOOGLE_CLIENT_ID`): `433741777622-tpf55b90v345tdfv15o0r059f3oigknn.apps.googleusercontent.com`.
  Proyecto número **`433741777622`**, distinto del de Firebase (`nodo-sur-eb45a`, `831126263942`).
- **Clientes OAuth tipo Android**, los dos en `433741777622` con la SHA-1
  `33:F3:C5:4A:5F:C7:EF:28:ED:F8:77:1E:C8:D1:FE:BA:88:8F:50:3C` (`debug.keystore` del dueño, secreto `ANDROID_KEYSTORE_BASE64`):

| App | Paquete |
|---|---|
| Almacén (companion) | `com.laplazoleta.companion` |
| Nodo Sur Servicios | `com.laplazoleta.servicios` |

## Qué pasaba

Al crear el cliente del almacén, Google contestaba "el nombre del paquete de Android y la huella digital ya están en uso". La
pareja estaba tomada por un cliente que Firebase había creado solo en `nodo-sur-eb45a`, al cargarle la SHA-1 a la app del
almacén. Se borró ahí (cliente y SHA-1 de Firebase) y se creó en el proyecto del Web.

## Si alguna vez cambia la clave de firma

Hay que cargar la SHA-1 nueva en los dos clientes Android de `433741777622`; si no, el celular vuelve a entrar con el
navegador. La SHA-1 sale en el resumen de cada corrida de `publicar-apk`, paso "Huella de la clave de firma". **No cargarla
en Firebase.**

## Cómo se ve en la app cuando falla

`pedirCuentaGoogleDelTelefono` (`lib/companion/google_en_celular.dart`) recibe `clientConfigurationError` o un "cancelado"
inmediato (Credential Manager no distingue una mala configuración de que la persona cierre el selector), y la pantalla ofrece
"Entrar con el navegador". No se rompe nada: es el camino de siempre.
