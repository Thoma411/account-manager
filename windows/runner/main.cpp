#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Create a unique mutex name, preferably including the project name.
  // Note: The suffix L"Vault Keeper" ensures the lock is unique within the system.
  HANDLE hMutex = CreateMutexW(NULL, TRUE, L"Local\\accountmanager_unique_mutex");

  // Check if a mutex with the same name already exists
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // If an instance already exists, the application attempts to locate the existing window and bring it to the foreground.
    // The first parameter is the default Flutter class name: FLUTTER_RUNNER_WIN32_WINDOW.
    // The second parameter must match the window title configured in your main.dart or elsewhere: "Vault Keeper".
    HWND hWnd = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Vault Keeper");
    if (hWnd) {
      ShowWindow(hWnd, SW_RESTORE); // If the window is minimized, restore it first
      SetForegroundWindow(hWnd);    // bring window to the foreground focus
    }
    // The handle acquired by the current process must be released (it should be closed even though the error indicates an existing instance was found).
    if (hMutex) CloseHandle(hMutex);
    // Return 0 directly to silently exit the current process without initializing the Flutter engine.
    return 0; 
  }

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
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"accountmanager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (hMutex) {
    ReleaseMutex(hMutex);
    CloseHandle(hMutex);
  }

  return EXIT_SUCCESS;
}
