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

  clipboard_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "eu.pureshell.app/clipboard", &codec);
  clipboard_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string* text = nullptr;
    if (args) {
      auto it = args->find(EncodableValue("text"));
      if (it != args->end()) text = std::get_if<std::string>(&it->second);
    }
    if (call.method_name() != "copy" || !text) {
      result->NotImplemented();
      return;
    }
    if (CopySensitive(*text)) {
      result->Success();
    } else {
      result->Error("failed");  // never the text
    }
  });
}

namespace {

// Puts a DWORD under a registered clipboard format (clipboard must be open).
void SetDwordFormat(const wchar_t* name, DWORD value) {
  const UINT format = RegisterClipboardFormatW(name);
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (!format || !mem) return;
  *static_cast<DWORD*>(GlobalLock(mem)) = value;
  GlobalUnlock(mem);
  if (!SetClipboardData(format, mem)) GlobalFree(mem);
}

}  // namespace

bool WindowChannels::CopySensitive(const std::string& utf8) {
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                    static_cast<int>(utf8.size()), nullptr, 0);
  HGLOBAL text = GlobalAlloc(GMEM_MOVEABLE, (n + 1) * sizeof(wchar_t));
  if (!text) return false;
  auto* dst = static_cast<wchar_t*>(GlobalLock(text));
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      dst, n);
  dst[n] = L'\0';
  GlobalUnlock(text);

  // Another program may hold the clipboard for a moment.
  bool open = false;
  for (int i = 0; i < 10 && !(open = OpenClipboard(window_) != 0); ++i) {
    Sleep(10);
  }
  if (!open) {
    GlobalFree(text);
    return false;
  }
  EmptyClipboard();
  const bool ok = SetClipboardData(CF_UNICODETEXT, text) != nullptr;
  if (!ok) GlobalFree(text);
  // Documented clipboard formats: their presence keeps the clip out of
  // clipboard monitors and history (Win+V) and out of cloud clipboard sync.
  SetDwordFormat(L"ExcludeClipboardContentFromMonitorProcessing", 0);
  SetDwordFormat(L"CanIncludeInClipboardHistory", 0);
  SetDwordFormat(L"CanUploadToCloudClipboard", 0);
  CloseClipboard();
  return ok;
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
