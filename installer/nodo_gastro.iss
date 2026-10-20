; Instalador de Nodo Gastro para Windows (Inno Setup 6). Lo compila tool/crear_instalador.ps1 -Edicion gastronomia:
;   iscc /DMyAppVersion=1.0.0.2190 /DSourceDir=..\build\windows\x64\runner\Release installer\nodo_gastro.iss
;
; Calcado de installer/nodo_sur_servicios.iss (2026-10-20, docs/PLAN-GASTRONOMIA.md): otra app, con su AppId, su carpeta, su
; ícono, sus accesos directos, su mutex y su bot. Las tres ediciones conviven en la misma PC sin pisarse.
;
; Reglas que este instalador NO puede romper (las mismas de installer/la_plazoleta.iss):
;  - NUNCA toca la base (%APPDATA%\com.laplazoleta\Nodo Gastro\base\la_plazoleta.sqlite, ver lib/data/carpeta_base.dart):
;    ni al instalar, ni al actualizar, ni al desinstalar. Solo la COPIA antes de actualizar.
;  - Soporta /SILENT /SUPPRESSMSGBOXES /NORESTART (lo usa WinSparkle).
;
; Parámetros propios, para probar sin tocar nada real:
;   /DIR="C:\temp\app"      instala ahí en vez de C:\NodoGastro\app
;   /DATOS="C:\temp\datos"  usa esa carpeta de datos en vez de la de la app
;   /SINACCESOS=1           no crea accesos directos del escritorio ni del inicio

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#define MyAppName "Nodo Gastro"
#define MyAppExe "nodo_gastro.exe"
; Tiene que coincidir EXACTO con el mutex de windows/runner/main.cpp (rama EDICION_GASTRONOMIA).
#define MyAppMutex "NodoGastroAppMutex"

[Setup]
; GUID fijo y distinto de los de almacén y Servicios: es lo que hace que una versión nueva se reconozca como actualización de
; esta app (y no de otra). No cambiarlo nunca.
AppId={{86B9AC3D-38C8-4B0D-B6F8-D9BBEC91B0A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppPublisher=Nodo Sur
DefaultDirName=C:\NodoGastro\app
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=no
PrivilegesRequired=lowest
; Sin AppMutex a propósito: ver el comentario en installer/la_plazoleta.iss (WinSparkle le puede ganar la carrera al cierre).
CloseApplications=yes
CloseApplicationsFilter={#MyAppExe}
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=NodoGastro-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon_gastronomia.ico
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[InstallDelete]
; La carpeta queda IDÉNTICA al build nuevo (sin assets ni DLL de versiones viejas). Solo dentro de {app}.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\*.exe"
Type: filesandordirs; Name: "{app}\bot"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Actualización silenciosa (WinSparkle): la reabre sola.
Filename: "{app}\{#MyAppExe}"; Flags: nowait runasoriginaluser; Check: DebeReabrir

; Sin [UninstallDelete] a propósito: desinstalar borra solo {app} y los accesos directos, nunca los datos. El bot de WhatsApp sí
; se apaga (CurUninstallStepChanged): si no, seguiría corriendo desde la carpeta de datos y arrancaría al iniciar sesión.

[Code]
var
  EraActualizacion: Boolean;

// Donde la app guarda su base: la carpeta de datos que arma path_provider con CompanyName y ProductName de Runner.rc.
function CarpetaBase: String;
begin
  Result := AddBackslash(ExpandConstant('{param:DATOS|{userappdata}\com.laplazoleta\Nodo Gastro}')) + 'base';
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

// Copia la base al lado de la original antes de tocar nada. Sin base (instalación nueva) no hace nada; si la copia falla,
// lo anota y sigue: la base no se modifica de ninguna manera.
procedure CopiarBaseAntesDeActualizar;
var
  Base, Copia, Sufijo: String;
begin
  Base := AddBackslash(CarpetaBase) + 'la_plazoleta.sqlite';
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
  if FileExists(Base + '-wal') then
    FileCopy(Base + '-wal', Base + '-wal' + Sufijo, False);
end;

// Actualización silenciosa: se espera hasta 30 s a que la app suelte su mutex (windows/runner/main.cpp).
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

// Apaga el bot como lo hace la app (lib/servicios/bot_en_pc.dart): arranque.json con encendido=false (el supervisor lo ve
// en 3 segundos y corta) y sin la clave Run que lo arranca al iniciar sesión.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', 'NodoGastroBot');
    SaveStringToFile(ExpandConstant('{userappdata}\com.laplazoleta\Nodo Gastro\bot-datos\arranque.json'), '{"encendido":false}', False);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    EraActualizacion := FileExists(ExpandConstant('{app}\{#MyAppExe}'));
    CopiarBaseAntesDeActualizar;
  end;
end;
