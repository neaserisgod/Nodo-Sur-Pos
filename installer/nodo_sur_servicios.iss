; Instalador de Nodo Sur Servicios para Windows (Inno Setup 6). Lo compila tool/crear_instalador.ps1 -Edicion servicios:
;   iscc /DMyAppVersion=1.0.0.2180 /DSourceDir=..\build\windows\x64\runner\Release installer\nodo_sur_servicios.iss
;
; Es otra app, no una opción de la de almacén (El dueño, 2026-10-15, docs/PLAN-ESCRITORIO-SERVICIOS.md): su AppId, su
; carpeta, su ícono, sus accesos directos y su mutex. Las dos conviven en la misma PC sin pisarse.
;
; Reglas que este instalador NO puede romper (las mismas de installer/la_plazoleta.iss):
;  - NUNCA toca la base (%APPDATA%\com.laplazoleta\Nodo Sur Servicios\base\la_plazoleta.sqlite, ver lib/data/carpeta_base.dart):
;    ni al instalar, ni al actualizar, ni al desinstalar. Solo la COPIA antes de actualizar.
;  - Soporta /SILENT /SUPPRESSMSGBOXES /NORESTART (lo usa WinSparkle).
;
; Parámetros propios, para probar sin tocar nada real:
;   /DIR="C:\temp\app"      instala ahí en vez de C:\NodoSurServicios\app
;   /DATOS="C:\temp\datos"  usa esa carpeta de datos en vez de la de la app
;   /SINACCESOS=1           no crea accesos directos del escritorio ni del inicio

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#define MyAppName "Nodo Sur Servicios"
#define MyAppExe "nodo_sur_servicios.exe"
; Tiene que coincidir EXACTO con el mutex de windows/runner/main.cpp (rama EDICION_SERVICIOS).
#define MyAppMutex "NodoSurServiciosAppMutex"

[Setup]
; GUID fijo y distinto del de almacén: es lo que hace que una versión nueva se reconozca como actualización de esta app (y
; no de la otra). No cambiarlo nunca.
AppId={{823057E1-288A-4240-B0FA-9D2B3360F1CB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppPublisher=Nodo Sur
DefaultDirName=C:\NodoSurServicios\app
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
OutputBaseFilename=NodoSurServicios-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon_servicios.ico
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

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; WorkingDir: "{app}"; Comment: "{#MyAppName}"; Check: CrearAccesos

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Actualización silenciosa (WinSparkle): la reabre sola.
Filename: "{app}\{#MyAppExe}"; Flags: nowait runasoriginaluser; Check: DebeReabrir

; Sin [UninstallDelete] a propósito: desinstalar borra solo {app} y los accesos directos, nunca los datos.

[Code]
var
  EraActualizacion: Boolean;

// Donde la app guarda su base: la carpeta de datos que arma path_provider con CompanyName y ProductName de Runner.rc.
function CarpetaBase: String;
begin
  Result := AddBackslash(ExpandConstant('{param:DATOS|{userappdata}\com.laplazoleta\Nodo Sur Servicios}')) + 'base';
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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    EraActualizacion := FileExists(ExpandConstant('{app}\{#MyAppExe}'));
    CopiarBaseAntesDeActualizar;
  end;
end;
