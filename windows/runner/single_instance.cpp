#include "single_instance.h"

#include <windows.h>

namespace {

constexpr const wchar_t *kMutexName = L"Local\\MyNAS.App.SingleInstance";
constexpr const wchar_t *kMappingName = L"Local\\MyNAS.App.MainHwnd";
constexpr const wchar_t *kReadyEventName = L"Local\\MyNAS.App.MainHwndReady";
constexpr DWORD kMappingSize = sizeof(HWND);
constexpr DWORD kPrimaryReadyTimeoutMs = 15000;
constexpr UINT kMessageTimeoutMs = 5000;

HANDLE g_mapping = nullptr;
HANDLE g_ready_event = nullptr;

bool InitializePrimaryIpc() {
  if (g_mapping == nullptr) {
    g_mapping =
        ::CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                             kMappingSize, kMappingName);
  }
  if (g_ready_event == nullptr) {
    g_ready_event = ::CreateEventW(nullptr, TRUE, FALSE, kReadyEventName);
  }
  return g_mapping != nullptr && g_ready_event != nullptr;
}

bool WritePublishedHwnd(HWND hwnd) {
  if (g_mapping == nullptr)
    return false;
  void *view = ::MapViewOfFile(g_mapping, FILE_MAP_WRITE, 0, 0, kMappingSize);
  if (view == nullptr)
    return false;
  *reinterpret_cast<HWND *>(view) = hwnd;
  ::FlushViewOfFile(view, kMappingSize);
  ::UnmapViewOfFile(view);
  return true;
}

bool PreparePrimaryIpc() {
  if (!InitializePrimaryIpc())
    return false;
  // 其他进程可能仍持有上一任 primary 的命名对象。新 primary 必须清空旧
  // HWND 并重新置为未就绪，避免 secondary 把 deep link 发给失效窗口。
  ::ResetEvent(g_ready_event);
  return WritePublishedHwnd(nullptr);
}

bool TryTakeOverAbandonedPrimary(HANDLE *mutex_out) {
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  const DWORD error = ::GetLastError();
  if (mutex != nullptr && error != ERROR_ALREADY_EXISTS) {
    // 同 SingleInstanceTryForwardOrAcquire：拿到 mutex 说明没有其他实例，
    // IPC 初始化失败只降级 deep link 转发，不应导致本进程静默退出。
    (void)PreparePrimaryIpc();
    if (mutex_out != nullptr)
      *mutex_out = mutex;
    return true;
  }
  if (mutex != nullptr)
    ::CloseHandle(mutex);
  return false;
}

} // namespace

void SingleInstancePublishHwnd(HWND hwnd) {
  if (!InitializePrimaryIpc())
    return;
  if (WritePublishedHwnd(hwnd))
    ::SetEvent(g_ready_event);
}

void SingleInstanceShutdown() {
  if (g_mapping != nullptr)
    WritePublishedHwnd(nullptr);
  if (g_ready_event != nullptr) {
    ::ResetEvent(g_ready_event);
    ::CloseHandle(g_ready_event);
    g_ready_event = nullptr;
  }
  if (g_mapping != nullptr) {
    ::CloseHandle(g_mapping);
    g_mapping = nullptr;
  }
}

namespace {

HWND ReadPublishedHwnd() {
  HANDLE mapping = ::OpenFileMappingW(FILE_MAP_READ, FALSE, kMappingName);
  if (mapping == nullptr)
    return nullptr;
  void *view = ::MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, kMappingSize);
  HWND hwnd = nullptr;
  if (view != nullptr) {
    hwnd = *reinterpret_cast<HWND *>(view);
    ::UnmapViewOfFile(view);
  }
  ::CloseHandle(mapping);
  if (hwnd != nullptr && !::IsWindow(hwnd)) {
    hwnd = nullptr;
  }
  return hwnd;
}

} // namespace

bool SingleInstanceTryForwardOrAcquire(const std::wstring &cmdline_payload,
                                       HANDLE *mutex_out) {
  if (mutex_out)
    *mutex_out = nullptr;

  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  DWORD err = ::GetLastError();

  if (mutex != nullptr && err != ERROR_ALREADY_EXISTS) {
    // 共享映射/就绪事件创建失败只影响 deep link 转发，不能据此放弃启动：
    // 调用方把 true 当作「已有实例在运行」并立即退出，用户会看到双击图标
    // 后什么都没发生。窗口创建时 SingleInstancePublishHwnd 会再试一次。
    (void)PreparePrimaryIpc();
    if (mutex_out)
      *mutex_out = mutex;
    return false;
  }

  if (mutex != nullptr) {
    ::CloseHandle(mutex);
  }

  // primary 已拿到 mutex 但 Flutter 窗口尚未创建时，等待显式就绪事件，
  // 避免第二个实例在共享 HWND 发布前直接退出并丢失 deep link。
  HANDLE ready_event = ::CreateEventW(nullptr, TRUE, FALSE, kReadyEventName);
  if (ready_event != nullptr) {
    const DWORD wait_result =
        ::WaitForSingleObject(ready_event, kPrimaryReadyTimeoutMs);
    ::CloseHandle(ready_event);
    if (wait_result != WAIT_OBJECT_0) {
      if (TryTakeOverAbandonedPrimary(mutex_out))
        return false;
      return true;
    }
  }

  HWND primary = ReadPublishedHwnd();
  if (primary == nullptr) {
    if (TryTakeOverAbandonedPrimary(mutex_out))
      return false;
    return true;
  }

  if (!cmdline_payload.empty()) {
    COPYDATASTRUCT cds{};
    cds.dwData = kMyNasCopyDataMagic;
    cds.cbData =
        static_cast<DWORD>(sizeof(wchar_t) * (cmdline_payload.size() + 1));
    cds.lpData = const_cast<wchar_t *>(cmdline_payload.c_str());
    DWORD_PTR message_result = 0;
    ::SendMessageTimeoutW(
        primary, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds),
        SMTO_ABORTIFHUNG | SMTO_BLOCK, kMessageTimeoutMs, &message_result);
  }

  if (!::IsWindowVisible(primary)) {
    ::ShowWindow(primary, SW_SHOW);
  }
  if (::IsIconic(primary)) {
    ::ShowWindow(primary, SW_RESTORE);
  }
  ::SetForegroundWindow(primary);
  return true;
}
