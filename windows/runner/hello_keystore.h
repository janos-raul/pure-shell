// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef RUNNER_HELLO_KEYSTORE_H_
#define RUNNER_HELLO_KEYSTORE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <functional>
#include <memory>

// SPIKE: Windows Hello key credentials (KeyCredentialManager) over the
// "eu.pureshell.app/hello_keys" channel. RSA-2048, private key held by Windows
// (TPM when present), every signature needs Windows Hello. Methods:
//   isSupported -> bool
//   create {alias} -> {publicKey: BCRYPT_RSAPUBLIC_BLOB, attestation: String}
//   exists {alias} -> bool          (no prompt)
//   publicKey {alias} -> BCRYPT_RSAPUBLIC_BLOB
//   sign {alias, data} -> raw RSASSA-PKCS1-v1_5 / SHA-256 signature
//   delete {alias}
// Errors: PlatformException code cancelled | lockout | unavailable |
// key_invalid | exists | busy | failed.
class HelloKeystore {
 public:
  HelloKeystore(flutter::BinaryMessenger* messenger, HWND owner);
  ~HelloKeystore();

 private:
  using Result =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>;

  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result);

  // Runs |work| on a worker thread; its reply runs back on this thread.
  void RunAsync(std::function<std::function<void()>()> work);
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND owner_;
  HWND dispatch_ = nullptr;
  std::atomic<bool> prompting_{false};
};

#endif  // RUNNER_HELLO_KEYSTORE_H_
