#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring CurrentExecutablePath() {
  std::wstring path(260, L'\0');
  while (true) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) {
      return {};
    }
    if (length + 1 < path.size()) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

bool SetRegistryString(HKEY key, LPCWSTR value_name, const std::wstring& value) {
  return ::RegSetValueExW(
             key, value_name, 0, REG_SZ,
             reinterpret_cast<const BYTE*>(value.c_str()),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
      ERROR_SUCCESS;
}

void RegisterAuthProtocol() {
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    return;
  }

  HKEY scheme_key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER, L"Software\\Classes\\io.canvascreative", 0,
          nullptr, REG_OPTION_NON_VOLATILE,
          KEY_SET_VALUE | KEY_CREATE_SUB_KEY, nullptr, &scheme_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }

  SetRegistryString(scheme_key, nullptr, L"URL:Creative Canvas Auth");
  SetRegistryString(scheme_key, L"URL Protocol", L"");

  HKEY command_key = nullptr;
  if (::RegCreateKeyExW(
          scheme_key, L"shell\\open\\command", 0, nullptr,
          REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &command_key,
          nullptr) == ERROR_SUCCESS) {
    std::wstring command = L"\"";
    command += executable_path;
    command += L"\" \"%1\"";
    SetRegistryString(command_key, nullptr, command);
    ::RegCloseKey(command_key);
  }

  ::RegCloseKey(scheme_key);
}

}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  RegisterAuthProtocol();

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
  if (!window.Create(L"varian", origin, size)) {
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
