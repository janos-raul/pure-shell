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
# Usage: tool/test-sshd.sh [start|stop|reset|fingerprints|status]
#   start         build the image if needed, start the container (default)
#   stop          stop and remove the container
#   reset         recreate the container: new host keys
#   fingerprints  print the host key fingerprints (ssh-keygen -lf)
#   status        show whether the container is running
set -euo pipefail

NAME=pureshell-test-sshd
IMAGE=pureshell-test-sshd
PORT=2222
TEST_USER=test
TEST_PASSWORD=pureshell-test   # throwaway, only reachable from 127.0.0.1
LOGIN_GRACE_TIME=${LOGIN_GRACE_TIME:-30}

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
CMD ["sh", "-c", "ssh-keygen -A && exec /usr/sbin/sshd -D -e -o LoginGraceTime=\$LOGIN_GRACE_TIME"]
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
    docker run -d --name "$NAME" -e "LOGIN_GRACE_TIME=$LOGIN_GRACE_TIME" -p "127.0.0.1:$PORT:22" "$IMAGE" >/dev/null
    sleep 2
  fi
  echo "sshd on 127.0.0.1:$PORT (emulator: 10.0.2.2:$PORT), LoginGraceTime ${LOGIN_GRACE_TIME}s, user '$TEST_USER', password '$TEST_PASSWORD'"
  echo "host keys:"
  fingerprints
}

case "${1:-start}" in
  start) start ;;
  stop) docker rm -f "$NAME" >/dev/null && echo stopped ;;
  reset) docker rm -f "$NAME" >/dev/null 2>&1 || true; start ;;
  fingerprints) fingerprints ;;
  status) docker ps -f "name=^$NAME\$" ;;
  *) echo "usage: $0 [start|stop|reset|fingerprints|status]" >&2; exit 1 ;;
esac
