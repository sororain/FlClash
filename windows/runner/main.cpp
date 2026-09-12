#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Flutter 3.47.1's Impeller crashes during texture initialization on some
  // GPUs (WER dump: flutter_windows.dll+0x926c90 INVALID_POINTER_READ).
  // Force Skia rendering via the official DartProject API - the
  // FLUTTER_ENGINE_SWITCHES env var was tried and did NOT take effect
  // (the same crash recurred with it set).
  // The switch must be applied before the engine initializes; DartProject is
  // consumed by FlutterViewController, created further down in this function.
  ::_putenv_s("FLUTTER_ENGINE_SWITCHES", "--enable-impeller=false");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Official API to disable Impeller (the env-var approach did NOT take
  // effect - the same crash recurred with it set). This avoids the
  // texture-initialization crash on some GPUs described at the top.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Sororain", origin, size)) {
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
