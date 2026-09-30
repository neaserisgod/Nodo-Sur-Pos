# Primera versión de Nodo Sur POS — paso a paso

Todo lo que se puede probar sin Windows ya está probado (suite de tests en Linux). Lo que sigue se hace **en tu PC con
Windows**, porque compilar y firmar el instalador solo se puede ahí. Orden recomendado: primero una versión **beta**
(solo la ve tu cuenta de administrador), la probás vos, y recién después la publicás para todos.

## 0. Una sola vez: preparar la PC

1. **Programas**: Flutter (con Windows desktop: `flutter config --enable-windows-desktop`), Visual Studio con "Desarrollo
   para el escritorio con C++", **Inno Setup 6**, **Git for Windows** (trae `openssl`), **Node.js**.
2. **Repos**: clonar este (POS) y el del sitio (`NodoSurPage`). Después, en PowerShell:
   `$env:NODOSUR_SCRIPTS = 'C:\ruta\NodoSurPage\scripts'`
3. **Cloudflare**: `npx wrangler login` (una vez). El token de publicación `RELEASE_TOKEN` tiene que ser el **mismo** que está
   cargado como secreto en el Worker; en tu PC: `$env:RELEASE_TOKEN = '...'` (no lo escribas en ningún archivo).
   `BACKUP_KEY` ya está cargada en el Worker y respaldada aparte: no hace falta tenerla en la PC.
4. **Clave de firma de actualizaciones (DSA)**: si ya existe `Documents\la_plazoleta_claves\dsa_priv.pem`, no hagas nada
   (el script no la pisa). Si no existe: `.\tool\generar_claves_actualizacion.ps1` **una sola vez**, y **guardá la privada en
   un pendrive y en otro lugar más**. Si se pierde, las PC ya instaladas no pueden recibir más actualizaciones.
5. **Firma de código**: sin certificado el instalador sale sin firmar y Windows SmartScreen avisa al instalarlo (alcanza
   para empezar con tu PC). Con certificado: `$env:SIGN_PFX_PATH` y `$env:SIGN_PFX_PASSWORD`.
6. (Opcional) Copiá tu carpeta `test/capturas/` al repo: ya no la ignora el `.gitignore` y así los 4 tests que hoy no
   compilan vuelven a correr.

## 1. Cuidar tu base actual

Copiá `Documentos\la_plazoleta.sqlite` a un pendrive **antes de instalar**. Las actualizaciones de la base no se pueden
deshacer, y así tenés lo de hoy intacto.

## 2. Probar la cadena completa sin publicar nada

```powershell
git pull
.\tool\publicar_release.ps1 -DryRun
```

Compila, arma el instalador, lo firma y muestra el comando de subida **sin ejecutarlo**. Si algo falla, falla acá y no
se subió nada.

## 3. Publicar la beta (solo la ve tu cuenta)

```powershell
.\tool\publicar_release.ps1 -Notas "Primera versión generalizada" -Canal beta -Rollout 100
```

Sube el build number en `pubspec.yaml` (commiteá ese cambio), arma `dist\LaPlazoleta-Setup-<versión>.exe` y lo sube al
servidor en el canal beta.

## 4. Instalar en tu PC y revisar

1. Ejecutá `dist\LaPlazoleta-Setup-<versión>.exe` (instala encima: abre tu base y la actualiza sola).
2. Al abrir aparece **"Datos de tu comercio"**: cargá nombre y dirección (salen en ventana, menú y tickets).
3. Mirá **Configuración → Módulos**: todo debería estar prendido como antes. Vender, cerrar caja y un ticket de prueba.
4. **Configuración → Impresión**: tu token de Mercado Pago sigue ahí (solo la copia de la nube es la que no lo lleva).

## 5. Probar la cuenta de Nodo Sur

1. **Configuración → Cuenta de Nodo Sur → Vincular con mi cuenta**: entrás con Google en el navegador y confirmás.
   Debe decir "Vinculada a tu-correo" y **"recibe las versiones de prueba antes"** (eso confirma que sos administrador).
2. **Guardar una copia ahora**: debe aparecer en la lista. Cerrá la caja un día: también debe subirse sola.
3. **Restaurar en una instalación limpia** (otra PC o una máquina virtual; nunca sobre tu base real mientras probás):
   instalar, vincular con la misma cuenta, elegir la copia y **Restaurar**. Comprobá que están tus ventas y productos.
   Después hay que volver a cargar el token de Mercado Pago y emparejar el celular (la copia no los lleva).

Si te quedó solo el archivo `.sqlite` (sin cuenta): **Configuración → Respaldo → Importar una base → Importar desde un
archivo…**.

## 6. Pasar a todos los clientes

Cuando la beta ande bien varios días:

```powershell
.\tool\publicar_release.ps1 -Notas "Primera versión" -Rollout 10      # canal estable al 10 %
```

Subí el porcentaje desde horsepos.com/admin/ → *Versiones* mientras no aparezcan problemas. Si algo sale mal, ahí mismo
podés **Retirar** la versión (vuelve a ser la vigente la anterior) o **Bloquearla**. La descarga para clientes nuevos sale de horsepos.com/descargar/ (canal estable).

## Pendiente fuera de esta versión

- **APK del celular**: hoy se firma con la clave de debug; antes de repartirlo hace falta una keystore propia.
- **Cobrar con Point desde el celular sin la PC**: todavía no.
- **Pantalla "Mi cuenta" en el sitio** (lista de copias y dispositivos en la web).
- **Automatizar la publicación con GitHub Actions**: por ahora se publica desde tu PC, que es donde están las claves.
