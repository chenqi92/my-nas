#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "single_instance.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 注册 Jump List 通道（仅主窗口需要）。
  jump_list_channel_ = std::make_unique<JumpListChannel>(
      flutter_controller_->engine()->messenger());

  // 为子窗口注册插件回调（desktop_multi_window 子窗口需要此回调来注册插件）
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
      auto *flutter_view_controller =
          reinterpret_cast<flutter::FlutterViewController *>(controller);
      auto *registry = flutter_view_controller->engine();
      RegisterPlugins(registry);
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  jump_list_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      // 第二个实例通过 single_instance 发来的 deep link 转发。
      auto* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds != nullptr && cds->dwData == kMyNasCopyDataMagic &&
          cds->cbData >= sizeof(wchar_t) && jump_list_channel_) {
        const wchar_t* payload = static_cast<const wchar_t*>(cds->lpData);
        std::wstring url(payload);
        jump_list_channel_->DispatchDeepLink(url);
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
