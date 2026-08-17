#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <string>
#include <windows.h>

constexpr ULONG_PTR kMyNasCopyDataMagic = 0x4D4E4153; // 'MNAS'

void SingleInstancePublishHwnd(HWND hwnd);

// 释放 primary 持有的共享映射和就绪事件。应在 mutex 释放前调用。
void SingleInstanceShutdown();

// secondary 启动时调用：若已有 primary 则把 cmdline 转发过去并返回 true
// （调用方应直接退出），否则返回 false 让当前进程继续作为 primary。
// 成功获取 mutex 的句柄通过 mutex_out 返回，主退出前 CloseHandle。
bool SingleInstanceTryForwardOrAcquire(const std::wstring &cmdline_payload,
                                       HANDLE *mutex_out);

#endif // RUNNER_SINGLE_INSTANCE_H_
