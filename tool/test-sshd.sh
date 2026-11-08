#!/usr/bin/env bash
# PureShell - an open-source Android SSH client
# Copyright (C) 2026 Janos-Raul
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Throwaway OpenSSH server in Docker for testing PureShell on an emulator.
# Bound to 127.0.0.1:2222 only (the Android emulator reaches it as 10.0.2.2).
# Password login for the throwaway user below. LoginGraceTime defaults to 30 s
# (override: LOGIN_GRACE_TIME=10 tool/test-sshd.sh reset) so the "slow Trust
# prompt" test takes seconds instead of two minutes.
#
# Usage: tool/test-sshd.sh [start|stop|reset|fingerprints|status|add-key|clear-keys]
#   start         build the image if needed, start the container (default)
#   stop          stop and remove the container
#   reset         recreate the container: new host keys, and no authorized keys
#   fingerprints  print the host key fingerprints (ssh-keygen -lf)
#   status        show whether the container is running
#   add-key FILE  add the public key line in FILE ('-' = stdin) to the test
#                 user's authorized_keys (lost on reset)
#   clear-keys    empty the test user's authorized_keys
#
# Environment (applies to start/reset):
#   LOGIN_GRACE_TIME=10   seconds the server waits for a login (default 30)
#   PASSWORD_AUTH=no      disable password login, to prove key login works
#                         without a password (default yes)
set -euo pipefail

NAME=pureshell-test-sshd
IMAGE=pureshell-test-sshd
PORT=2222
TEST_USER=test
TEST_PASSWORD=pureshell-test   # throwaway, only reachable from 127.0.0.1
LOGIN_GRACE_TIME=${LOGIN_GRACE_TIME:-30}
PASSWORD_AUTH=${PASSWORD_AUTH:-yes}

build() {
  docker image inspect "$IMAGE" >/dev/null 2>&1 && return
  docker build -q -t "$IMAGE" - <<DOCKERFILE
FROM alpine:3.20
RUN apk add --no-cache openssh-server shadow procps iputils htop vim \\
 && adduser -D -s /bin/sh $TEST_USER \\
 && echo '$TEST_USER:$TEST_PASSWORD' | chpasswd \\
 && printf '%s\n' \\
    'PasswordAuthentication yes' \\
    'PermitRootLogin no' \\
    'KbdInteractiveAuthentication no' \\
    > /etc/ssh/sshd_config.d/test.conf
# Host keys are generated at container start, so every new container (reset)
# gets new ones.
CMD ["sh", "-c", "ssh-keygen -A && exec /usr/sbin/sshd -D -e -o LoginGraceTime=\$LOGIN_GRACE_TIME -o PasswordAuthentication=\$PASSWORD_AUTH"]
DOCKERFILE
}

fingerprints() {
  for f in $(docker exec "$NAME" sh -c 'ls /etc/ssh/ssh_host_*_key.pub'); do
    docker exec "$NAME" ssh-keygen -lf "$f"
  done
}

start() {
  build
  if docker ps -q -f "name=^$NAME\$" | grep -q .; then
    echo "already running"
  else
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" -e "LOGIN_GRACE_TIME=$LOGIN_GRACE_TIME" -e "PASSWORD_AUTH=$PASSWORD_AUTH" -p "127.0.0.1:$PORT:22" "$IMAGE" >/dev/null
    sleep 2
  fi
  echo "sshd on 127.0.0.1:$PORT (emulator: 10.0.2.2:$PORT), LoginGraceTime ${LOGIN_GRACE_TIME}s, password auth ${PASSWORD_AUTH}, user '$TEST_USER', password '$TEST_PASSWORD'"
  echo "host keys:"
  fingerprints
}

add_key() {
  local src=${1:-}
  [ -n "$src" ] || { echo "usage: $0 add-key FILE|-" >&2; exit 1; }
  local line
  if [ "$src" = "-" ]; then line=$(cat); else line=$(cat "$src"); fi
  case "$line" in
    ssh-*|ecdsa-*|sk-*) ;;
    *) echo "that does not look like a public key line" >&2; exit 1 ;;
  esac
  printf '%s\n' "$line" | docker exec -i "$NAME" sh -c '
    umask 077
    mkdir -p /home/test/.ssh
    cat >> /home/test/.ssh/authorized_keys
    chown -R test:test /home/test/.ssh
    chmod 700 /home/test/.ssh
    chmod 600 /home/test/.ssh/authorized_keys'
  echo "added; $(docker exec "$NAME" sh -c 'wc -l < /home/test/.ssh/authorized_keys') key(s) authorized for '$TEST_USER'"
}

case "${1:-start}" in
  start) start ;;
  stop) docker rm -f "$NAME" >/dev/null && echo stopped ;;
  reset) docker rm -f "$NAME" >/dev/null 2>&1 || true; start ;;
  fingerprints) fingerprints ;;
  add-key) add_key "${2:-}" ;;
  clear-keys) docker exec "$NAME" sh -c ': > /home/test/.ssh/authorized_keys' && echo cleared ;;
  status) docker ps -f "name=^$NAME\$" ;;
  *) echo "usage: $0 [start|stop|reset|fingerprints|status|add-key|clear-keys]" >&2; exit 1 ;;
esac
