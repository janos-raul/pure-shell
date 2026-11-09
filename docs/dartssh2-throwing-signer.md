# dartssh2: a throwing `SSHIdentity` signer hangs the login

Status: observed in code review of dartssh2 4.1.0; possible upstream issue,
**not filed**. Pure-Shell works around it (see below).

## What happens

`SSHIdentity.sign` returns `FutureOr<SSHSignature>` and dartssh2 awaits it in
two places (`lib/src/ssh_client.dart`):

- `_authWithNextPublicKey()`: `final signature = await identity.sign(challenge);`
- `_handleUserauthPKOk()` (the `shouldProbe: true` path): same call.

Both methods are `async` and are started without being awaited by the
authentication state machine (`_tryNextAuthMethod`, and the message dispatcher
for `SSH_MSG_USERAUTH_PK_OK`). If the signer throws, for example because the
user dismissed a fingerprint prompt, the error:

- is not caught anywhere and surfaces as an unhandled asynchronous error in
  the zone of the SSH client, and
- leaves the authentication half-finished: no further message is sent, the
  `authenticated` future neither completes nor fails, and the connection just
  sits there until the server's login grace time runs out (or, if
  `authTimeout` is set, until that timer fires).

For hardware-backed keys a thrown error is the natural way to report "the user
cancelled", so this is an easy trap for any external-signer integration.

## Possible upstream fix

Wrap the two `await identity.sign(...)` calls in `try`/`catch`, and on error
fail authentication, e.g. `_authenticated.completeError(SSHAuthAbortError(...))`
and close the transport, so callers get a normal `SSHAuthError` instead of a
hang.

## Pure-Shell's workaround

`SshConnection.buildIdentity` (`lib/core/ssh/ssh_connection.dart`) gives
dartssh2 an identity whose signer **never throws**. Any failure (user
cancelled, lockout, unexpected error) completes our own connect outcome
(`cancelled` / `keyFailed`), closes the client and socket immediately, and the
signer returns a future that never completes. That abandoned future references
the connection object, never the client, and the connection drops its client
and socket references when it finishes.

Covered by `test/ssh_connection_test.dart` ("key login" group): a cancelled
prompt finishes the connect as cancelled within 2 s and nothing is left
holding the transport.
