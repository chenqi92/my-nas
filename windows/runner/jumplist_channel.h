#ifndef RUNNER_JUMPLIST_CHANNEL_H_
#define RUNNER_JUMPLIST_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <mutex>
#include <string>
#include <vector>

// Stable, project-specific AppUserModelID. Used both to group taskbar icons
// and to bind the custom Jump List to this app.
extern const wchar_t* const kMyNasAppUserModelId;

// Per-item descriptor (Tasks 与 Recent 共用).
struct JumpListItem {
  std::wstring label;
  std::wstring args;
  std::wstring icon_path;
  int icon_index = 0;
  std::wstring tooltip;
};

// MethodChannel: my_nas/jump_list
//
// Dart → Native:
//   setTasks(List<Map<String,Object?>>)
//   setRecent(List<Map<String,Object?>>)
//   clear()
//
// Native → Dart:
//   onDeepLink(String url)  — 来自 Jump List 拉起 / 第二个实例转发的 deep link
class JumpListChannel {
 public:
  explicit JumpListChannel(flutter::BinaryMessenger* messenger);
  ~JumpListChannel();

  JumpListChannel(const JumpListChannel&) = delete;
  JumpListChannel& operator=(const JumpListChannel&) = delete;

  static void SetExecutablePath(const std::wstring& path);
  static const std::wstring& GetExecutablePath();

  // 由 flutter_window.cpp 在收到 WM_COPYDATA 时调用，转发到 Dart。
  void DispatchDeepLink(const std::wstring& url);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::vector<JumpListItem> ParseItems(const flutter::EncodableValue* arg);
  long Commit();
  long ClearList();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::mutex mutex_;
  std::vector<JumpListItem> tasks_;
  std::vector<JumpListItem> recent_;
};

#endif  // RUNNER_JUMPLIST_CHANNEL_H_
