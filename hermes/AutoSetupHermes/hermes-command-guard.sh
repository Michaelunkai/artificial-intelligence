#!/usr/bin/env bash
set -euo pipefail

real_bin="${HERMES_REAL_BIN:-/home/ubuntu/.hermes/hermes-agent/venv/bin/hermes}"

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

if [[ "$is_protected_gateway_mutation" == "1" && "${HERMES_ALLOW_GATEWAY_STOP:-}" != "1" ]]; then
  echo "BLOCKED: Hermes gateway stop/restart is protected to prevent mid-work disconnects." >&2
  echo "Use the Windows tray Manual Stop/Restart controls, or set HERMES_ALLOW_GATEWAY_STOP=1 only for an intentional manual operation." >&2
  exit 126
fi

exec "$real_bin" "$@"
