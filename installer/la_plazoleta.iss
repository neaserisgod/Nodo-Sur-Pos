; Instalador de Nodo Sur POS (Inno Setup 6). Lo compila tool/crear_instalador.ps1,
; que pasa la versión y la carpeta del build:
;   iscc /DMyAppVersion=1.0.0.2098 /DSourceDir=..\build\windows\x64\runner\Release installer\la_plazoleta.iss
;
; Reglas que este instalador NO puede romper:
;  - Instala en C:\LaPlazoleta\app, la misma ruta que usa
;    tool/publicar_actualizacion_desktop.ps1, para que una actualización pise
;    la instalación actual y los accesos directos sigan andando.
;  - NUNCA toca la base (Documents\la_plazoleta.sqlite): ni al instalar, ni al
;    actualizar, ni al desinstalar. Solo la COPIA antes de actualizar.
;  - Soporta /SILENT /SUPPRESSMSGBOXES /NORESTART (lo usa WinSparkle).
;
; Parámetros propios, pensados para probar sin tocar nada real:
;   /DIR="C:\temp\app"      instala ahí en vez de C:\LaPlazoleta\app
;   /DOCS="C:\temp\docs"    usa esa carpeta en vez de Documents
;   /SINACCESOS=1           no crea accesos directos del escritorio ni del inicio

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#define MyAppName "Nodo Sur POS"
#define MyAppExe "la_plazoleta.exe"
; Tiene que coincidir EXACTO con el mutex de windows/runner/main.cpp.
#define MyAppMutex "LaPlazoletaAppMutex"

[Setup]
; GUID fijo: es lo que hace que una versión nueva se reconozca como
; actualización de la anterior. No cambiarlo nunca.
AppId={{6F1B7D52-3C0E-4B8A-9E4D-2A7C5D91B3E8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppPublisher=Nodo Sur
DefaultDirName=C:\LaPlazoleta\app
; Siempre la misma ruta: que el que actualiza no pueda instalar en otro lado
; y dejar dos copias. /DIR sigue funcionando para las pruebas.
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=no
; C:\LaPlazoleta ya se escribe hoy sin permisos de administrador (lo hace el
; script de publicación), y los accesos directos son del usuario.
PrivilegesRequired=lowest
; Sin la directiva AppMutex a propósito: Inno la revisa ANTES de cerrar
; aplicaciones y, en modo silencioso, cancela la instalación si la app sigue
; abierta (probado: es justo el caso de WinSparkle, que lanza este instalador
; apenas le pide a la app que se cierre y puede ganarle la carrera). En su
; lugar, InitializeSetup espera a que se libere el mutex y, si sigue abierta,
; CloseApplications la cierra por Restart Manager.
CloseApplications=yes
CloseApplicationsFilter={#MyAppExe}
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=NodoSurPOS-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[InstallDelete]
; Como el /MIR de robocopy del script de publicación: la carpeta queda IDÉNTICA
; al build nuevo (sin assets ni DLL de versiones viejas). Solo dentro de {app}.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\*.exe"
; Accesos directos con el nombre anterior (renombre a Nodo Sur POS): se borran para no dejar duplicados.
Type: files; Name: "{userstartup}\La Plazoleta.lnk"
Type: files; Name: "{userdesktop}\la_plazoleta - Acceso directo.lnk"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Mismos nombres que crea hoy tool/publicar_actualizacion_desktop.ps1, para que
; el instalador los pise en vez de duplicarlos.
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos

[Run]
; Instalación a mano: casilla "Abrir Nodo Sur POS" al final.
Filename: "{app}\{#MyAppExe}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Actualización silenciosa (WinSparkle): la reabre sola, que el local siga
; vendiendo sin que nadie tenga que buscar el icono.
Filename: "{app}\{#MyAppExe}"; Flags: nowait runasoriginaluser; Check: DebeReabrir

; Sin [UninstallDelete] a propósito: desinstalar borra solo lo que instaló acá
; ({app} y los accesos directos), nunca nada de Documents.

[Code]
var
  EraActualizacion: Boolean;

function CarpetaDocumentos: String;
begin
  Result := ExpandConstant('{param:DOCS|{userdocs}}');
end;

function CrearAccesos: Boolean;
begin
  Result := ExpandConstant('{param:SINACCESOS|0}') <> '1';
end;

function DebeReabrir: Boolean;
begin
  Result := WizardSilent and EraActualizacion;
end;

function FechaHoy: String;
begin
  Result := GetDateTimeString('yyyymmdd', #0, #0);
end;

// Copia la base al lado de la original antes de tocar nada. Si la base no
// existe (instalación nueva) no hace nada; si la copia falla, avisa en el log
// pero NO frena la instalación: la base no se modifica de ninguna manera.
procedure CopiarBaseAntesDeActualizar;
var
  Base, Copia, Sufijo: String;
begin
  Base := AddBackslash(CarpetaDocumentos) + 'la_plazoleta.sqlite';
  if not FileExists(Base) then
  begin
    Log('No hay base en ' + Base + ': no se hace copia previa.');
    Exit;
  end;
  Sufijo := '.backup-pre-update-{#MyAppVersion}-' + FechaHoy;
  Copia := Base + Sufijo;
  if FileCopy(Base, Copia, False) then
    Log('Copia previa de la base: ' + Copia)
  else
    Log('ATENCION: no se pudo copiar la base a ' + Copia);
  // Si quedó un -wal sin consolidar, la copia de la base sola estaría
  // incompleta: se copia también, con el mismo sufijo.
  if FileExists(Base + '-wal') then
    FileCopy(Base + '-wal', Base + '-wal' + Sufijo, False);
end;

// Actualización silenciosa: WinSparkle le pide a la app que se cierre y
// lanza este instalador al toque, así que la app puede estar todavía
// terminando. Se espera hasta 30 s a que suelte el mutex (windows/runner/
// main.cpp). Si no lo suelta, sigue igual y CloseApplications se ocupa. Con
// el instalador a mano no se espera: el asistente ya ofrece cerrarla.
function InitializeSetup: Boolean;
var
  Intentos: Integer;
begin
  Result := True;
  if not WizardSilent then Exit;
  Intentos := 0;
  while CheckForMutexes('{#MyAppMutex}') and (Intentos < 60) do
  begin
    Sleep(500);
    Intentos := Intentos + 1;
  end;
  Log('Esperas por el cierre de la app: ' + IntToStr(Intentos));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    EraActualizacion := FileExists(ExpandConstant('{app}\{#MyAppExe}'));
    CopiarBaseAntesDeActualizar;
  end;
end;
