#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

#ifdef EDICION_SERVICIOS
// "--bot <comando>": lanza <comando> oculto (sin consola) y termina sin abrir ventana. Lo usa la clave Run que deja la app
// para que el bot de WhatsApp arranque al iniciar sesión (lib/servicios/bot_en_pc.dart): Node es un programa de consola y,
// llamado directo desde Run, abriría una ventana negra.
static bool LanzarBotOculto(const wchar_t* command_line) {
  const std::wstring argumentos(command_line ? command_line : L"");
  const std::wstring marca = L"--bot ";
  if (argumentos.compare(0, marca.size(), marca) != 0) return false;
  std::wstring comando = argumentos.substr(marca.size());
  STARTUPINFOW inicio{};
  inicio.cb = sizeof(inicio);
  PROCESS_INFORMATION proceso{};
  if (::CreateProcessW(nullptr, comando.data(), nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP, nullptr,
                       nullptr, &inicio, &proceso)) {
    ::CloseHandle(proceso.hThread);
    ::CloseHandle(proceso.hProcess);
  }
  return true;
}
#endif

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
#ifdef EDICION_SERVICIOS
  // Antes del mutex: este arranque no es la app (el instalador no tiene que esperarlo).
  if (LanzarBotOculto(command_line)) return EXIT_SUCCESS;
#endif
  // Mutex con nombre: el instalador (installer/la_plazoleta.iss,
  // InitializeSetup) lo usa para saber si la app sigue abierta y esperar a que
  // termine antes de actualizar. Tiene que coincidir EXACTO con MyAppMutex
  // del .iss. El handle se deja
  // abierto a propósito hasta que termine el proceso.
  // Nodo Sur Servicios tiene el suyo (installer/nodo_sur_servicios.iss): si fuera el mismo, actualizar una
  // esperaría a que se cierre la otra.
#ifdef EDICION_SERVICIOS
  ::CreateMutexW(nullptr, FALSE, L"NodoSurServiciosAppMutex");
#else
  ::CreateMutexW(nullptr, FALSE, L"LaPlazoletaAppMutex");
#endif

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Fase 13: el local pasó a una máquina con monitor de 1920×1080 o más —
  // esa es la resolución de diseño ahora, no 1280×720 (piso de la PC de
  // 2008 que ya no corre esta app).
  Win32Window::Size size(1920, 1080);
#ifdef EDICION_SERVICIOS
  const wchar_t* titulo = L"Nodo Sur Servicios";
#else
  const wchar_t* titulo = L"Nodo Sur POS";
#endif
  if (!window.Create(titulo, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
