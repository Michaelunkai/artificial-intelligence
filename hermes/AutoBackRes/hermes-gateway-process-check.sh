#!/usr/bin/env bash
set +e
USER_NAME="${HERMES_WSL_USER:-ubuntu}"
python3 - "$USER_NAME" <<'PY'
import os, pwd, sys
user = sys.argv[1]
try:
    target_uid = pwd.getpwnam(user).pw_uid
except KeyError:
    raise SystemExit(1)

def is_gateway_argv(argv):
    # Match actual Hermes gateway process argv, not shell/tool commands that contain this text.
    for i in range(len(argv) - 2):
        if argv[i].endswith('/hermes') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
        if (
            i + 3 < len(argv)
            and os.path.basename(argv[i]).startswith('python')
            and argv[i + 1:i + 4] == ['-m', 'hermes_cli.main', 'gateway']
            and i + 4 < len(argv)
            and argv[i + 4] == 'run'
        ):
            return True
        if (
            argv[i].endswith('/hermes_cli/main.py')
            and argv[i + 1:i + 3] == ['gateway', 'run']
        ):
            return True
    return False

for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    proc = f'/proc/{name}'
    try:
        if os.stat(proc).st_uid != target_uid:
            continue
        argv = [x.decode('utf-8', 'ignore') for x in open(f'{proc}/cmdline', 'rb').read().split(b'\0') if x]
    except Exception:
        continue
    if is_gateway_argv(argv):
        print(name)
        raise SystemExit(0)
raise SystemExit(1)
PY
