#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <functional>
#include <string>
#include <vector>

// Single-instance guard for the notepad app.
//
// The first instance acquires a named mutex and creates a message-only window
// that receives file paths forwarded from subsequent instances. Subsequent
// instances forward their command-line arguments to the first instance and
// exit without creating a window.
class SingleInstance {
 public:
  // Invoked on the first instance when another instance forwards file paths.
  // The list may be empty (second launch without arguments).
  using FilesCallback = std::function<void(const std::vector<std::string>&)>;

  SingleInstance() = default;
  ~SingleInstance();

  // Not copyable or movable (owns Win32 handles).
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // Attempts to acquire the single-instance mutex. Returns true if this is
  // the first instance. If it returns false, call ForwardToFirstInstance().
  bool Acquire();

  // Forwards |args| (UTF-8) to the first instance and brings its main window
  // to the foreground. Returns true if the first instance was found.
  bool ForwardToFirstInstance(const std::vector<std::string>& args);

  // Creates the message-only window that receives forwarded files.
  // |main_window| is brought to the foreground when files arrive.
  // Must be called after a successful Acquire().
  bool CreateMessageWindow(HWND main_window, FilesCallback callback);

 private:
  static LRESULT CALLBACK MessageWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  HANDLE mutex_ = nullptr;
  HWND message_window_ = nullptr;
  HWND main_window_ = nullptr;
  FilesCallback callback_;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_