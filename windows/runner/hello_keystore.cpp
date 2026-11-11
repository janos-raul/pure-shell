// PureShell - an open-source SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later

#include "hello_keystore.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.Core.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.UI.h>

#include <chrono>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Security::Credentials::KeyCredential;
using winrt::Windows::Security::Credentials::KeyCredentialAttestationStatus;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::Core::
    CryptographicPublicKeyBlobType;
using winrt::Windows::Storage::Streams::Buffer;
using winrt::Windows::Storage::Streams::IBuffer;

constexpr UINT kRunReply = WM_APP + 0x4E1;
constexpr wchar_t kClassName[] = L"PureShellHelloDispatch";

// An error that becomes a PlatformException code.
struct Failure {
  std::string code;
};

std::string StatusCode(KeyCredentialStatus s) {
  switch (s) {
    case KeyCredentialStatus::UserCanceled:
    case KeyCredentialStatus::UserPrefersPassword:
      return "cancelled";
    case KeyCredentialStatus::NotFound:
      return "key_invalid";
    case KeyCredentialStatus::SecurityDeviceLocked:
      return "lockout";
    case KeyCredentialStatus::CredentialAlreadyExists:
      return "exists";
    default:
      return "failed";
  }
}

std::vector<uint8_t> ToBytes(const IBuffer& b) {
  std::vector<uint8_t> v(b.Length());
  if (!v.empty()) memcpy(v.data(), b.data(), v.size());
  return v;
}

IBuffer FromBytes(const std::vector<uint8_t>& v) {
  Buffer b(static_cast<uint32_t>(v.size()));
  if (!v.empty()) memcpy(b.data(), v.data(), v.size());
  b.Length(static_cast<uint32_t>(v.size()));
  return b;
}

std::wstring Wide(const std::string& s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

// Windows.UI.WindowId for the app window, so the Hello prompt is owned by it
// (the plain calls show it behind the window). Resolved at run time: older
// Windows has neither the export nor the *ForWindow* methods.
winrt::Windows::UI::WindowId WindowIdFor(HWND hwnd) {
  using Fn = HRESULT(WINAPI*)(HWND, winrt::Windows::UI::WindowId*);
  static Fn fn = [] {
    HMODULE m = LoadLibraryExW(L"Windows.UI.dll", nullptr,
                               LOAD_LIBRARY_SEARCH_SYSTEM32);
    return m ? reinterpret_cast<Fn>(GetProcAddress(m, "GetWindowIdFromWindow"))
             : nullptr;
  }();
  winrt::Windows::UI::WindowId id{reinterpret_cast<uint64_t>(hwnd)};
  if (fn) fn(hwnd, &id);
  return id;
}

KeyCredential Open(const std::wstring& alias) {
  auto r = KeyCredentialManager::OpenAsync(alias).get();
  if (r.Status() != KeyCredentialStatus::Success) {
    throw Failure{StatusCode(r.Status())};
  }
  return r.Credential();
}

std::vector<uint8_t> PublicBlob(const KeyCredential& k) {
  return ToBytes(
      k.RetrievePublicKey(CryptographicPublicKeyBlobType::BCryptPublicKey));
}

std::string Attestation(const KeyCredential& k) {
  try {
    auto op = k.GetAttestationAsync();
    // Attestation can need the network (AIK certificate); do not hang on it.
    if (op.wait_for(std::chrono::seconds(20)) !=
        winrt::Windows::Foundation::AsyncStatus::Completed) {
      op.Cancel();
      return "timeout";
    }
    switch (op.GetResults().Status()) {
      case KeyCredentialAttestationStatus::Success:
        return "success";
      case KeyCredentialAttestationStatus::TemporaryFailure:
        return "temporaryFailure";
      case KeyCredentialAttestationStatus::NotSupported:
        return "notSupported";
      default:
        return "unknownError";
    }
  } catch (...) {
    return "unknownError";
  }
}

const std::string* StringArg(const EncodableValue* args, const char* name) {
  auto* m = std::get_if<EncodableMap>(args);
  if (!m) return nullptr;
  auto it = m->find(EncodableValue(name));
  return it == m->end() ? nullptr : std::get_if<std::string>(&it->second);
}

const std::vector<uint8_t>* BytesArg(const EncodableValue* args,
                                     const char* name) {
  auto* m = std::get_if<EncodableMap>(args);
  if (!m) return nullptr;
  auto it = m->find(EncodableValue(name));
  return it == m->end() ? nullptr
                        : std::get_if<std::vector<uint8_t>>(&it->second);
}

}  // namespace

HelloKeystore::HelloKeystore(flutter::BinaryMessenger* messenger, HWND owner)
    : owner_(owner) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  RegisterClassW(&wc);
  dispatch_ = CreateWindowW(kClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                            nullptr, wc.hInstance, nullptr);

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "eu.pureshell.app/hello_keys",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) { Handle(call, std::move(result)); });
}

HelloKeystore::~HelloKeystore() {
  channel_->SetMethodCallHandler(nullptr);
  if (dispatch_) DestroyWindow(dispatch_);
}

LRESULT CALLBACK HelloKeystore::WndProc(HWND hwnd, UINT msg, WPARAM wp,
                                        LPARAM lp) {
  if (msg == kRunReply) {
    std::unique_ptr<std::function<void()>> reply(
        reinterpret_cast<std::function<void()>*>(lp));
    (*reply)();
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

void HelloKeystore::RunAsync(std::function<std::function<void()>()> work) {
  HWND dispatch = dispatch_;
  std::thread([work = std::move(work), dispatch] {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    auto reply = new std::function<void()>(work());
    if (!PostMessageW(dispatch, kRunReply, 0, reinterpret_cast<LPARAM>(reply))) {
      delete reply;  // window gone: the engine is shutting down
    }
    winrt::uninit_apartment();
  }).detach();
}

void HelloKeystore::Handle(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> raw) {
  Result result(std::move(raw));
  const std::string method = call.method_name();
  const EncodableValue* args = call.arguments();
  const std::string* alias_arg = StringArg(args, "alias");
  const std::wstring alias = alias_arg ? Wide(*alias_arg) : L"";
  const bool prompts = method == "create" || method == "sign";

  if (method != "isSupported" && alias.empty()) {
    result->Error("failed", "alias missing");
    return;
  }
  if (prompts && prompting_.exchange(true)) {
    result->Error("busy");
    return;
  }

  std::vector<uint8_t> data;
  if (method == "sign") {
    auto* d = BytesArg(args, "data");
    if (!d) {
      prompting_ = false;
      result->Error("failed", "data missing");
      return;
    }
    data = *d;
  }

  HWND owner = owner_;
  RunAsync([this, method, alias, data, owner, prompts,
            result]() -> std::function<void()> {
    auto done = [this, prompts](std::function<void()> f) {
      return [this, prompts, f] {
        if (prompts) prompting_ = false;
        f();
      };
    };
    try {
      if (method == "isSupported") {
        bool ok = KeyCredentialManager::IsSupportedAsync().get();
        return done([result, ok] { result->Success(EncodableValue(ok)); });
      }
      if (method == "exists") {
        auto r = KeyCredentialManager::OpenAsync(alias).get();
        bool ok = r.Status() == KeyCredentialStatus::Success;
        return done([result, ok] { result->Success(EncodableValue(ok)); });
      }
      if (method == "publicKey") {
        auto blob = PublicBlob(Open(alias));
        return done([result, blob] { result->Success(EncodableValue(blob)); });
      }
      if (method == "delete") {
        KeyCredentialManager::DeleteAsync(alias).get();
        return done([result] { result->Success(); });
      }
      if (method == "create") {
        if (!KeyCredentialManager::IsSupportedAsync().get()) {
          throw Failure{"unavailable"};
        }
        winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult r{
            nullptr};
        try {
          r = KeyCredentialManager::RequestCreateForWindowAsync(
                  WindowIdFor(owner), alias,
                  KeyCredentialCreationOption::FailIfExists)
                  .get();
        } catch (const winrt::hresult_error&) {
          // Older Windows: no *ForWindow* overload.
          r = KeyCredentialManager::RequestCreateAsync(
                  alias, KeyCredentialCreationOption::FailIfExists)
                  .get();
        }
        if (r.Status() != KeyCredentialStatus::Success) {
          throw Failure{StatusCode(r.Status())};
        }
        auto key = r.Credential();
        EncodableMap m{
            {EncodableValue("publicKey"), EncodableValue(PublicBlob(key))},
            {EncodableValue("attestation"), EncodableValue(Attestation(key))},
        };
        return done([result, m] { result->Success(EncodableValue(m)); });
      }
      if (method == "sign") {
        auto key = Open(alias);
        winrt::Windows::Security::Credentials::KeyCredentialOperationResult r{
            nullptr};
        try {
          r = key.RequestSignForWindowAsync(WindowIdFor(owner), FromBytes(data))
                  .get();
        } catch (const winrt::hresult_error&) {
          r = key.RequestSignAsync(FromBytes(data)).get();
        }
        if (r.Status() != KeyCredentialStatus::Success) {
          throw Failure{StatusCode(r.Status())};
        }
        auto sig = ToBytes(r.Result());
        return done([result, sig] { result->Success(EncodableValue(sig)); });
      }
      return done([result] { result->NotImplemented(); });
    } catch (const Failure& f) {
      std::string code = f.code;
      return done([result, code] { result->Error(code); });
    } catch (const winrt::hresult_error& e) {
      // The HRESULT only, never data.
      char hr[16];
      snprintf(hr, sizeof hr, "0x%08X", static_cast<unsigned>(e.code().value));
      std::string detail = hr;
      return done([result, detail] { result->Error("failed", detail); });
    } catch (...) {
      return done([result] { result->Error("failed"); });
    }
  });
}
