// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#include "window_channels.h"

#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

#include <string>

#pragma comment(lib, "wtsapi32.lib")

using flutter::EncodableValue;

WindowChannels::WindowChannels(flutter::BinaryMessenger* messenger,
                               HWND window)
    : window_(window) {
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  events_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "eu.pureshell.app/window_events", &codec);
  // WM_WTSSESSION_CHANGE for this session: Win+L, lock on sleep, etc.
  session_registered_ =
      WTSRegisterSessionNotification(window_, NOTIFY_FOR_THIS_SESSION) != 0;
  minimized_ = IsIconic(window_) != 0;

  SetCaptureBlocked(true);  // until Dart applies the stored choice
  window_ch_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "eu.pureshell.app/window", &codec);
  window_ch_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setSecure") {
      result->NotImplemented();
      return;
    }
    bool secure = true;  // when in doubt, block
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(EncodableValue("secure"));
      if (it != args->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) secure = *b;
      }
    }
    if (SetCaptureBlocked(secure)) {
      result->Success();
    } else {
      result->Error("failed", std::to_string(GetLastError()));
    }
  });
}

bool WindowChannels::SetCaptureBlocked(bool blocked) {
  if (!blocked) return SetWindowDisplayAffinity(window_, WDA_NONE) != 0;
  // Windows 10 2004+: the window is left out of captures. Older Windows:
  // WDA_MONITOR, captures show it black.
  if (SetWindowDisplayAffinity(window_, WDA_EXCLUDEFROMCAPTURE)) return true;
  return SetWindowDisplayAffinity(window_, WDA_MONITOR) != 0;
}

WindowChannels::~WindowChannels() {
  if (session_registered_) WTSUnRegisterSessionNotification(window_);
}

void WindowChannels::Send(const char* event) {
  events_->InvokeMethod(event, nullptr);
}

void WindowChannels::OnMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_WTSSESSION_CHANGE:
      if (wparam == WTS_SESSION_LOCK) Send("sessionLock");
      if (wparam == WTS_SESSION_UNLOCK) Send("sessionUnlock");
      break;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED && !minimized_) {
        minimized_ = true;
        Send("minimized");
      } else if ((wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED) &&
                 minimized_) {
        minimized_ = false;
        Send("restored");
      }
      break;
  }
}
