#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "flutter_window.h"
#include "jumplist_channel.h"
#include "single_instance.h"
#include "utils.h"

namespace {

// 从命令行 argv 里取第一个 mynas:// 形式的参数（用于转发给已运行的 primary）。
std::wstring ExtractDeepLinkArg() {
  int argc = 0;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return std::wstring();
  std::wstring out;
  for (int i = 1; i < argc; ++i) {
    std::wstring arg = argv[i];
    if (arg.rfind(L"mynas://", 0) == 0) {
      out = arg;
      break;
    }
  }
  ::LocalFree(argv);
  return out;
}

std::wstring GetExeFullPath() {
  wchar_t buf[MAX_PATH];
  DWORD len = ::GetModuleFileNameW(nullptr, buf, MAX_PATH);
  if (len == 0 || len == MAX_PATH) return std::wstring();
  return std::wstring(buf, len);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 设置显式 AUMID，让任务栏图标分组稳定，同时让 jump list 绑到正确的 group。
  // 必须在第一次创建窗口之前调用。
  ::SetCurrentProcessExplicitAppUserModelID(kMyNasAppUserModelId);

  // 把 EXE 路径告诉 jump list channel，IShellLinkW->SetPath 时要用。
  JumpListChannel::SetExecutablePath(GetExeFullPath());

  // desktop_multi_window 子窗口走单独入口：argv[1] == "multi_window"。
  // 这种情况下不做单实例判定（每个 multi_window 子进程都该独立运行）。
  int argc = 0;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  bool is_multi_window = false;
  if (argv != nullptr) {
    if (argc >= 2 && std::wstring(argv[1]) == L"multi_window") {
      is_multi_window = true;
    }
    ::LocalFree(argv);
  }

  HANDLE single_instance_mutex = nullptr;
  if (!is_multi_window) {
    std::wstring deep_link = ExtractDeepLinkArg();
    bool secondary = SingleInstanceTryForwardOrAcquire(
        deep_link, &single_instance_mutex);
    if (secondary) {
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1400, 900);
  if (!window.Create(L"my_nas", origin, size)) {
    if (single_instance_mutex) ::CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  if (!is_multi_window) {
    SingleInstancePublishHwnd(window.GetHandle());
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex) ::CloseHandle(single_instance_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
