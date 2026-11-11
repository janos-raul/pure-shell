// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef RUNNER_WINDOW_CHANNELS_H_
#define RUNNER_WINDOW_CHANNELS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Window-level platform channels for the main window:
//   "eu.pureshell.app/window_events" (native -> Dart): sessionLock,
//     sessionUnlock, minimized, restored. The desktop app lock is driven by
//     these instead of focus changes.
//   "eu.pureshell.app/window" setSecure {secure}: screen-capture blocking
//     (SetWindowDisplayAffinity), the "Allow screenshots" setting. Blocked
//     from the moment the window exists, like FLAG_SECURE on Android.
//   "eu.pureshell.app/clipboard" copy {text}: copies terminal text marked so
//     it stays out of clipboard history, cloud clipboard sync and clipboard
//     monitors (the Android "sensitive clip").
class WindowChannels {
 public:
  WindowChannels(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowChannels();

  // Called for every message of the top-level window (observes only).
  void OnMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void Send(const char* event);
  bool SetCaptureBlocked(bool blocked);
  bool CopySensitive(const std::string& utf8);

  HWND window_;
  bool minimized_ = false;
  bool session_registered_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_ch_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> clipboard_;
};

#endif  // RUNNER_WINDOW_CHANNELS_H_
