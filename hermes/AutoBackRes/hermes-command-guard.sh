#!/usr/bin/env bash
set -euo pipefail

real_bin="${HERMES_REAL_BIN:-/home/ubuntu/.hermes/hermes-agent/venv/bin/hermes}"
intent_check="/usr/local/sbin/hermes-check-manual-gateway-intent"

is_protected_gateway_mutation=0
if [[ "${1:-}" == "gateway" ]]; then
  case "${2:-}" in
    stop|restart)
      is_protected_gateway_mutation=1
      ;;
    run)
      for arg in "$@"; do
        if [[ "$arg" == "--replace" ]]; then
          is_protected_gateway_mutation=1
          break
        fi
      done
      ;;
  esac
fi
if [[ "${1:-}" == "update" ]]; then
  is_protected_gateway_mutation=1
fi

if [[ "$is_protected_gateway_mutation" == "1" ]]; then
  if [[ ! -x "$intent_check" ]] || ! "$intent_check" >/dev/null; then
    echo "BLOCKED: Hermes gateway stop/restart/update is protected to prevent mid-work Telegram disconnects." >&2
    echo "Use only the Windows tray Manual Stop/Restart/Update controls; agent/tool commands cannot create manual restart permission." >&2
    exit 126
  fi
fi

exec "$real_bin" "$@"
