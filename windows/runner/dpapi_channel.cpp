// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#include "dpapi_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dpapi.h>

#include <string>
#include <vector>

#pragma comment(lib, "crypt32.lib")

namespace {

using flutter::EncodableValue;

bool Run(bool protect, const std::vector<uint8_t>& in,
         std::vector<uint8_t>& out) {
  DATA_BLOB input{static_cast<DWORD>(in.size()),
                  const_cast<BYTE*>(in.data())};
  DATA_BLOB output{};
  const BOOL ok =
      protect ? CryptProtectData(&input, nullptr, nullptr, nullptr, nullptr,
                                 CRYPTPROTECT_UI_FORBIDDEN, &output)
              : CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                                   CRYPTPROTECT_UI_FORBIDDEN, &output);
  if (!ok) return false;
  out.assign(output.pbData, output.pbData + output.cbData);
  // Plain text never stays in freed memory longer than needed.
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return true;
}

}  // namespace

DpapiChannel::DpapiChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "eu.pureshell.app/dpapi",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string& method = call.method_name();
    const bool protect = method == "protect";
    if (!protect && method != "unprotect") {
      result->NotImplemented();
      return;
    }
    const auto* data = std::get_if<std::vector<uint8_t>>(call.arguments());
    if (!data) {
      result->Error("failed", "bytes expected");
      return;
    }
    std::vector<uint8_t> out;
    if (!Run(protect, *data, out)) {
      result->Error("failed", std::to_string(GetLastError()));
      return;
    }
    result->Success(EncodableValue(out));
  });
}
