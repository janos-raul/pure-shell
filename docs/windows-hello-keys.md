# Windows Hello SSH keys (spike)

Branch `windows-build`. Goal: the Windows counterpart of the Android StrongBox
key: non-exportable, hardware-backed, every use gated by Windows Hello and
enforced by Windows, not by the app.

API: `Windows.Security.Credentials.KeyCredentialManager` ("Passport" keys).

## What Microsoft's documentation says (checked 2026-11-11)

| Question | Answer | Source |
|---|---|---|
| Key type / size | RSA 2048 only. "Represents a key credential, an RSA, 2048-bit, asymmetric key." | [KeyCredential class][kc] |
| Signature produced by `RequestSignAsync` | RSASSA-PKCS1-v1_5 with SHA-256: "We are using SHA256 as the hash algorithm and Pkcs1 for SignaturePadding"; the sample verifies with `VerifyData(originalChallenge, sig, SHA256, Pkcs1)`. | [Windows Hello][hello] |
| Hashes the input itself? | Yes: the verifier hashes the original challenge (`VerifyData`, not `VerifyHash`), so the app passes the raw data, never a digest. | [Windows Hello][hello] |
| SSH mapping | Exactly `rsa-sha2-256` (RFC 8332). `rsa-sha2-512` is not possible; `ssh-rsa` (SHA-1) is never used. | |
| Private key exportable? | No API returns it: "There is no way for the app to access the created private keys directly." | [Windows Hello][hello] |
| TPM-backed? | Only if the device has a TPM: "if there is no TPM chip available, the OS will create the key pair in code" (software-protected). TPM backing is provable only through attestation (`GetAttestationAsync`, TPM 2.0 only). | [Windows Hello][hello] |
| Hello on every sign? | `RequestSignAsync` "Prompts the user to cryptographically sign data"; the docs say the call causes "Windows to request the user's PIN or biometrics". No caching is documented. (Measured below.) | [RequestSignAsync][sign] |
| Hello not set up | `KeyCredentialManager.IsSupportedAsync()` returns false. | [Windows Hello][hello] |
| Unpackaged Win32 apps | Works (Chromium uses it), but the plain calls show the prompt *behind* Win32 windows (Chromium works around it). SDK 26100 adds `RequestCreateForWindowAsync(WindowId, ...)` and `RequestSignForWindowAsync(WindowId, ...)`, which own the prompt to the app window. | [Chromium][chromium], [RequestSignForWindowAsync][signwin] |
| Listing keys | No enumeration API; keys are opened by name (`OpenAsync`). The app keeps its own index. | [KeyCredential class][kc] |

[kc]: https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential
[hello]: https://learn.microsoft.com/en-us/windows/apps/develop/security/windows-hello
[sign]: https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential.requestsignasync
[signwin]: https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential.requestsignforwindowasync
[chromium]: https://chromium.googlesource.com/chromium/src/+/8addab97c51649a2d10fbf0ecfe7a968908901b6/crypto/user_verifying_key_win.cc

### Differences from the Android StrongBox key

- RSA-2048 instead of EC P-256 (`ssh-rsa` key, `rsa-sha2-256` signatures).
- On a machine without a TPM the "Hello key" is a software key; the app must
  check attestation before calling it hardware-backed.
- Windows Hello itself can be a PIN only; the TPM rate-limits PIN guesses.

## Implementation

- Native: `windows/runner/hello_keystore.{h,cpp}`, C++/WinRT, channel
  `eu.pureshell.app/hello_keys` (isSupported, create, exists, publicKey, sign,
  delete). WinRT calls run on a worker thread; replies return on the platform
  thread through a message-only window. Prompts are owned by the app window
  (`*ForWindowAsync`, falling back to the plain calls on older Windows).
