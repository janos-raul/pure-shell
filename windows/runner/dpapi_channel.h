// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef RUNNER_DPAPI_CHANNEL_H_
#define RUNNER_DPAPI_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// "eu.pureshell.app/dpapi": protect / unprotect bytes with the Windows Data
// Protection API for the current user (no prompt, no extra entropy). The app
// stores its settings, hosts and key metadata as one DPAPI-protected file in
// Local AppData (lib/core/storage/windows_secure_store.dart).
class DpapiChannel {
 public:
  explicit DpapiChannel(flutter::BinaryMessenger* messenger);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DPAPI_CHANNEL_H_
