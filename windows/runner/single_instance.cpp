#include "single_instance.h"

#include <windows.h>

namespace {

constexpr const wchar_t* kMutexName = L"Local\\MyNAS.App.SingleInstance";
constexpr const wchar_t* kMappingName = L"Local\\MyNAS.App.MainHwnd";
constexpr DWORD kMappingSize = sizeof(HWND);

}  // namespace

void SingleInstancePublishHwnd(HWND hwnd) {
  HANDLE mapping = ::CreateFileMappingW(
      INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
      0, kMappingSize, kMappingName);
  if (mapping == nullptr) return;
  // 故意不 CloseHandle(mapping)：让映射在 primary 进程生命周期内存在，
  // secondary 才能 OpenFileMappingW 到它。进程退出时 OS 自动回收。

  void* view = ::MapViewOfFile(
      mapping, FILE_MAP_WRITE, 0, 0, kMappingSize);
  if (view == nullptr) return;
  *reinterpret_cast<HWND*>(view) = hwnd;
  ::UnmapViewOfFile(view);
}

namespace {

HWND ReadPublishedHwnd() {
  HANDLE mapping = ::OpenFileMappingW(FILE_MAP_READ, FALSE, kMappingName);
  if (mapping == nullptr) return nullptr;
  void* view = ::MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, kMappingSize);
  HWND hwnd = nullptr;
  if (view != nullptr) {
    hwnd = *reinterpret_cast<HWND*>(view);
    ::UnmapViewOfFile(view);
  }
  ::CloseHandle(mapping);
  if (hwnd != nullptr && !::IsWindow(hwnd)) {
    hwnd = nullptr;
  }
  return hwnd;
}

}  // namespace

bool SingleInstanceTryForwardOrAcquire(
    const std::wstring& cmdline_payload,
    HANDLE* mutex_out) {
  if (mutex_out) *mutex_out = nullptr;

  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  DWORD err = ::GetLastError();

  if (mutex != nullptr && err != ERROR_ALREADY_EXISTS) {
    if (mutex_out) *mutex_out = mutex;
    return false;
  }

  if (mutex != nullptr) {
    ::CloseHandle(mutex);
  }

  HWND primary = ReadPublishedHwnd();
  if (primary == nullptr) {
    return true;
  }

  if (!cmdline_payload.empty()) {
    COPYDATASTRUCT cds{};
    cds.dwData = kMyNasCopyDataMagic;
    cds.cbData = static_cast<DWORD>(
        sizeof(wchar_t) * (cmdline_payload.size() + 1));
    cds.lpData = const_cast<wchar_t*>(cmdline_payload.c_str());
    ::SendMessageW(primary, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
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
