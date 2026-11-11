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

// Window-level platform channels for the main window:
//   "eu.pureshell.app/window_events" (native -> Dart): sessionLock,
//     sessionUnlock, minimized, restored. The desktop app lock is driven by
//     these instead of focus changes.
class WindowChannels {
 public:
  WindowChannels(flutter::BinaryMessenger* messenger, HWND window);
  ~WindowChannels();

  // Called for every message of the top-level window (observes only).
  void OnMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void Send(const char* event);

  HWND window_;
  bool minimized_ = false;
  bool session_registered_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> events_;
};

#endif  // RUNNER_WINDOW_CHANNELS_H_
