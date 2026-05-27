#include "jumplist_channel.h"

#include <objbase.h>
#include <propkey.h>
#include <propsys.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>

#include <iostream>
#include <utility>

namespace {

constexpr const char* kChannelName = "my_nas/jump_list";

std::wstring g_executable_path;

template <class T>
inline void SafeRelease(T*& ptr) {
  if (ptr) {
    ptr->Release();
    ptr = nullptr;
  }
}

std::wstring GetWStringField(
    const flutter::EncodableMap& map,
    const std::string& key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return std::wstring();
  if (auto* s = std::get_if<std::string>(&it->second)) {
    int target_length = ::MultiByteToWideChar(
        CP_UTF8, 0, s->c_str(), -1, nullptr, 0);
    if (target_length <= 1) return std::wstring();
    std::wstring out(static_cast<size_t>(target_length - 1), L'\0');
    ::MultiByteToWideChar(
        CP_UTF8, 0, s->c_str(), -1, out.data(), target_length);
    return out;
  }
  return std::wstring();
}

int GetIntField(
    const flutter::EncodableMap& map,
    const std::string& key,
    int fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (auto* i = std::get_if<int64_t>(&it->second)) return static_cast<int>(*i);
  return fallback;
}

HRESULT CreateShellLink(const JumpListItem& item, IShellLinkW** out_link) {
  if (g_executable_path.empty() || item.label.empty() || item.args.empty()) {
    return E_INVALIDARG;
  }

  IShellLinkW* link = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&link));
  if (FAILED(hr)) return hr;

  hr = link->SetPath(g_executable_path.c_str());
  if (FAILED(hr)) goto fail;

  hr = link->SetArguments(item.args.c_str());
  if (FAILED(hr)) goto fail;

  {
    std::wstring work_dir = g_executable_path;
    auto slash = work_dir.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      work_dir.resize(slash);
      link->SetWorkingDirectory(work_dir.c_str());
    }
  }

  if (!item.icon_path.empty()) {
    link->SetIconLocation(item.icon_path.c_str(), item.icon_index);
  } else {
    link->SetIconLocation(g_executable_path.c_str(), 0);
  }

  if (!item.tooltip.empty()) {
    link->SetDescription(item.tooltip.c_str());
  } else {
    link->SetDescription(item.label.c_str());
  }

  {
    IPropertyStore* store = nullptr;
    hr = link->QueryInterface(IID_PPV_ARGS(&store));
    if (FAILED(hr)) goto fail;

    {
      PROPVARIANT title_var;
      hr = ::InitPropVariantFromString(item.label.c_str(), &title_var);
      if (SUCCEEDED(hr)) {
        hr = store->SetValue(PKEY_Title, title_var);
        ::PropVariantClear(&title_var);
      }
      if (SUCCEEDED(hr)) {
        hr = store->Commit();
      }
      store->Release();
    }
    if (FAILED(hr)) goto fail;
  }

  *out_link = link;
  return S_OK;

fail:
  link->Release();
  return hr;
}

HRESULT BuildCollection(
    const std::vector<JumpListItem>& items,
    IObjectCollection** out_coll) {
  IObjectCollection* coll = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&coll));
  if (FAILED(hr)) return hr;

  for (const auto& item : items) {
    IShellLinkW* link = nullptr;
    HRESULT link_hr = CreateShellLink(item, &link);
    if (FAILED(link_hr)) continue;
    coll->AddObject(link);
    link->Release();
  }

  *out_coll = coll;
  return S_OK;
}

}  // namespace

const wchar_t* const kMyNasAppUserModelId = L"MyNAS.App";

void JumpListChannel::SetExecutablePath(const std::wstring& path) {
  g_executable_path = path;
}

const std::wstring& JumpListChannel::GetExecutablePath() {
  return g_executable_path;
}

JumpListChannel::JumpListChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

JumpListChannel::~JumpListChannel() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void JumpListChannel::DispatchDeepLink(const std::wstring& url) {
  if (!channel_ || url.empty()) return;

  int target_length = ::WideCharToMultiByte(
      CP_UTF8, 0, url.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (target_length <= 1) return;

  std::string utf8(static_cast<size_t>(target_length - 1), '\0');
  ::WideCharToMultiByte(
      CP_UTF8, 0, url.c_str(), -1, utf8.data(), target_length,
      nullptr, nullptr);

  channel_->InvokeMethod(
      "onDeepLink",
      std::make_unique<flutter::EncodableValue>(utf8));
}

void JumpListChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "setTasks") {
    auto items = ParseItems(call.arguments());
    {
      std::lock_guard<std::mutex> lk(mutex_);
      tasks_ = std::move(items);
    }
    long hr = Commit();
    if (SUCCEEDED(hr)) {
      result->Success();
    } else {
      result->Error("commit_failed", "JumpList Commit failed",
                    flutter::EncodableValue(static_cast<int64_t>(hr)));
    }
    return;
  }

  if (method == "setRecent") {
    auto items = ParseItems(call.arguments());
    {
      std::lock_guard<std::mutex> lk(mutex_);
      recent_ = std::move(items);
    }
    long hr = Commit();
    if (SUCCEEDED(hr)) {
      result->Success();
    } else {
      result->Error("commit_failed", "JumpList Commit failed",
                    flutter::EncodableValue(static_cast<int64_t>(hr)));
    }
    return;
  }

  if (method == "clear") {
    {
      std::lock_guard<std::mutex> lk(mutex_);
      tasks_.clear();
      recent_.clear();
    }
    long hr = ClearList();
    if (SUCCEEDED(hr)) {
      result->Success();
    } else {
      result->Error("clear_failed", "JumpList clear failed",
                    flutter::EncodableValue(static_cast<int64_t>(hr)));
    }
    return;
  }

  result->NotImplemented();
}

std::vector<JumpListItem> JumpListChannel::ParseItems(
    const flutter::EncodableValue* arg) {
  std::vector<JumpListItem> out;
  if (arg == nullptr) return out;
  const auto* list = std::get_if<flutter::EncodableList>(arg);
  if (list == nullptr) return out;

  out.reserve(list->size());
  for (const auto& v : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&v);
    if (map == nullptr) continue;

    JumpListItem item;
    item.label = GetWStringField(*map, "label");
    item.args = GetWStringField(*map, "args");
    item.icon_path = GetWStringField(*map, "iconPath");
    item.icon_index = GetIntField(*map, "iconIndex", 0);
    item.tooltip = GetWStringField(*map, "tooltip");

    if (item.label.empty() || item.args.empty()) continue;
    out.push_back(std::move(item));
  }
  return out;
}

long JumpListChannel::Commit() {
  std::vector<JumpListItem> tasks_copy;
  std::vector<JumpListItem> recent_copy;
  {
    std::lock_guard<std::mutex> lk(mutex_);
    tasks_copy = tasks_;
    recent_copy = recent_;
  }

  ICustomDestinationList* cdl = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&cdl));
  if (FAILED(hr)) return hr;

  hr = cdl->SetAppID(kMyNasAppUserModelId);
  if (FAILED(hr)) { SafeRelease(cdl); return hr; }

  UINT min_items = 0;
  IObjectArray* removed = nullptr;
  hr = cdl->BeginList(&min_items, IID_PPV_ARGS(&removed));
  if (FAILED(hr)) { SafeRelease(cdl); return hr; }

  if (!tasks_copy.empty()) {
    IObjectCollection* coll = nullptr;
    if (SUCCEEDED(BuildCollection(tasks_copy, &coll)) && coll != nullptr) {
      IObjectArray* arr = nullptr;
      if (SUCCEEDED(coll->QueryInterface(IID_PPV_ARGS(&arr)))) {
        cdl->AddUserTasks(arr);
        SafeRelease(arr);
      }
      SafeRelease(coll);
    }
  }

  if (!recent_copy.empty()) {
    IObjectCollection* coll = nullptr;
    if (SUCCEEDED(BuildCollection(recent_copy, &coll)) && coll != nullptr) {
      IObjectArray* arr = nullptr;
      if (SUCCEEDED(coll->QueryInterface(IID_PPV_ARGS(&arr)))) {
        HRESULT cat_hr = cdl->AppendCategory(L"Recent", arr);
        if (FAILED(cat_hr)) {
          std::wcerr << L"[JumpList] AppendCategory failed: 0x"
                     << std::hex << cat_hr << std::endl;
        }
        SafeRelease(arr);
      }
      SafeRelease(coll);
    }
  }

  HRESULT commit_hr = cdl->CommitList();
  SafeRelease(removed);
  SafeRelease(cdl);
  return commit_hr;
}

long JumpListChannel::ClearList() {
  ICustomDestinationList* cdl = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&cdl));
  if (FAILED(hr)) return hr;

  hr = cdl->SetAppID(kMyNasAppUserModelId);
  if (SUCCEEDED(hr)) {
    hr = cdl->DeleteList(kMyNasAppUserModelId);
  }
  SafeRelease(cdl);
  return hr;
}
