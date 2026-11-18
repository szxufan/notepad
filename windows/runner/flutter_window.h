#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Forwards file paths from another instance to the Dart side. Paths are
  // queued until Dart signals readiness on the "notepad/app" channel.
  void ForwardFilesToDart(const std::vector<std::string>& paths);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Creates the "notepad/app" channel used for single-instance file
  // forwarding and the Dart readiness handshake.
  void SetUpAppChannel();

  // Invokes "openFiles" on the Dart side with |paths|.
  void SendFilesToDart(const std::vector<std::string>& paths);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel for native -> Dart file forwarding.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;

  // Whether Dart has registered its handler and is ready to receive files.
  bool dart_ready_ = false;

  // File batches received before Dart was ready.
  std::vector<std::vector<std::string>> pending_files_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
