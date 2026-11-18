#include "single_instance.h"

#include <utility>

#include "utils.h"

namespace {

// Names are scoped to this app via the installer AppId GUID to avoid
// collisions with other Flutter apps (the runner window class is generic).
constexpr wchar_t kMutexName[] =
    L"Local\\Notepad.SingleInstance.{6F0E60BA-5F2D-4844-BD6F-CF93287A6A41}";
constexpr wchar_t kMessageWindowClassName[] =
    L"Notepad.SingleInstance.Msg.{6F0E60BA-5F2D-4844-BD6F-CF93287A6A41}";

// Identifies our WM_COPYDATA payload (double-null-terminated UTF-16 paths).
constexpr DWORD kCopyDataId = 1;

// Converts a UTF-8 string to UTF-16. Returns an empty string on failure.
std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8_string.data(),
                                     static_cast<int>(utf8_string.size()),
                                     nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8_string.data(),
                        static_cast<int>(utf8_string.size()), result.data(),
                        length);
  return result;
}

// Converts a UTF-8 path to an absolute UTF-16 path using this process's
// working directory. The receiving instance may have a different one.
std::wstring AbsolutePathFromUtf8(const std::string& utf8_path) {
  const std::wstring path = Utf16FromUtf8(utf8_path);
  if (path.empty()) {
    return path;
  }
  const DWORD required =
      ::GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
  if (required == 0) {
    return path;
  }
  std::wstring absolute(static_cast<size_t>(required), L'\0');
  const DWORD length = ::GetFullPathNameW(path.c_str(), required,
                                          absolute.data(), nullptr);
  if (length == 0 || length >= required) {
    return path;
  }
  absolute.resize(length);
  return absolute;
}

}  // namespace

SingleInstance::~SingleInstance() {
  if (message_window_ != nullptr) {
    ::DestroyWindow(message_window_);
    message_window_ = nullptr;
  }
  if (mutex_ != nullptr) {
    ::CloseHandle(mutex_);
    mutex_ = nullptr;
  }
}

bool SingleInstance::Acquire() {
  mutex_ = ::CreateMutexW(nullptr, FALSE, kMutexName);
  if (mutex_ == nullptr) {
    // Mutex creation failed; fall back to allowing multiple instances.
    return true;
  }
  return ::GetLastError() != ERROR_ALREADY_EXISTS;
}

bool SingleInstance::ForwardToFirstInstance(
    const std::vector<std::string>& args) {
  // The first instance may still be starting up; retry briefly before
  // giving up (caller then launches a regular window).
  HWND target = nullptr;
  for (int attempt = 0; attempt < 40 && target == nullptr; ++attempt) {
    target = ::FindWindowW(kMessageWindowClassName, nullptr);
    if (target == nullptr) {
      ::Sleep(50);
    }
  }
  if (target == nullptr) {
    return false;
  }

  // Build a double-null-terminated UTF-16 multi-string of paths.
  std::wstring payload;
  for (const auto& arg : args) {
    payload += AbsolutePathFromUtf8(arg);
    payload.push_back(L'\0');
  }
  payload.push_back(L'\0');

  COPYDATASTRUCT copy_data = {};
  copy_data.dwData = kCopyDataId;
  copy_data.cbData = static_cast<DWORD>(payload.size() * sizeof(wchar_t));
  copy_data.lpData = const_cast<wchar_t*>(payload.data());
  const LRESULT result = ::SendMessageW(
      target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data));
  return result == TRUE;
}

bool SingleInstance::CreateMessageWindow(HWND main_window,
                                         FilesCallback callback) {
  main_window_ = main_window;
  callback_ = std::move(callback);

  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = &SingleInstance::MessageWindowProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.lpszClassName = kMessageWindowClassName;
  if (!::RegisterClassW(&window_class) &&
      ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  message_window_ = ::CreateWindowExW(
      0, kMessageWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
      window_class.hInstance, this);
  return message_window_ != nullptr;
}

LRESULT CALLBACK SingleInstance::MessageWindowProc(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(
        hwnd, GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
    return ::DefWindowProcW(hwnd, message, wparam, lparam);
  }
  auto* self = reinterpret_cast<SingleInstance*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->HandleMessage(hwnd, message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT SingleInstance::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case WM_COPYDATA: {
      auto* copy_data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (copy_data == nullptr || copy_data->dwData != kCopyDataId ||
          copy_data->lpData == nullptr ||
          copy_data->cbData < sizeof(wchar_t) ||
          copy_data->cbData % sizeof(wchar_t) != 0) {
        break;
      }
      // Parse the double-null-terminated UTF-16 multi-string.
      std::vector<std::string> files;
      auto* data = static_cast<const wchar_t*>(copy_data->lpData);
      size_t count = copy_data->cbData / sizeof(wchar_t);
      size_t i = 0;
      while (i < count && data[i] != L'\0') {
        size_t start = i;
        while (i < count && data[i] != L'\0') {
          ++i;
        }
        files.push_back(
            Utf8FromUtf16(std::wstring(data + start, i - start).c_str()));
        ++i;  // skip the terminator
      }
      if (callback_) {
        callback_(files);
      }
      if (main_window_ != nullptr) {
        if (::IsIconic(main_window_)) {
          ::ShowWindow(main_window_, SW_RESTORE);
        }
        ::SetForegroundWindow(main_window_);
      }
      return TRUE;
    }
    case WM_DESTROY:
      return 0;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}