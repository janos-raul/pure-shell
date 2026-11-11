#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "dpapi_channel.h"
#include "hello_keystore.h"
#include "win32_window.h"
#include "window_channels.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Windows Hello key credentials (spike).
  std::unique_ptr<HelloKeystore> hello_keystore_;

  // DPAPI for the app's encrypted store.
  std::unique_ptr<DpapiChannel> dpapi_;

  // Session lock / minimise events, capture blocking, clipboard.
  std::unique_ptr<WindowChannels> window_channels_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
