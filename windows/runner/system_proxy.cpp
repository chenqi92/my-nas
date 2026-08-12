#include "system_proxy.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <utility>

namespace {

struct ProxyEndpoints {
  std::wstring http;
  std::wstring https;
};

bool EnvironmentVariableExists(const wchar_t* name) {
  ::SetLastError(ERROR_SUCCESS);
  const DWORD length = ::GetEnvironmentVariableW(name, nullptr, 0);
  return length > 0 || ::GetLastError() != ERROR_ENVVAR_NOT_FOUND;
}

bool HasProxyEnvironment(const wchar_t* lower, const wchar_t* upper) {
  return EnvironmentVariableExists(lower) || EnvironmentVariableExists(upper);
}

std::wstring Trim(std::wstring value) {
  const auto is_space = [](wchar_t character) {
    return std::iswspace(character) != 0;
  };
  const auto first = std::find_if_not(value.begin(), value.end(), is_space);
  const auto last =
      std::find_if_not(value.rbegin(), value.rend(), is_space).base();
  if (first >= last) return std::wstring();
  return std::wstring(first, last);
}

std::wstring ToLower(std::wstring value) {
  std::transform(
      value.begin(), value.end(), value.begin(), [](wchar_t character) {
        return static_cast<wchar_t>(std::towlower(character));
      });
  return value;
}

std::wstring NormalizeProxy(std::wstring value) {
  value = Trim(std::move(value));
  const std::wstring lower = ToLower(value);
  if (lower.rfind(L"http://", 0) == 0) return value.substr(7);
  if (lower.rfind(L"https://", 0) == 0) return value.substr(8);
  return value;
}

ProxyEndpoints ParseProxyEndpoints(const std::wstring& proxy_list) {
  ProxyEndpoints endpoints;
  std::wstring fallback;
  size_t start = 0;
  while (start <= proxy_list.size()) {
    const size_t end = proxy_list.find(L';', start);
    std::wstring entry = Trim(proxy_list.substr(start, end - start));
    const size_t equals = entry.find(L'=');
    if (equals == std::wstring::npos) {
      if (!entry.empty()) fallback = NormalizeProxy(std::move(entry));
    } else {
      const std::wstring scheme = ToLower(Trim(entry.substr(0, equals)));
      std::wstring server = NormalizeProxy(entry.substr(equals + 1));
      if (scheme == L"http") endpoints.http = std::move(server);
      if (scheme == L"https") endpoints.https = std::move(server);
    }
    if (end == std::wstring::npos) break;
    start = end + 1;
  }
  if (endpoints.http.empty()) endpoints.http = fallback;
  if (endpoints.https.empty()) endpoints.https = fallback;
  return endpoints;
}

std::wstring NormalizeBypassList(const std::wstring& bypass_list) {
  std::wstring result;
  size_t start = 0;
  while (start <= bypass_list.size()) {
    const size_t end = bypass_list.find(L';', start);
    std::wstring entry = Trim(bypass_list.substr(start, end - start));
    if (ToLower(entry) == L"<local>") {
      entry = L"localhost,127.0.0.1,::1";
    } else if (entry.rfind(L"*.", 0) == 0) {
      entry.erase(0, 2);
    }
    if (!entry.empty()) {
      if (!result.empty()) result.push_back(L',');
      result.append(entry);
    }
    if (end == std::wstring::npos) break;
    start = end + 1;
  }
  return result;
}

void FreeProxyConfig(WINHTTP_CURRENT_USER_IE_PROXY_CONFIG* config) {
  if (config->lpszAutoConfigUrl != nullptr) {
    ::GlobalFree(config->lpszAutoConfigUrl);
  }
  if (config->lpszProxy != nullptr) ::GlobalFree(config->lpszProxy);
  if (config->lpszProxyBypass != nullptr) {
    ::GlobalFree(config->lpszProxyBypass);
  }
}

}  // namespace

void ApplyWindowsSystemProxyEnvironment() {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config{};
  if (!::WinHttpGetIEProxyConfigForCurrentUser(&config)) {
    FreeProxyConfig(&config);
    return;
  }

  if (config.lpszProxy != nullptr) {
    const ProxyEndpoints endpoints = ParseProxyEndpoints(config.lpszProxy);
    if (!endpoints.http.empty() &&
        !HasProxyEnvironment(L"http_proxy", L"HTTP_PROXY")) {
      ::SetEnvironmentVariableW(L"http_proxy", endpoints.http.c_str());
    }
    if (!endpoints.https.empty() &&
        !HasProxyEnvironment(L"https_proxy", L"HTTPS_PROXY")) {
      ::SetEnvironmentVariableW(L"https_proxy", endpoints.https.c_str());
    }
  }

  if (config.lpszProxyBypass != nullptr &&
      !HasProxyEnvironment(L"no_proxy", L"NO_PROXY")) {
    const std::wstring bypass = NormalizeBypassList(config.lpszProxyBypass);
    if (!bypass.empty()) {
      ::SetEnvironmentVariableW(L"no_proxy", bypass.c_str());
    }
  }

  FreeProxyConfig(&config);
}
