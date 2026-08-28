#!/usr/bin/env bash
# Switch email between the Mailpit sink and a real relay, on the box.
#
#   ./mail-mode.sh sink    — nothing reaches a real inbox; read it at /mailpit
#   ./mail-mode.sh real    — deliver to actual customer addresses
#   ./mail-mode.sh status  — which is active, and whether the relay is answering
#
# It exists because the two modes differ only by which lines in .env are commented, and doing that
# by hand at speed is how a test blast reaches real customers — or how a launch quietly sinkholes
# every verification code. One command, and it says which mode it left you in.
#
# The password is NEVER an argument. It is read from the terminal with the echo off, or already in
# .env. An argument would be in the shell history, in the process list while it runs, and in any
# transcript of the session.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/delivery/infra/.env}"
COMPOSE="${COMPOSE:-/opt/delivery/infra/docker-compose.dev.yml}"
KEYS=(SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASSWORD SMTP_AUTH SMTP_STARTTLS EMAIL_FROM SMS_TEST_INBOX)

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 1 ] || usage

active_mode() {
  grep -qE '^SMTP_HOST=(smtp\.|mail\.)' "$ENV_FILE" && echo real || echo sink
}

case "$1" in
  status)
    mode=$(active_mode)
    echo "mode: $mode"
    grep -E '^SMTP_HOST=|^EMAIL_FROM=' "$ENV_FILE" || true
    if [ "$mode" = real ]; then
      host=$(grep -E '^SMTP_HOST=' "$ENV_FILE" | cut -d= -f2)
      port=$(grep -E '^SMTP_PORT=' "$ENV_FILE" | cut -d= -f2)
      # Reachability only. Whether the credentials are accepted is a different question, and the
      # only honest way to answer it is to send something and read the notification log.
      if (echo QUIT; sleep 1) | timeout 8 nc "$host" "$port" 2>/dev/null | head -1 | grep -q '^220'; then
        echo "relay $host:$port is reachable (this says nothing about the password)"
      else
        echo "relay $host:$port did NOT answer"
      fi
    fi
    ;;

  sink)
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
    for k in "${KEYS[@]}"; do sed -i -E "s/^${k}=/#${k}=/" "$ENV_FILE"; done
    docker compose -f "$COMPOSE" up -d --no-deps --force-recreate email-connector sms-connector >/dev/null
    echo "sink. Nothing reaches a real inbox; read it at https://monitoring-dev.youdrop.shop/mailpit"
    ;;

  real)
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
    for k in "${KEYS[@]}"; do sed -i -E "s/^#${k}=/${k}=/" "$ENV_FILE"; done

    # Offer to replace the password, because the usual reason for switching to real mail is that
    # the old one stopped working.
    read -r -p "Set a new SMTP password? [y/N] " reply
    if [ "$reply" = y ] || [ "$reply" = Y ]; then
      read -r -s -p "App password (not echoed): " pw
      echo
      # Written with a temp file and moved into place: an interrupted in-place edit of .env would
      # leave the whole stack without its credentials.
      tmp=$(mktemp)
      grep -v '^SMTP_PASSWORD=' "$ENV_FILE" > "$tmp"
      printf 'SMTP_PASSWORD=%s\n' "$pw" >> "$tmp"
      chmod --reference="$ENV_FILE" "$tmp"
      mv "$tmp" "$ENV_FILE"
      unset pw
    fi

    docker compose -f "$COMPOSE" up -d --no-deps --force-recreate email-connector sms-connector >/dev/null
    echo "real. Send one verification code and read notification.notification_log before trusting it:"
    echo "  a row at FAILED with 'relay authentication failed' means the password, not the network."
    ;;

  *) usage ;;
esac
